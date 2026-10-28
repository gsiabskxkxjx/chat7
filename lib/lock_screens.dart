part of 'main.dart';

// ---------- قفل التطبيق بالبصمة أو الوجه ----------

/// حالة القفل (لكل جهاز، تنحفظ بملف على الجوال)
final ValueNotifier<bool> _lockNotifier = ValueNotifier<bool>(false);

final LocalAuthentication _bioAuth = LocalAuthentication();

Future<File> _lockFile() async {
  final dir = await getApplicationSupportDirectory();
  return File('${dir.path}/app_lock.txt');
}

Future<void> _loadLock() async {
  try {
    final f = await _lockFile();
    final on = await f.exists() && (await f.readAsString()).trim() == 'on';
    _lockNotifier.value = on;
  } catch (_) {}
}

Future<void> _saveLock(bool on) async {
  try {
    final f = await _lockFile();
    await f.writeAsString(on ? 'on' : 'off');
  } catch (_) {}
  _lockNotifier.value = on;
}

/// يفتح نافذة البصمة أو الوجه (أو رمز الجوال إذا ما فيه بصمة). يرجع true إذا نجح.
Future<bool> _authenticate(String reason) async {
  try {
    final can =
        await _bioAuth.canCheckBiometrics || await _bioAuth.isDeviceSupported();
    if (!can) return false;
    return await _bioAuth.authenticate(
      localizedReason: reason,
      options: const AuthenticationOptions(
        stickyAuth: true,
        biometricOnly: false,
      ),
    );
  } catch (_) {
    return false;
  }
}

/// تفعيل أو إطفاء القفل. لازم تأكيد الهوية في الحالتين.
Future<void> _toggleLockAuth(BuildContext context) async {
  final turnOn = !_lockNotifier.value;
  final ok = await _authenticate(
      turnOn ? 'أكّد هويتك لتفعيل القفل' : 'أكّد هويتك لإطفاء القفل');
  if (!ok) {
    if (context.mounted) {
      _toast(context,
          'ما قدرنا نتأكد من هويتك. تأكد إن جوالك فيه بصمة أو قفل شاشة.');
    }
    return;
  }
  await _saveLock(turnOn);
}

/// يغطي التطبيق بشاشة قفل إذا القفل مفعّل: عند الفتح، وإذا طلعت أكثر من 30 ثانية.
class _LockGate extends StatefulWidget {
  const _LockGate({required this.child});
  final Widget child;

  @override
  State<_LockGate> createState() => _LockGateState();
}

class _LockGateState extends State<_LockGate> with WidgetsBindingObserver {
  bool _locked = false;
  bool _busy = false; // نافذة البصمة مفتوحة، ما نقفل ونحن فيها
  DateTime? _leftAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _lockNotifier.addListener(_onLockChanged);
    _loadLock().then((_) {
      if (mounted && _lockNotifier.value) _lockNow();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _lockNotifier.removeListener(_onLockChanged);
    super.dispose();
  }

  void _onLockChanged() {
    if (mounted && !_lockNotifier.value && _locked) {
      setState(() => _locked = false);
    }
  }

  void _lockNow() {
    if (!mounted) return;
    setState(() => _locked = true);
    WidgetsBinding.instance.addPostFrameCallback((_) => _unlock());
  }

  Future<void> _unlock() async {
    if (_busy || !_locked) return;
    _busy = true;
    final ok = await _authenticate('افتح بيناتنا');
    _busy = false;
    if (ok && mounted) setState(() => _locked = false);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_lockNotifier.value || _busy) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _leftAt ??= DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      final left = _leftAt;
      _leftAt = null;
      if (left != null &&
          DateTime.now().difference(left) > const Duration(seconds: 30)) {
        _lockNow();
      }
    }
  }

  @override
  Widget build(BuildContext context) => Stack(
        fit: StackFit.expand,
        children: [
          widget.child,
          if (_locked)
            Material(
              color: const Color(0xF2050A18),
              child: SafeArea(
                child: Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.lock_outline,
                        size: 64, color: Colors.white),
                    const SizedBox(height: 16),
                    const Text('بيناتنا مقفول',
                        style: TextStyle(
                            fontSize: 22, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 24),
                    _Btn(
                        label: 'افتح بالبصمة أو الوجه',
                        onTap: _unlock,
                        busy: false),
                  ]),
                ),
              ),
            ),
        ],
      );
}
