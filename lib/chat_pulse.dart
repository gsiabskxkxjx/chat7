part of 'main.dart';

// ---------- نبض المحادثة: حالة الاتصال + اكتشاف إلغاء الارتباط ----------

class ChatPulse with WidgetsBindingObserver {
  ChatPulse(
    this.chatId, {
    required this.onPartner,
    required this.onGone,
    required this.onResume,
    required this.onNet,
  });

  final String chatId;

  /// يُستدعى كل 10 ثواني بحالة الطرف الثاني.
  final void Function(
      bool online, double? age, String? name, String? avatar, String? gender)
      onPartner;

  /// الارتباط انلغى من الطرف الثاني.
  final VoidCallback onGone;

  /// التطبيق رجع للواجهة.
  final VoidCallback onResume;

  /// true = الاتصال شغال، false = ما قدر يوصل للسيرفر
  final void Function(bool ok) onNet;

  Timer? _timer;
  bool foreground = true;
  bool _stopped = false;
  int _n = 0;

  void start() {
    WidgetsBinding.instance.addObserver(this);
    unawaited(_tick());
    _timer = Timer.periodic(const Duration(seconds: 10), (_) => _tick());
  }

  void stop() {
    if (_stopped) return;
    _stopped = true;
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_online(false));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_stopped) return;
    foreground = state == AppLifecycleState.resumed;
    unawaited(_online(foreground));
    if (foreground) {
      unawaited(_tick());
      onResume();
    }
  }

  Future<void> _online(bool v) async {
    try {
      await _db.rpc('touch_presence', params: {'p_online': v});
    } catch (_) {}
  }

  Future<void> _tick() async {
    if (_stopped) return;
    _n++;
    // نبضة حضور كل 20 ثانية وأنا بالواجهة
    if (foreground && _n % 2 == 1) unawaited(_online(true));
    try {
      final r = await _db.rpc('partner_status', params: {'p_chat': chatId});
      if (_stopped) return;
      onNet(true);
      final rows = r as List;
      if (rows.isEmpty) {
        stop();
        onGone();
        return;
      }
      final m = Map<String, dynamic>.from(rows.first as Map);
      onPartner(
        m['is_online'] == true,
        (m['age_seconds'] as num?)?.toDouble(),
        m['pname'] as String?,
        m['pavatar'] as String?,
        m['pgender'] as String?,
      );
    } catch (_) {
      if (!_stopped) onNet(false);
    }
  }
}
