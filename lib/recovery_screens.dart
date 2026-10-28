part of 'main.dart';

// ---------- استرجاع الحساب برمز (بدون إيميل) ----------

const _recAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

String _newRecoveryCode() {
  final r = Random.secure();
  return List.generate(16, (_) => _recAlphabet[r.nextInt(_recAlphabet.length)])
      .join();
}

String _prettyCode(String c) =>
    '${c.substring(0, 4)}-${c.substring(4, 8)}-${c.substring(8, 12)}-${c.substring(12)}';

String _cleanCode(String s) =>
    s.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

/// يولّد رمز جديد ويحفظ بصمته بالسيرفر، ويرجّع الرمز (يظهر للمستخدم مرة وحدة).
Future<String> _issueRecoveryCode() async {
  final code = _newRecoveryCode();
  await _db.rpc('set_recovery_code', params: {'p_code': code});
  return code;
}

/// بعد التسجيل أو الترقية: نعرض رمز الاسترجاع، وإذا فشل نكمل للتطبيق.
Future<void> _recoveryThenBoot(BuildContext context) async {
  String? code;
  try {
    code = await _issueRecoveryCode();
  } catch (_) {}
  if (!context.mounted) return;
  final c = code;
  if (c == null) {
    _toBoot(context);
    return;
  }
  Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => RecoveryCodeScreen(code: c, onDone: _toBoot)));
}

// ---------- شاشة عرض الرمز ----------

class RecoveryCodeScreen extends StatefulWidget {
  const RecoveryCodeScreen(
      {super.key, required this.code, required this.onDone});
  final String code;
  final void Function(BuildContext) onDone;

  @override
  State<RecoveryCodeScreen> createState() => _RecoveryState();
}

class _RecoveryState extends State<RecoveryCodeScreen> {
  bool _saved = false;

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: false,
        child: _AuthShell(
          title: 'رمز استرجاع حسابك',
          children: [
            const Text(
                'احفظ هذا الرمز بمكان آمن (لقطة شاشة أو ملاحظات). إذا نسيت كلمة السر '
                'ما تقدر ترجع حسابك إلا بهذا الرمز. ما راح يظهر لك مرة ثانية.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xCCFFFFFF))),
            const SizedBox(height: 16),
            Glass(
              radius: 20,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
              child: Row(children: [
                Expanded(
                  child: SelectableText(
                    _prettyCode(widget.code),
                    textAlign: TextAlign.center,
                    textDirection: TextDirection.ltr,
                    style: const TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.5),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.copy_rounded),
                  onPressed: () {
                    Clipboard.setData(
                        ClipboardData(text: _prettyCode(widget.code)));
                    _toast(context, 'تم نسخ الرمز');
                  },
                ),
              ]),
            ),
            const SizedBox(height: 8),
            CheckboxListTile(
              value: _saved,
              onChanged: (v) => setState(() => _saved = v ?? false),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              title: const Text('حفظت الرمز'),
            ),
            const SizedBox(height: 8),
            _Btn(
              label: 'متابعة',
              onTap: () {
                if (!_saved) {
                  _toast(context, 'أكّد إنك حفظت الرمز أول.');
                  return;
                }
                widget.onDone(context);
              },
            ),
          ],
        ),
      );
}

// ---------- نسيت كلمة السر ----------

class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key, this.username = ''});
  final String username;

  @override
  State<ResetPasswordScreen> createState() => _ResetState();
}

class _ResetState extends State<ResetPasswordScreen> {
  late final _u = TextEditingController(text: widget.username);
  final _c = TextEditingController();
  final _p = TextEditingController();
  final _p2 = TextEditingController();
  String? _err;
  bool _busy = false;

  @override
  void dispose() {
    _u.dispose();
    _c.dispose();
    _p.dispose();
    _p2.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final u = _u.text.trim().toLowerCase();
    final code = _cleanCode(_c.text);
    String? bad;
    if (!_usernameRe.hasMatch(u)) {
      bad = 'اكتب اسم المستخدم.';
    } else if (code.length != 16) {
      bad = 'رمز الاسترجاع 16 خانة (حروف وأرقام).';
    } else if (_p.text.length < 6) {
      bad = 'كلمة السر الجديدة 6 أحرف على الأقل.';
    } else if (_p.text != _p2.text) {
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
      final ok = await _db.rpc('reset_password_with_code',
          params: {'p_username': u, 'p_code': code, 'p_new': _p.text});
      if (ok != true) {
        throw const _Msg(
            'اسم المستخدم أو رمز الاسترجاع غير صحيح، أو محاولات كثيرة. جرّب بعد ساعة.');
      }
      await _db.auth
          .signInWithPassword(email: _authEmail(u), password: _p.text);
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
        title: 'استرجاع الحساب',
        children: [
          _Field(
              controller: _u,
              label: 'اسم المستخدم',
              icon: Icons.alternate_email,
              onSubmit: _submit),
          const SizedBox(height: 12),
          _Field(
              controller: _c,
              label: 'رمز الاسترجاع',
              icon: Icons.vpn_key_outlined,
              onSubmit: _submit,
              maxLength: 19,
              pattern: r'[A-Za-z0-9-]',
              upper: true),
          const SizedBox(height: 12),
          _PassField(
              controller: _p,
              label: 'كلمة السر الجديدة',
              onSubmit: _submit),
          const SizedBox(height: 12),
          _PassField(
              controller: _p2,
              label: 'تأكيد كلمة السر',
              onSubmit: _submit,
              error: _err),
          const SizedBox(height: 18),
          _Btn(label: 'تغيير كلمة السر', onTap: _submit, busy: _busy),
        ],
      );
}
