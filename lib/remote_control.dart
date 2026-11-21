part of 'main.dart';

// ---------- التحكم عن بعد (من تطبيق الأدمن): صيانة، إجبار على التحديث، إعلان ----------
// السيرفر يرجّع حالة التطبيق بدالة app_status (متاحة قبل تسجيل الدخول أيضاً).
// لو تعذر الاتصال نكمل عادي: ما نمنع أحد بسبب خلل بالشبكة.

class _AppStatus {
  const _AppStatus({
    this.maintenance = false,
    this.maintenanceMsg = '',
    this.minBuild = 0,
    this.announce = '',
    this.announceId = 0,
  });

  final bool maintenance;
  final String maintenanceMsg;
  final int minBuild;
  final String announce;
  final int announceId;

  /// الإجبار يشتغل فقط للنسخ اللي فيها رقم بناء (نسخ GitHub والمتجر)
  bool get forceUpdate => minBuild > 0 && _buildNo > 0 && _buildNo < minBuild;

  static int _toInt(Object? v) => v is num ? v.toInt() : (int.tryParse('${v ?? ''}') ?? 0);

  factory _AppStatus.fromJson(Map<String, dynamic> j) => _AppStatus(
        maintenance: j['maintenance'] == true,
        maintenanceMsg: '${j['maintenance_msg'] ?? ''}',
        minBuild: _toInt(j['min_build']),
        announce: '${j['announce'] ?? ''}',
        announceId: _toInt(j['announce_id']),
      );
}

final _appStatus = ValueNotifier<_AppStatus>(const _AppStatus());
DateTime? _lastStatusCheck;
bool _statusChecking = false;
bool _announceShownThisRun = false;

/// يجلب حالة التطبيق. [force] يتجاهل فترة الانتظار (دقيقة) بين الفحوصات
Future<void> _refreshAppStatus({bool force = false}) async {
  if (!_configured || _statusChecking) return;
  final last = _lastStatusCheck;
  if (!force && last != null && DateTime.now().difference(last) < const Duration(seconds: 60)) return;
  _statusChecking = true;
  try {
    final r = await Future<dynamic>.value(_db.rpc('app_status')).timeout(const Duration(seconds: 8));
    if (r is Map) {
      _lastStatusCheck = DateTime.now();
      _appStatus.value = _AppStatus.fromJson(Map<String, dynamic>.from(r));
      unawaited(_maybeShowAnnouncement(_appStatus.value));
    }
  } catch (_) {
    // فشل الجلب: نبقي آخر حالة معروفة ونعيد المحاولة لاحقاً
  } finally {
    _statusChecking = false;
  }
}

/// الإعلان يطلع مرة وحدة لكل رقم إعلان، وما يتعارض مع شاشة صيانة أو إجبار
Future<void> _maybeShowAnnouncement(_AppStatus s) async {
  if (s.announce.trim().isEmpty || s.announceId <= 0) return;
  if (s.maintenance || s.forceUpdate || _announceShownThisRun) return;
  final seen = _R2Store.get<int>('rc_seen_announce') ?? 0;
  if (s.announceId <= seen) return;
  final ctx = _navKey.currentContext;
  if (ctx == null || !ctx.mounted) return; // الواجهة ما جهزت بعد: نعرضه بالفحص القادم
  _announceShownThisRun = true;
  await _R2Store.set('rc_seen_announce', s.announceId);
  if (!ctx.mounted) return;
  await showDialog<void>(
    context: ctx,
    builder: (d) => AlertDialog(
      icon: const Icon(Icons.campaign_rounded, size: 34),
      title: const Text('إعلان من بيناتنا'),
      content: SingleChildScrollView(child: Text(s.announce, style: const TextStyle(height: 1.6))),
      actions: [FilledButton(onPressed: () => Navigator.pop(d), child: const Text('تمام'))],
    ),
  );
}

/// يظهر فوق كل شي لما تكون الصيانة شغّالة أو النسخة أقدم من المسموح
class _StatusGate extends StatelessWidget {
  const _StatusGate({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<_AppStatus>(
        valueListenable: _appStatus,
        child: child,
        builder: (context, s, ch) {
          final block = s.maintenance || s.forceUpdate;
          return Stack(
            fit: StackFit.expand,
            children: [
              ch!,
              if (block) const ModalBarrier(dismissible: false, color: Color(0xFF0B1020)),
              if (block) Positioned.fill(child: _BlockPage(status: s)),
            ],
          );
        },
      );
}

class _BlockPage extends StatefulWidget {
  const _BlockPage({required this.status});
  final _AppStatus status;

  @override
  State<_BlockPage> createState() => _BlockPageState();
}

class _BlockPageState extends State<_BlockPage> {
  bool _busy = false;

  Future<void> _retry() async {
    setState(() => _busy = true);
    await _refreshAppStatus(force: true);
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _update() async {
    setState(() => _busy = true);
    try {
      String link = 'https://play.google.com/store/apps/details?id=com.bainatna.chat';
      if (_sideload) {
        final r = await _latestRelease();
        link = r?.$2 ?? _releaseUrl;
      }
      await _openUrl(null, link);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.status;
    final maint = s.maintenance;
    final msg = maint
        ? (s.maintenanceMsg.trim().isEmpty ? 'نسوي تحسينات بسيطة، ونرجع لكم بأقرب وقت.' : s.maintenanceMsg.trim())
        : 'صدرت نسخة جديدة ولازم تحدّث التطبيق قبل ما تكمل.';
    return Material(
      color: const Color(0xFF0B1020),
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(maint ? Icons.construction_rounded : Icons.system_update_rounded, size: 64, color: Colors.white),
                const SizedBox(height: 18),
                Text(maint ? 'التطبيق تحت الصيانة' : 'تحديث مطلوب',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Colors.white)),
                const SizedBox(height: 12),
                Text(msg,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 15, height: 1.7, color: Color(0xCCFFFFFF))),
                if (!maint) ...[
                  const SizedBox(height: 14),
                  const Text(
                    'ثبّت التحديث فوق النسخة القديمة ولا تحذف التطبيق، لأن الحذف يمسح مفتاح التشفير من جهازك.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, height: 1.6, color: Color(0xFFFFCC80)),
                  ),
                ],
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _busy ? null : (maint ? _retry : _update),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                    child: _busy
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : Text(maint ? 'إعادة المحاولة' : 'تحديث الآن'),
                  ),
                ),
                if (!maint)
                  TextButton(
                    onPressed: _busy ? null : _retry,
                    child: const Text('حدّثت؟ تحقق من جديد'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
