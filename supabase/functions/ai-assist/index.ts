// مساعد الذكاء الاصطناعي (ترجمة، تلخيص، اقتراح ردود...) عبر Groq المجاني.
// السر: GROQ_API_KEY (نفس سر تحويل الصوت). لازم المستخدم مسجّل دخول (Verify JWT).
// ما نحفظ النصوص بالسيرفر، وفيه حصة يومية لكل مستخدم (ai_quota_take).
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, 'Content-Type': 'application/json' } });

type Task = { sys: (b: Record<string, unknown>) => string; json?: boolean; tokens: number };

const LANGS: Record<string, string> = {
  ar: 'Arabic', en: 'English', tr: 'Turkish', fa: 'Persian', ku: 'Kurdish (Sorani)',
  fr: 'French', de: 'German', es: 'Spanish', ru: 'Russian', ur: 'Urdu',
};
const STYLES: Record<string, string> = {
  romantic: 'رومانسي ودافئ', funny: 'مرح وخفيف', short: 'مختصر ومباشر',
  formal: 'مهذّب ورسمي', poetic: 'شاعري',
};

const TASKS: Record<string, Task> = {
  translate: {
    tokens: 700,
    sys: (b) => `You are a precise translator. Translate the user's message into ${LANGS[String(b.lang)] ?? 'Arabic'}. Keep the tone, emojis and names. Output ONLY the translation, with no quotes and no notes.`,
  },
  summarize: {
    tokens: 300,
    sys: () => 'لخّص النص التالي (تفريغ رسالة صوتية) بجملتين قصيرتين بنفس لغة النص وبلهجته. لا تضف معلومات جديدة. اكتب الملخص فقط.',
  },
  reply: {
    tokens: 500, json: true,
    sys: () => 'أنت تساعد شخصاً يرد على رسالة من شريكه بتطبيق دردشة خاص. اقترح ثلاثة ردود قصيرة (أقل من 200 حرف) بالعربية العراقية الودّية: واحد رومانسي، واحد مرح، واحد مختصر. أعد JSON فقط بالشكل {"options":[{"style":"romantic","text":"..."},{"style":"funny","text":"..."},{"style":"short","text":"..."}]}',
  },
  fix: {
    tokens: 700,
    sys: () => 'صحّح الأخطاء الإملائية والنحوية بالنص التالي بدون تغيير المعنى أو اللهجة أو الإيموجي. أعد النص المصحّح فقط بدون أي شرح.',
  },
  catchup: {
    tokens: 450,
    sys: () => 'هذي رسائل محادثة بين شخصين بالترتيب الزمني. اكتب ملخصاً بنقاط قصيرة (3 إلى 6 نقاط) لأهم ما قيل، بالعربية، مع ذكر أي موعد أو طلب. لا تخترع شيئاً غير موجود.',
  },
  gift: {
    tokens: 600, json: true,
    sys: () => 'اقترح 4 أفكار هدايا مناسبة اعتماداً على المعلومات المعطاة (قائمة أمنيات وميزانية). أعد JSON فقط بالشكل {"ideas":[{"title":"...","why":"..."}]} بالعربية، وكل "why" جملة وحدة.',
  },
  outing: {
    tokens: 600, json: true,
    sys: () => 'اقترح 4 أفكار طلعات لشخصين حسب الوقت والميزانية والطقس المعطاة. أعد JSON فقط بالشكل {"ideas":[{"title":"...","why":"..."}]} بالعربية، وكل "why" جملة وحدة.',
  },
  occasion: {
    tokens: 500,
    sys: (b) => `اكتب رسالة قصيرة (3 إلى 5 أسطر) لمناسبة بين شريكين بأسلوب ${STYLES[String(b.style)] ?? 'رومانسي ودافئ'} وبالعربية العراقية. استخدم المعلومات المعطاة فقط. اكتب الرسالة فقط.`,
  },
};

async function groq(key: string, model: string, system: string, user: string, jsonMode: boolean, tokens: number) {
  return await fetch('https://api.groq.com/openai/v1/chat/completions', {
    method: 'POST',
    headers: { Authorization: 'Bearer ' + key, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      model,
      temperature: jsonMode ? 0.8 : 0.5,
      max_tokens: tokens,
      messages: [{ role: 'system', content: system }, { role: 'user', content: user }],
      ...(jsonMode ? { response_format: { type: 'json_object' } } : {}),
    }),
  });
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  try {
    const key = Deno.env.get('GROQ_API_KEY');
    if (!key) return json({ error: 'not_configured' }, 501);

    const sb = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_ANON_KEY')!, {
      global: { headers: { Authorization: req.headers.get('Authorization') ?? '' } },
    });
    const { data: u } = await sb.auth.getUser();
    if (!u?.user) return json({ error: 'unauthorized' }, 401);

    const body = await req.json();
    const task = TASKS[String(body?.task ?? '')];
    if (!task) return json({ error: 'bad_task' }, 400);
    const text = String(body?.text ?? '').trim().slice(0, 4000);
    if (!text) return json({ error: 'empty' }, 400);

    const { data: ok } = await sb.rpc('ai_quota_take', { p_limit: 40 });
    if (ok !== true) return json({ error: 'quota' }, 429);

    const system = task.sys(body ?? {});
    let r = await groq(key, 'llama-3.3-70b-versatile', system, text, !!task.json, task.tokens);
    if (r.status === 429 || r.status >= 500) {
      r = await groq(key, 'llama-3.1-8b-instant', system, text, !!task.json, task.tokens);
    }
    if (!r.ok) return json({ error: 'upstream_' + r.status }, r.status === 429 ? 429 : 502);
    const out = await r.json();
    const content = String(out?.choices?.[0]?.message?.content ?? '').trim();
    if (!content) return json({ error: 'empty_result' }, 502);

    if (task.json) {
      try {
        return json(JSON.parse(content));
      } catch (_) {
        return json({ error: 'bad_format' }, 502);
      }
    }
    return json({ text: content });
  } catch (_) {
    return json({ error: 'failed' }, 500);
  }
});
