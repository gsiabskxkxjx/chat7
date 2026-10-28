part of 'main.dart';

// ---------- الشاشة 2: ربط الحساب ----------

class PairScreen extends StatefulWidget {
  const PairScreen({super.key, required this.me});
  final String me;

  @override
  State<PairScreen> createState() => _PairState();
}

class _PairState extends State<PairScreen> {
  final _c = TextEditingController();
  Timer? _timer;
  String? _code;
  String? _codeErr;
  DateTime _expires = DateTime.now();
  bool _creating = false;
  bool _busy = false;
  bool _gone = false;

  @override
  void initState() {
    super.initState();
    _newCode();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => _tick());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _c.dispose();
    super.dispose();
  }

  /// يطلب رمز دعوة جديد من السيرفر (صالح 15 دقيقة، لمرة وحدة).
  Future<void> _newCode() async {
    if (_creating || _gone) return;
    _creating = true;
    try {
      final code = (await _db.rpc('create_invite')) as String;
      if (!mounted) return;
      setState(() {
        _code = code;
        _codeErr = null;
        _expires = DateTime.now().add(const Duration(minutes: 14));
      });
    } on PostgrestException catch (e) {
      if (e.message.contains('already_paired')) {
        await _open();
      } else if (mounted) {
        setState(() => _codeErr = 'تعذر إنشاء الرمز.');
      }
    } catch (_) {
      if (mounted) setState(() => _codeErr = 'تعذر الاتصال بالسيرفر.');
    } finally {
      _creating = false;
    }
  }

  /// كل 3 ثواني: إذا الطرف الثاني دخل رمزي، أفتح المحادثة. وأجدد الرمز إذا انتهى.
  Future<void> _tick() async {
    if (await _open()) return;
    if (!mounted) return;
    if (_code == null || DateTime.now().isAfter(_expires)) {
      await _newCode();
    }
  }

  /// يفتح المحادثة إذا موجودة. يرجع true إذا انفتحت.
  Future<bool> _open() async {
    if (_gone) return true;
    try {
      final chat = await _loadChat();
      if (chat == null || !mounted || _gone) return _gone;
      _gone = true;
      _timer?.cancel();
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => ChatScreen(chat: chat)),
        (_) => false,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _link() async {
    if (_busy) return;
    final code = _c.text.trim().toUpperCase();
    if (code.length != 6) {
      _toast(context, 'رمز الدعوة 6 خانات.');
      return;
    }
    setState(() => _busy = true);
    try {
      final r = await _db.rpc('redeem_invite', params: {'p_code': code});
      if (r == null) {
        if (mounted) _toast(context, 'الرمز غير صحيح أو منتهي.');
        return;
      }
      if (!await _open() && mounted) {
        _toast(context, 'تم الربط، افتح التطبيق من جديد إذا ما انفتحت المحادثة.');
      }
    } on PostgrestException catch (e) {
      if (!mounted) return;
      final m = e.message;
      if (m.contains('already_paired')) {
        await _open();
      } else if (m.contains('own_code')) {
        _toast(context, 'هذا رمزك أنت. أعطه للشخص الثاني.');
      } else if (m.contains('too_many_attempts')) {
        _toast(context, 'محاولات كثيرة، انتظر 10 دقايق وجرّب مرة ثانية.');
      } else if (m.contains('invalid_code')) {
        _toast(context, 'الرمز غير صحيح أو منتهي.');
      } else {
        _toast(context, 'تعذر الربط، حاول مرة ثانية.');
      }
    } catch (_) {
      if (mounted) _toast(context, 'تعذر الاتصال بالسيرفر.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Backdrop(
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Glass(
                  radius: 32,
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text('ربط حسابك',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 26, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      Text(
                          'أهلاً @${widget.me}. شارك رمز الدعوة مع الشخص الآخر، أو أدخل رمزه.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Color(0xCCFFFFFF))),
                      const SizedBox(height: 20),
                      Glass(
                        radius: 20,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 6),
                        child: Row(children: [
                          Expanded(
                            child: _code == null
                                ? Center(
                                    child: _codeErr == null
                                        ? const SizedBox(
                                            width: 22,
                                            height: 22,
                                            child: CircularProgressIndicator(
                                                strokeWidth: 2.5),
                                          )
                                        : Text(_codeErr!,
                                            textAlign: TextAlign.center),
                                  )
                                : Text(_code!,
                                    textAlign: TextAlign.center,
                                    textDirection: TextDirection.ltr,
                                    style: const TextStyle(
                                        fontSize: 30,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 6)),
                          ),
                          IconButton(
                            icon: const Icon(Icons.copy_rounded),
                            onPressed: _code == null
                                ? null
                                : () {
                                    Clipboard.setData(
                                        ClipboardData(text: _code!));
                                    _toast(context, 'تم نسخ الرمز');
                                  },
                          ),
                        ]),
                      ),
                      const SizedBox(height: 16),
                      _Field(
                        controller: _c,
                        label: 'رمز الشخص الآخر',
                        icon: Icons.link,
                        maxLength: 6,
                        pattern: r'[A-Za-z0-9]',
                        upper: true,
                        onSubmit: _link,
                      ),
                      const SizedBox(height: 16),
                      _Btn(label: 'ربط', onTap: _link, busy: _busy),
                      const SizedBox(height: 12),
                      const Text('الرمز يصلح لمرة وحدة ولمدة 15 دقيقة.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 12, color: Color(0x99FFFFFF))),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}
