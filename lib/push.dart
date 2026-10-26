part of 'main.dart';

// ---------- الإشعارات (Firebase Cloud Messaging) ----------

class Push {
  static bool _ready = false;
  static bool _busy = false;

  /// حالة الإشعارات (تظهر بالملف الشخصي عشان نعرف المشكلة لو صارت).
  static String status = 'ما بدأت بعد';

  /// يطلب إذن الإشعارات ويسجّل رمز الجهاز بالسيرفر.
  /// الإشعارات اختيارية: لو فشلت التطبيق يكمل شغله عادي.
  static Future<void> start() async {
    if (_ready || _busy) return;
    _busy = true;
    try {
      await Firebase.initializeApp();
      final fm = FirebaseMessaging.instance;
      final perm = await fm.requestPermission();
      if (perm.authorizationStatus == AuthorizationStatus.denied) {
        status = 'مرفوضة. فعّلها من إعدادات الجوال (التطبيقات ثم الإشعارات).';
        _busy = false;
        return;
      }
      final t = await fm.getToken();
      if (t == null) {
        status = 'ما قدر الجهاز يجيب رمز الإشعارات (تأكد من خدمات Google).';
        _busy = false;
        return;
      }
      await _db.rpc('save_push_token', params: {'p_token': t});
      fm.onTokenRefresh.listen((n) => unawaited(_save(n)));
      _ready = true;
      status = 'مفعّلة';
    } catch (e) {
      final m = e.toString();
      status = 'غير مفعّلة: ${m.length > 140 ? m.substring(0, 140) : m}';
    }
    _busy = false;
  }

  static Future<void> _save(String t) async {
    try {
      await _db.rpc('save_push_token', params: {'p_token': t});
    } catch (_) {}
  }
}
