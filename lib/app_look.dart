part of 'main.dart';

// ---------- المظهر الشامل: ثيم الزوج وخلفيته تنطبق على كل التطبيق ----------
// الزوج له محادثة وحدة، وإعدادات المحادثة (chats) تكون مشتركة بين الطرفين،
// فنستخدمها لكل الشاشات. أي تغيير من أي طرف يوصل للثاني تلقائياً.

class AppLook {
  const AppLook({
    required this.theme,
    required this.kind,
    required this.strength,
    this.url,
  });
  final ChatTheme theme;
  final String kind; // gradient | plain | blur | glass
  final int strength;
  final String? url; // رابط الصورة الموقّع (إذا فيه صورة)
}

final ValueNotifier<AppLook?> _appLook = ValueNotifier<AppLook?>(null);

StreamSubscription<List<Map<String, dynamic>>>? _lookAllSub;
String? _lookPath;

/// يبدأ متابعة مظهر الزوج (يعاد استدعاؤها عند تغيير تسجيل الدخول)
void _startAppLook() {
  _lookAllSub?.cancel();
  if (_db.auth.currentUser == null) {
    _appLook.value = null;
    _lookPath = null;
    return;
  }
  _lookAllSub = _db
      .from('chats')
      .stream(primaryKey: ['id'])
      .listen((rows) async {
    if (rows.isEmpty) {
      _appLook.value = null;
      _lookPath = null;
      return;
    }
    final r = rows.first;
    final id = (r['theme_id'] as num?)?.toInt() ?? 1;
    final kind = (r['bg_kind'] as String?) ?? 'gradient';
    final strength = (r['bg_strength'] as num?)?.toInt() ?? 10;
    final path = r['bg_path'] as String?;
    String? url = _appLook.value?.url;
    if (path != _lookPath) {
      _lookPath = path;
      url = path == null ? null : await MediaUrls.get('chat-bg', path);
    }
    _appLook.value = AppLook(
      theme: chatThemeById(id),
      kind: kind,
      strength: strength,
      url: url,
    );
  }, onError: (_) {});
}
