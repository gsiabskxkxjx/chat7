part of 'main.dart';

// ---------- الشاشة 0: التشغيل (يقرر وين تروح) ----------

class Boot extends StatefulWidget {
  const Boot({super.key});

  @override
  State<Boot> createState() => _BootState();
}

class _BootState extends State<Boot> {
  String? _err;

  @override
  void initState() {
    super.initState();
    _start();
  }

  void _go(Widget w) => Navigator.of(context)
      .pushReplacement(MaterialPageRoute(builder: (_) => w));

  Future<void> _start() async {
    if (!_configured) return;
    try {
      if (_db.auth.currentSession == null) {
        await _db.auth.signInAnonymously();
      }
      final uid = _db.auth.currentUser!.id;
      final p = await _db
          .from('profiles')
          .select('username')
          .eq('id', uid)
          .maybeSingle();
      if (!mounted) return;
      if (p == null) {
        _go(const UsernameScreen());
        return;
      }
      final me = p['username'] as String;
      final chat = await _loadChat();
      if (!mounted) return;
      _go(chat == null ? PairScreen(me: me) : ChatScreen(chat: chat));
    } catch (e) {
      if (!mounted) return;
      String msg;
      if (e is AuthException) {
        msg = 'فشل تسجيل الدخول المجهول. فعّل Anonymous sign-ins من إعدادات '
            'Supabase (Authentication ثم Sign In / Providers).\n(${e.message})';
      } else if (e is PostgrestException) {
        msg = 'خطأ من السيرفر: ${e.message}\nتأكد إنك شغّلت ملف SQL كامل.';
      } else {
        msg = 'تعذر الاتصال بالسيرفر. تأكد من الإنترنت وحاول مرة ثانية.';
      }
      setState(() => _err = msg);
    }
  }

  @override
  Widget build(BuildContext context) {
    final err = _configured ? _err : 'ضع مفاتيح Supabase في ملف lib/config.dart';
    return Scaffold(
      body: Backdrop(
        child: Center(
          child: err == null
              ? const CircularProgressIndicator()
              : Padding(
                  padding: const EdgeInsets.all(24),
                  child: Glass(
                    radius: 28,
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(err, textAlign: TextAlign.center),
                        if (_configured) ...[
                          const SizedBox(height: 16),
                          _Btn(
                            label: 'إعادة المحاولة',
                            onTap: () {
                              setState(() => _err = null);
                              _start();
                            },
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}

// ---------- الشاشة 1: اسم المستخدم ----------

class UsernameScreen extends StatefulWidget {
  const UsernameScreen({super.key});

  @override
  State<UsernameScreen> createState() => _UsernameState();
}

class _UsernameState extends State<UsernameScreen> {
  final _c = TextEditingController();
  String? _err;
  bool _busy = false;
  // من 1 إلى 20: أحرف إنجليزية صغيرة وأرقام و _ ، وبشرط حرف أو رقم واحد على الأقل
  static final _ok = RegExp(r'^(?=.*[a-z0-9])[a-z0-9_]{1,20}$');

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    if (_busy) return;
    final n = _c.text.trim().toLowerCase();
    if (!_ok.hasMatch(n)) {
      setState(() => _err = 'اكتب من 1 إلى 20 خانة: أحرف إنجليزية وأرقام و _ فقط.');
      return;
    }
    setState(() {
      _err = null;
      _busy = true;
    });
    try {
      await _db
          .from('profiles')
          .insert({'id': _db.auth.currentUser!.id, 'username': n});
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => PairScreen(me: n)));
    } on PostgrestException catch (e) {
      if (!mounted) return;
      final taken = e.code == '23505' && e.message.contains('username');
      setState(() => _err = taken
          ? 'اسم المستخدم محجوز، اختر اسماً ثانياً.'
          : 'تعذر حفظ الاسم، حاول مرة ثانية.');
    } catch (_) {
      if (mounted) setState(() => _err = 'تعذر الاتصال بالسيرفر.');
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
                      const Center(child: _Rings()),
                      const SizedBox(height: 24),
                      const Text('اختر اسم المستخدم',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 26, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      const Text(
                          'هذا اسمك الوحيد في التطبيق، وستتحدث من خلاله مع شخص واحد فقط.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Color(0xCCFFFFFF))),
                      const SizedBox(height: 24),
                      _Field(
                        controller: _c,
                        label: 'اسم المستخدم',
                        icon: Icons.alternate_email,
                        error: _err,
                        onSubmit: _go,
                      ),
                      const SizedBox(height: 16),
                      _Btn(label: 'متابعة', onTap: _go, busy: _busy),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}
