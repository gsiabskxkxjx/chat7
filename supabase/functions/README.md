# دوال السيرفر (Supabase Edge Functions)

دالتين اختياريتين. التطبيق يشتغل بدونهم، والميزة بس تطلع «غير مفعّلة بعد».

## 1) `transcribe`: تحويل الرسالة الصوتية لنص
1. سوّ حساب مجاني بـ console.groq.com واطلع منه API Key.
2. Supabase ← Edge Functions ← Secrets ← أضف `GROQ_API_KEY` وقيمتها المفتاح.
3. Edge Functions ← Deploy a new function باسم `transcribe`، الصق محتوى `transcribe/index.ts`، وخلّ **Verify JWT شغّال** (الافتراضي).
4. بالتطبيق: اضغط مطولاً على رسالة صوتية ← «حوّلها لنص».

## 2) `telegram-verify`: توثيق الرقم عبر تلغرام (مجاني)
1. بتلغرام افتح @BotFather ← `/newbot` ← اختر اسم واسم مستخدم ينتهي بـ bot. يعطيك **التوكن**.
2. Supabase ← Secrets ← أضف:
   - `TELEGRAM_BOT_TOKEN` = توكن البوت
   - `TG_WEBHOOK_SECRET` = أي نص عشوائي طويل تختاره (حروف وأرقام بس)
3. Deploy باسم `telegram-verify`، الصق `telegram-verify/index.ts`، و**عطّل Verify JWT** لهذي الدالة بس (تلغرام ما يرسل توكن سوبابيس).
4. فعّل الـ webhook بفتح هذا الرابط بالمتصفح (بدّل القيمتين):
   `https://api.telegram.org/bot<التوكن>/setWebhook?url=https://tbmrikxmlnpbcqycjvco.supabase.co/functions/v1/telegram-verify&secret_token=<نفس TG_WEBHOOK_SECRET>`
   لازم يطلع `"ok":true`.
5. شغّل `update_7.sql` بـ SQL Editor، وبدّل `YOUR_BOT_USERNAME` باسم البوت (بدون @) وشيل التعليق عن السطرين اللي فوق الفحص.
6. بالتطبيق: الإعدادات ← الحساب ← «وثّق رقمك».

الرقم ما ينحفظ بأي مكان: تلغرام يتأكد إنه رقمك، والدالة تحفظ بصمة مشفّرة بس حتى ما ينربط رقم بحسابين.
