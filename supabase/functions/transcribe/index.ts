// تحويل رسالة صوتية لنص (Supabase Edge Function).
// الرسائل الصوتية مشفّرة بين الطرفين، فالسيرفر ما يقدر يفتحها بنفسه:
// التطبيق يفك الصوت عند المستخدم ويرسله هنا فقط لما المستخدم يضغط «تحويل لنص».
// يستخدم Groq Whisper. السر: GROQ_API_KEY من Edge Functions > Secrets. لا شي يتخزّن.
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

const mimes: Record<string, string> = {
  m4a: 'audio/mp4', mp4: 'audio/mp4', aac: 'audio/aac', ogg: 'audio/ogg', webm: 'audio/webm',
  wav: 'audio/wav', mp3: 'audio/mpeg', '3gp': 'audio/3gpp', amr: 'audio/amr',
};

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  try {
    const groq = Deno.env.get('GROQ_API_KEY');
    if (!groq) return json({ error: 'not_configured' }, 501);

    const sb = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_ANON_KEY')!, {
      global: { headers: { Authorization: req.headers.get('Authorization') ?? '' } },
    });
    const { data: u } = await sb.auth.getUser();
    if (!u?.user) return json({ error: 'unauthorized' }, 401);

    const body = await req.json();
    const b64 = body?.audio_b64;
    const lang = typeof body?.language === 'string' ? body.language.slice(0, 5) : '';
    const ext = (typeof body?.ext === 'string' ? body.ext : 'm4a')
      .toLowerCase().replace(/[^a-z0-9]/g, '').slice(0, 4) || 'm4a';
    if (typeof b64 !== 'string' || b64.length < 100) return json({ error: 'bad_request' }, 400);
    if (b64.length > 12_000_000) return json({ error: 'too_large' }, 413);

    const bin = Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));
    const form = new FormData();
    form.append('file', new File([bin], 'voice.' + ext, { type: mimes[ext] ?? 'audio/mp4' }));
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
