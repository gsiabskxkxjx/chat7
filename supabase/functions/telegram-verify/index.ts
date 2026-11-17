// بوت تلغرام لتوثيق رقم الهاتف (Supabase Edge Function).
// الأسرار (Edge Functions > Secrets): TELEGRAM_BOT_TOKEN و TG_WEBHOOK_SECRET
// مهم: عطّل خيار Verify JWT لهذي الدالة بس، لأن تلغرام ما يرسل توكن سوبابيس.
// الحماية: نتحقق من الهيدر السري اللي تحطه وقت setWebhook.
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const TOKEN = Deno.env.get('TELEGRAM_BOT_TOKEN') ?? '';
const SECRET = Deno.env.get('TG_WEBHOOK_SECRET') ?? '';
const enc = new TextEncoder();

async function hmacHex(msg: string, key: string): Promise<string> {
  const k = await crypto.subtle.importKey('raw', enc.encode(key), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  const sig = await crypto.subtle.sign('HMAC', k, enc.encode(msg));
  return Array.from(new Uint8Array(sig)).map((b) => b.toString(16).padStart(2, '0')).join('');
}

async function say(chatId: number, text: string, markup?: Record<string, unknown>) {
  await fetch(`https://api.telegram.org/bot${TOKEN}/sendMessage`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ chat_id: chatId, text, ...(markup ? { reply_markup: markup } : {}) }),
  });
}

Deno.serve(async (req) => {
  // دائماً نرد 200 لتلغرام (غير الأخطاء الصريحة) حتى ما يعيد المحاولة
  if (req.method !== 'POST') return new Response('ok');
  if (!TOKEN || !SECRET) return new Response('not configured', { status: 501 });
  if (req.headers.get('x-telegram-bot-api-secret-token') !== SECRET) {
    return new Response('forbidden', { status: 403 });
  }
  try {
    const sb = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
    const upd = await req.json();
    const msg = upd?.message;
    if (!msg || msg.chat?.type !== 'private') return new Response('ok');
    const chatId: number = msg.chat.id;
    const fromId: number | undefined = msg.from?.id;
    if (typeof fromId !== 'number') return new Response('ok');

    if (typeof msg.text === 'string' && msg.text.startsWith('/start')) {
      const code = (msg.text.split(' ')[1] ?? '').trim();
      const { data } = await sb.rpc('phone_verify_bind', { p_code: code, p_tg: fromId });
      if (data !== true) {
        await say(chatId, 'الرابط منتهي أو غير صحيح. ارجع لتطبيق بيناتنا واضغط «وثّق رقمي» من جديد.');
      } else {
        await say(
          chatId,
          'اضغط الزر تحت لمشاركة رقم هاتفك. نستخدمه مرة وحدة للتأكد إنه رقمك، وما نحتفظ بالرقم نفسه.',
          { keyboard: [[{ text: '📱 مشاركة رقمي', request_contact: true }]], resize_keyboard: true, one_time_keyboard: true },
        );
      }
    } else if (msg.contact) {
      if (msg.contact.user_id !== fromId) {
        await say(chatId, 'لازم تشارك رقمك أنت بالزر، مو رقم شخص ثاني.', { remove_keyboard: true });
      } else {
        const digits = String(msg.contact.phone_number ?? '').replace(/\D/g, '');
        if (digits.length < 8) {
          await say(chatId, 'الرقم مو واضح، جرّب مرة ثانية.', { remove_keyboard: true });
        } else {
          const { data } = await sb.rpc('phone_verify_finish', { p_tg: fromId, p_hash: await hmacHex(digits, TOKEN) });
          const text = data === 'ok'
            ? 'تم توثيق رقمك ✅ ارجع لتطبيق بيناتنا.'
            : data === 'taken'
            ? 'هذا الرقم مربوط بحساب ثاني بالتطبيق.'
            : 'انتهت المهلة. ارجع للتطبيق واضغط «وثّق رقمي» من جديد.';
          await say(chatId, text, { remove_keyboard: true });
        }
      }
    }
  } catch (_) {
    // نتجاهل: تلغرام ما يحتاج تفاصيل
  }
  return new Response('ok');
});
