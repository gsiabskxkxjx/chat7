# بيناتنا (chat7)

تطبيق دردشة خاص بين شخصين، مبني بـ Flutter وSupabase وFirebase (الإشعارات فقط).

## خريطة المشروع

| المسار | المحتوى |
| --- | --- |
| `lib/main.dart` | نقطة الدخول، الاستيرادات، وقائمة الـ `part` (المشروع مكتبة واحدة مقسّمة لملفات) |
| `lib/chat_*.dart` | شاشة المحادثة، الإرسال، الفقاعات، الخيارات |
| `lib/call_*.dart` | المكالمات (WebRTC): الجلسة، الشاشات، الإشعارات |
| `lib/games*.dart` | الألعاب (`chat_games` بسوبابيس، حالة اللعبة JSON) |
| `lib/r2_*.dart` | الجولة الثانية: الإعدادات، الخطط، الثنائي، الذكاء الاصطناعي، الألبومات، الموقع |
| `lib/pure.dart` | دوال نقية قابلة للاختبار (`test/pure_test.dart`) |
| `lib/config.dart`, `lib/turn_config.dart` | مفاتيح المشروع (لا تُنشر قيمها) |
| `.github/workflows/build.yml` | البناء: يولّد مشروع أندرويد، يضيف الكود الأصلي من `.github/android/*.kt`، ويوقّع وينشر Release |
| `supabase/migrations/` | ترحيلات SQL مرقّمة بالترتيب |
| `supabase/functions/` | دوال الحافة: `push` · `ai-assist` · `smart-transcribe` · `telegram-verify` |

## قنوات أندرويد (MethodChannel)

`bainatna/widgets` · `bainatna/pip` · `bainatna/media` · `bainatna/icon` · `bainatna/r2` (منع لقطات الشاشة، حساس القرب، إبقاء الشاشة مضيئة، استقبال المشاركة).

## قاعدة البيانات

- كل الجداول عليها RLS، والعضوية عبر `public.is_member(chat uuid)`.
- الإشعارات: `push_user(...)` و`notify_push()` تستدعي دالة الحافة `push` عبر `pg_net`.
- الرسائل: `messages.kind` ∈ text, image, video, audio, call, think, card, vnote, file, location, ref, alert.

## التطوير

لا يوجد SDK محلي بالبيئة؛ التحقق يتم عبر GitHub Actions (يبني ويشغّل الاختبارات والتحليل). الأخطاء الحقيقية تظهر في سجل الـ workflow.
