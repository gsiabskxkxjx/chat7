part of 'main.dart';

// ---------- الدخول وربط حساب الأدمن ----------

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: _sb.auth.onAuthStateChange,
      builder: (context, snap) {
        final session = _sb.auth.currentSession;
        if (session == null) return const LoginScreen();
        return AdminCheck(key: ValueKey(session.user.id));
      },
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _pass = TextEditingController();
  final _pass2 = TextEditingController();
  bool _signup = false;
  bool _busy = false;
  bool _hide = true;
  String? _error;
  String? _info;

  @override
  void dispose() {
    _email.dispose();
    _pass.dispose();
    _pass2.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _email.text.trim().toLowerCase();
    final pass = _pass.text;
    if (!email.contains('@') || !email.contains('.')) {
      setState(() => _error = 'اكتب إيميل صحيح');
      return;
    }
    if (pass.length < 8) {
      setState(() => _error = 'كلمة السر لازم 8 خانات على الأقل');
      return;
    }
    if (_signup && pass != _pass2.text) {
      setState(() => _error = 'كلمتا السر مو متطابقتين');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    try {
      if (_signup) {
        final r = await _sb.auth.signUp(email: email, password: pass);
        if (r.session == null && mounted) {
          setState(() => _info = 'تم إنشاء الحساب. إذا طلب تأكيد، افتح رسالة التأكيد بإيميلك ثم سجّل دخول.');
        }
      } else {
        await _sb.auth.signInWithPassword(email: email, password: pass);
      }
    } catch (e) {
      if (mounted) setState(() => _error = _err(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.admin_panel_settings_rounded, size: 64),
                  const SizedBox(height: 12),
                  const Text('أدمن بيناتنا',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(_signup ? 'إنشاء حساب الإدارة' : 'تسجيل الدخول',
                      textAlign: TextAlign.center, style: const TextStyle(color: Color(0x99FFFFFF))),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    textDirection: TextDirection.ltr,
                    decoration: const InputDecoration(labelText: 'الإيميل', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _pass,
                    obscureText: _hide,
                    textDirection: TextDirection.ltr,
                    decoration: InputDecoration(
                      labelText: 'كلمة السر',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(_hide ? Icons.visibility_rounded : Icons.visibility_off_rounded),
                        onPressed: () => setState(() => _hide = !_hide),
                      ),
                    ),
                    onSubmitted: (_) => _signup ? null : _submit(),
                  ),
                  if (_signup) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: _pass2,
                      obscureText: _hide,
                      textDirection: TextDirection.ltr,
                      decoration: const InputDecoration(
                          labelText: 'أعد كتابة كلمة السر', border: OutlineInputBorder()),
                      onSubmitted: (_) => _submit(),
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: const TextStyle(color: Color(0xFFFF8A80))),
                  ],
                  if (_info != null) ...[
                    const SizedBox(height: 12),
                    Text(_info!, style: const TextStyle(color: Color(0xFF80CBC4))),
                  ],
                  const SizedBox(height: 18),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: _busy
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : Text(_signup ? 'إنشاء الحساب' : 'دخول'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => setState(() {
                              _signup = !_signup;
                              _error = null;
                              _info = null;
                            }),
                    child: Text(_signup ? 'عندي حساب. تسجيل دخول' : 'أول مرة؟ إنشاء حساب'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// يتأكد إن الحساب الحالي أدمن، وإلا يطلب كود الربط
class AdminCheck extends StatefulWidget {
  const AdminCheck({super.key});

  @override
  State<AdminCheck> createState() => _AdminCheckState();
}

class _AdminCheckState extends State<AdminCheck> {
  int _state = 0; // 0 تحميل، 1 أدمن، 2 مو أدمن، 3 خطأ
  String _msg = '';

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    setState(() => _state = 0);
    try {
      final r = await _rpc('is_admin');
      if (!mounted) return;
      setState(() => _state = r == true ? 1 : 2);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _state = 3;
        _msg = _err(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    switch (_state) {
      case 1:
        return const AdminHome();
      case 2:
        return ClaimScreen(onDone: _check);
      case 3:
        return Scaffold(
          body: Column(
            children: [
              Expanded(child: _ErrorBox(message: _msg, onRetry: _check)),
              TextButton(onPressed: () => _sb.auth.signOut(), child: const Text('تسجيل خروج')),
              const SizedBox(height: 24),
            ],
          ),
        );
      default:
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
  }
}

class ClaimScreen extends StatefulWidget {
  const ClaimScreen({super.key, required this.onDone});
  final Future<void> Function() onDone;

  @override
  State<ClaimScreen> createState() => _ClaimScreenState();
}

class _ClaimScreenState extends State<ClaimScreen> {
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _claim() async {
    final code = _code.text.trim();
    if (code.length < 8) {
      setState(() => _error = 'اكتب الكود كامل');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final ok = await _rpc('admin_claim', {'p_code': code});
      if (ok == true) {
        await widget.onDone();
        return;
      }
      if (mounted) setState(() => _error = 'الكود غلط أو منتهي أو مستخدم من قبل');
    } catch (e) {
      if (mounted) setState(() => _error = _err(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final email = _sb.auth.currentUser?.email ?? '';
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.vpn_key_rounded, size: 56),
                  const SizedBox(height: 12),
                  const Text('ربط الحساب بصلاحية الأدمن',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  Text('مسجّل دخول بـ $email\nأدخل كود الربط (يشتغل مرة وحدة).',
                      textAlign: TextAlign.center, style: const TextStyle(color: Color(0x99FFFFFF))),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _code,
                    textCapitalization: TextCapitalization.characters,
                    textDirection: TextDirection.ltr,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 18, letterSpacing: 2),
                    decoration: const InputDecoration(hintText: 'XXXX-XXXX-XXXX-XXXX-XXXX', border: OutlineInputBorder()),
                    onSubmitted: (_) => _claim(),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFFFF8A80))),
                  ],
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _busy ? null : _claim,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: _busy
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('ربط'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _busy ? null : () => _sb.auth.signOut(),
                    child: const Text('استخدم حساب ثاني'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
