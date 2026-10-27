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
      final user = _db.auth.currentUser;
      if (_db.auth.currentSession == null || user == null) {
        _go(const WelcomeScreen());
        return;
      }
      final uid = user.id;
      final hasEmail = (user.email ?? '').isNotEmpty;
      final p = await _db
          .from('profiles')
          .select('username,gender')
          .eq('id', uid)
          .maybeSingle();
      if (!mounted) return;
      if (p == null) {
        if (!hasEmail) {
          // حساب مجهول قديم بلا بيانات: نبدأ من جديد
          await _db.auth.signOut();
          if (!mounted) return;
          _go(const WelcomeScreen());
          return;
        }
        // حساب بإيميل لكن الملف الشخصي ما انحفظ: نكمله
        final name = user.email!.split('@').first;
        _go(GenderScreen(onPicked: (g) async {
          await _db
              .from('profiles')
              .insert({'id': uid, 'username': name, 'gender': g});
          return const Boot();
        }));
        return;
      }
      final me = p['username'] as String;
      if (!hasEmail) {
        // حساب قديم بدون كلمة سر: نطلب كلمة سر مرة وحدة
        _go(UpgradeScreen(username: me));
        return;
      }
      if (p['gender'] == null) {
        _go(GenderScreen(onPicked: (g) async {
          await _db.from('profiles').update({'gender': g}).eq('id', uid);
          return const Boot();
        }));
        return;
      }
      final chat = await _loadChat();
      if (!mounted) return;
      _go(chat == null ? PairScreen(me: me) : ChatScreen(chat: chat));
    } catch (e) {
      if (!mounted) return;
      String msg;
      final low = (e is AuthException
              ? e.message
              : e is PostgrestException
                  ? e.message
                  : '')
          .toLowerCase();
      if (low.contains('api key') || low.contains('apikey')) {
        msg = 'مفتاح Supabase غير صحيح أو من مشروع ثاني.\n'
            'افتح lib/config.dart وتأكد إن الرابط والمفتاح من نفس المشروع '
            'ومنسوخين كاملين.\n($low)';
      } else if (e is AuthException) {
        msg = 'فشل تسجيل الدخول: ${e.message}';
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
              ? const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(appName,
                        style: TextStyle(
                            fontSize: 38, fontWeight: FontWeight.w800)),
                    SizedBox(height: 24),
                    CircularProgressIndicator(),
                  ],
                )
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
