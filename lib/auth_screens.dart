part of 'main.dart';

// ---------- الحسابات: يوزر + كلمة سر (مثل إنستغرام) ----------

/// Supabase يطلب "إيميل" لكل حساب بكلمة سر، فنحوّل اليوزر إلى إيميل داخلي
/// (ما يُرسل له أي شي). لازم دومين حقيقي له MX وإلا Supabase يرفضه.
const authEmailDomain = 'gmail.com';

String _authEmail(String username) =>
    '${username.trim().toLowerCase()}@$authEmailDomain';

final _usernameRe = RegExp(r'^(?=.*[a-z0-9])[a-z0-9_]{1,20}$');

class _Msg implements Exception {
  const _Msg(this.text);
  final String text;
}

String _authError(Object e) {
  if (e is _Msg) return e.text;
  if (e is AuthException) {
    final m = e.message.toLowerCase();
    if (m.contains('invalid login') || m.contains('invalid credentials')) {
      return 'اسم المستخدم أو كلمة السر غلط.';
    }
    if (m.contains('already')) return 'اسم المستخدم مأخوذ، جرّب غيره.';
    if (m.contains('email address') && m.contains('invalid')) {
      return 'Supabase رفض الدومين الداخلي ($authEmailDomain). '
          'غيّر authEmailDomain بملف auth_screens.dart.';
    }
    if (m.contains('rate limit') || m.contains('too many')) {
      return 'محاولات كثيرة، انتظر شوي وجرّب مرة ثانية.';
    }
    if (m.contains('signup') && m.contains('disabled')) {
      return 'التسجيل مقفل بإعدادات Supabase.';
    }
    if (m.contains('password')) {
      return 'كلمة السر ضعيفة أو قصيرة (6 أحرف على الأقل).';
    }
    return 'خطأ: ${e.message}';
  }
  if (e is PostgrestException) {
    if (e.code == '23505') return 'اسم المستخدم مأخوذ، جرّب غيره.';
    return 'خطأ من السيرفر: ${e.message}';
  }
  return 'تعذر الاتصال. تأكد من الإنترنت وجرّب مرة ثانية.';
}

void _toBoot(BuildContext context) => Navigator.of(context).pushAndRemoveUntil(
    MaterialPageRoute(builder: (_) => const Boot()), (_) => false);

// ---------- حقل كلمة السر ----------

class _PassField extends StatefulWidget {
  const _PassField({
    required this.controller,
    required this.label,
    required this.onSubmit,
    this.error,
  });
  final TextEditingController controller;
  final String label;
  final VoidCallback onSubmit;
  final String? error;

  @override
  State<_PassField> createState() => _PassFieldState();
}

class _PassFieldState extends State<_PassField> {
  bool _hide = true;

  @override
  Widget build(BuildContext context) => TextField(
        controller: widget.controller,
        obscureText: _hide,
        textDirection: TextDirection.ltr,
        autocorrect: false,
        enableSuggestions: false,
        onSubmitted: (_) => widget.onSubmit(),
        decoration: InputDecoration(
          labelText: widget.label,
          prefixIcon: const Icon(Icons.lock_outline),
          suffixIcon: IconButton(
            icon: Icon(_hide ? Icons.visibility_off : Icons.visibility),
            onPressed: () => setState(() => _hide = !_hide),
          ),
          errorText: widget.error,
          errorMaxLines: 3,
          filled: true,
          fillColor: const Color(0x1AFFFFFF),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: _edge),
          ),
        ),
      );
}

/// هيكل مشترك لشاشات الحساب.
class _AuthShell extends StatelessWidget {
  const _AuthShell({required this.title, required this.children});
  final String title;
  final List<Widget> children;

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
                      const SizedBox(height: 14),
                      const Text(appName,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 30, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 6),
                      Text(title,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontSize: 17, color: Color(0xCCFFFFFF))),
                      const SizedBox(height: 22),
                      ...children,
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}

// ---------- الشاشة الترحيبية: تسجيل / دخول ----------

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) => _AuthShell(
        title: 'محادثة خاصة بينكم',
        children: [
          _Btn(
            label: 'إنشاء حساب',
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => GenderScreen(
                    onPicked: (g) async => SignUpScreen(gender: g)))),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const LoginScreen())),
            child: const Text('عندي حساب؟ تسجيل الدخول',
                style: TextStyle(fontSize: 16)),
          ),
        ],
      );
}

// ---------- إنشاء حساب ----------

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key, required this.gender});
  final String gender; // male | female

  @override
  State<SignUpScreen> createState() => _SignUpState();
}

class _SignUpState extends State<SignUpScreen> {
  final _u = TextEditingController();
  final _p = TextEditingController();
  final _p2 = TextEditingController();
  String? _err;
  bool _busy = false;

  @override
  void dispose() {
    _u.dispose();
    _p.dispose();
    _p2.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final u = _u.text.trim().toLowerCase();
    final p = _p.text;
    String? bad;
    if (!_usernameRe.hasMatch(u)) {
      bad = 'اليوزر من 1 إلى 20 خانة: أحرف إنجليزية وأرقام و _ فقط.';
    } else if (p.length < 6) {
      bad = 'كلمة السر 6 أحرف على الأقل.';
    } else if (p != _p2.text) {
      bad = 'كلمتا السر غير متطابقتين.';
    }
    if (bad != null) {
      setState(() => _err = bad);
      return;
    }
    setState(() {
      _err = null;
      _busy = true;
    });
    try {
      final free =
          await _db.rpc('username_available', params: {'p_username': u});
      if (free != true) throw const _Msg('اسم المستخدم مأخوذ، جرّب غيره.');

      AuthResponse res;
      try {
        res = await _db.auth.signUp(email: _authEmail(u), password: p);
      } on AuthException catch (e) {
        if (!e.message.toLowerCase().contains('already')) rethrow;
        // حساب انسوّى قبل بنفس البيانات (انقطع الاتصال قبل حفظ الملف مثلاً)
        try {
          res = await _db.auth.signInWithPassword(
              email: _authEmail(u), password: p);
        } on AuthException {
          throw const _Msg('اسم المستخدم مأخوذ، جرّب غيره.');
        }
      }
      final user = res.user;
      if (res.session == null || user == null) {
        throw const _Msg('Supabase يطلب تأكيد الإيميل. أطفئ خيار Confirm email '
            'من Authentication ثم Sign In / Providers ثم Email.');
      }
      final exists = await _db
          .from('profiles')
          .select('id')
          .eq('id', user.id)
          .maybeSingle();
      if (exists == null) {
        await _db.from('profiles').insert(
            {'id': user.id, 'username': u, 'gender': widget.gender});
      }
      if (!mounted) return;
      await _recoveryThenBoot(context);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _err = _authError(e);
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) => _AuthShell(
        title: 'إنشاء حساب جديد',
        children: [
          _Field(
              controller: _u,
              label: 'اسم المستخدم',
              icon: Icons.alternate_email,
              onSubmit: _submit),
          const SizedBox(height: 12),
          _PassField(
              controller: _p, label: 'كلمة السر', onSubmit: _submit),
          const SizedBox(height: 12),
          _PassField(
              controller: _p2,
              label: 'تأكيد كلمة السر',
              onSubmit: _submit,
              error: _err),
          const SizedBox(height: 8),
          const Text(
              'ملاحظة: ما في استرجاع لكلمة السر، فاحفظها.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Color(0x99FFFFFF))),
          const SizedBox(height: 14),
          _Btn(label: 'إنشاء الحساب', onTap: _submit, busy: _busy),
        ],
      );
}

// ---------- تسجيل الدخول ----------

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginState();
}

class _LoginState extends State<LoginScreen> {
  final _u = TextEditingController();
  final _p = TextEditingController();
  String? _err;
  bool _busy = false;

  @override
  void dispose() {
    _u.dispose();
    _p.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final u = _u.text.trim().toLowerCase();
    if (u.isEmpty || _p.text.isEmpty) {
      setState(() => _err = 'اكتب اسم المستخدم وكلمة السر.');
      return;
    }
    setState(() {
      _err = null;
      _busy = true;
    });
    try {
      await _db.auth
          .signInWithPassword(email: _authEmail(u), password: _p.text);
      if (!mounted) return;
      _toBoot(context);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _err = _authError(e);
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) => _AuthShell(
        title: 'تسجيل الدخول',
        children: [
          _Field(
              controller: _u,
              label: 'اسم المستخدم',
              icon: Icons.alternate_email,
              onSubmit: _submit),
          const SizedBox(height: 12),
          _PassField(
              controller: _p,
              label: 'كلمة السر',
              onSubmit: _submit,
              error: _err),
          const SizedBox(height: 18),
          _Btn(label: 'دخول', onTap: _submit, busy: _busy),
          const SizedBox(height: 4),
          TextButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) =>
                    ResetPasswordScreen(username: _u.text.trim()))),
            child: const Text('نسيت كلمة السر؟'),
          ),
        ],
      );
}

// ---------- ترقية حساب قديم (بدون كلمة سر) ----------

class UpgradeScreen extends StatefulWidget {
  const UpgradeScreen({super.key, required this.username});
  final String username;

  @override
  State<UpgradeScreen> createState() => _UpgradeState();
}

class _UpgradeState extends State<UpgradeScreen> {
  final _p = TextEditingController();
  final _p2 = TextEditingController();
  String? _err;
  bool _busy = false;

  @override
  void dispose() {
    _p.dispose();
    _p2.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (_p.text.length < 6) {
      setState(() => _err = 'كلمة السر 6 أحرف على الأقل.');
      return;
    }
    if (_p.text != _p2.text) {
      setState(() => _err = 'كلمتا السر غير متطابقتين.');
      return;
    }
    setState(() {
      _err = null;
      _busy = true;
    });
    try {
      await _db.auth
          .updateUser(UserAttributes(email: _authEmail(widget.username)));
      await _db.auth.updateUser(UserAttributes(password: _p.text));
      final email = _db.auth.currentUser?.email ?? '';
      if (email.isEmpty) {
        throw const _Msg('تعذر تفعيل الحساب. تأكد إن Confirm email مطفأ '
            'بإعدادات Supabase ثم جرّب.');
      }
      if (!mounted) return;
      await _recoveryThenBoot(context);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _err = _authError(e);
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) => _AuthShell(
        title: 'أمّن حسابك @${widget.username}',
        children: [
          const Text(
              'ضع كلمة سر حتى تقدر تدخل حسابك من أي جهاز، ومحادثتك تبقى كما هي.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xCCFFFFFF))),
          const SizedBox(height: 16),
          _PassField(controller: _p, label: 'كلمة السر', onSubmit: _submit),
          const SizedBox(height: 12),
          _PassField(
              controller: _p2,
              label: 'تأكيد كلمة السر',
              onSubmit: _submit,
              error: _err),
          const SizedBox(height: 18),
          _Btn(label: 'حفظ ومتابعة', onTap: _submit, busy: _busy),
        ],
      );
}

// ---------- تغيير كلمة السر (من الملف الشخصي) ----------

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePassState();
}

class _ChangePassState extends State<ChangePasswordScreen> {
  final _p = TextEditingController();
  final _p2 = TextEditingController();
  String? _err;
  bool _busy = false;

  @override
  void dispose() {
    _p.dispose();
    _p2.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (_p.text.length < 6) {
      setState(() => _err = 'كلمة السر 6 أحرف على الأقل.');
      return;
    }
    if (_p.text != _p2.text) {
      setState(() => _err = 'كلمتا السر غير متطابقتين.');
      return;
    }
    setState(() {
      _err = null;
      _busy = true;
    });
    try {
      await _db.auth.updateUser(UserAttributes(password: _p.text));
      if (!mounted) return;
      Navigator.of(context).pop();
      _toast(context, 'تم تغيير كلمة السر');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _err = _authError(e);
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) => _AuthShell(
        title: 'تغيير كلمة السر',
        children: [
          _PassField(
              controller: _p, label: 'كلمة السر الجديدة', onSubmit: _submit),
          const SizedBox(height: 12),
          _PassField(
              controller: _p2,
              label: 'تأكيد كلمة السر',
              onSubmit: _submit,
              error: _err),
          const SizedBox(height: 18),
          _Btn(label: 'حفظ', onTap: _submit, busy: _busy),
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('إلغاء')),
        ],
      );
}
