// تحويل رسالة صوتية لنص (Supabase Edge Function).
// يستخدم Groq Whisper (مجاني بحدود معقولة). السر: GROQ_API_KEY من Edge Functions > Secrets.
// فعّل خيار Verify JWT (هو الافتراضي): لازم المستخدم يكون مسجّل دخول.
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, 'Content-Type': 'application/json' },
  });

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  try {
    const groq = Deno.env.get('GROQ_API_KEY');
    if (!groq) return json({ error: 'not_configured' }, 501);

    // المستخدم بصلاحياته هو (RLS تنطبق)
    const sb = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_ANON_KEY')!, {
      global: { headers: { Authorization: req.headers.get('Authorization') ?? '' } },
    });
    const { data: u } = await sb.auth.getUser();
    if (!u?.user) return json({ error: 'unauthorized' }, 401);

    const body = await req.json();
    const chatId = body?.chat_id;
    const path = body?.path;
    const lang = typeof body?.language === 'string' ? body.language : '';
    if (typeof chatId !== 'string' || typeof path !== 'string' ||
        !path.startsWith(chatId + '/') || path.includes('..')) {
      return json({ error: 'bad_request' }, 400);
    }

    const { data: member } = await sb.rpc('is_member', { p_chat: chatId });
    if (member !== true) return json({ error: 'forbidden' }, 403);

    // لازم تكون رسالة صوتية فعلاً بهذي المحادثة
    const { data: row } = await sb.from('messages').select('kind')
      .eq('chat_id', chatId).eq('media_path', path).maybeSingle();
    if (!row || row.kind !== 'audio') return json({ error: 'not_audio' }, 400);

    const dl = await sb.storage.from('chat-media').download(path);
    if (dl.error || !dl.data) return json({ error: 'download_failed' }, 404);
    const blob = dl.data;
    if (blob.size > 24 * 1024 * 1024) return json({ error: 'too_large' }, 413);

    const ext = (path.split('.').pop() ?? 'm4a').toLowerCase();
    const form = new FormData();
    form.append('file', new File([blob], 'voice.' + ext, { type: blob.type || 'audio/mp4' }));
    form.append('model', 'whisper-large-v3-turbo');
    form.append('response_format', 'json');
    form.append('temperature', '0');
    if (lang) form.append('language', lang);

    const r = await fetch('https://api.groq.com/openai/v1/audio/transcriptions', {
      method: 'POST',
      headers: { Authorization: 'Bearer ' + groq },
      body: form,
    });
    if (!r.ok) return json({ error: 'upstream_' + r.status }, r.status === 429 ? 429 : 502);
    const out = await r.json();
    return json({ text: String(out?.text ?? '').trim() });
  } catch (_) {
    return json({ error: 'failed' }, 500);
  }
});
