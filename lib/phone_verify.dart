part of 'main.dart';

// ---------- توثيق الرقم عبر تلغرام ----------
// تلغرام نفسه يتأكد إن الرقم لصاحب الحساب، والسيرفر يحفظ بصمة مشفّرة بس (مو الرقم).

class _PhoneVerifyTile extends StatefulWidget {
  const _PhoneVerifyTile();

  @override
  State<_PhoneVerifyTile> createState() => _PhoneVerifyTileState();
}

class _PhoneVerifyTileState extends State<_PhoneVerifyTile> with WidgetsBindingObserver {
  bool? _ok; // null = السيرفر ما فيه الميزة بعد (نخفي الخيار)
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_load());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // نرجع من تلغرام: نحدّث الحالة
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_load());
  }

  Future<void> _load() async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) return;
    try {
      final r = await _db.from('profiles').select('phone_verified').eq('id', uid).maybeSingle();
      if (mounted) setState(() => _ok = r?['phone_verified'] == true);
    } catch (_) {}
  }

  Future<void> _start() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final r = await _db.rpc('phone_verify_start');
      final bot = r is Map ? r['bot'] as String? : null;
      final code = r is Map ? r['code'] as String? : null;
      if (bot == null || code == null) {
        if (mounted) _toast(context, 'التوثيق غير مفعّل بعد على السيرفر.');
      } else {
        final opened = await launchUrl(Uri.parse('https://t.me/$bot?start=$code'),
            mode: LaunchMode.externalApplication);
        if (!opened && mounted) _toast(context, 'تعذر فتح تلغرام. تأكد إنه منصّب.');
      }
    } catch (_) {
      if (mounted) _toast(context, 'تعذر البدء. تأكد من الإنترنت.');
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _remove() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('إلغاء التوثيق'),
        content: const Text('يختفي علامة التوثيق من حسابك، وتقدر توثّق من جديد بأي وقت.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('رجوع')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('إلغاء التوثيق')),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    try {
      await _db.rpc('phone_unlink');
    } catch (_) {
      if (mounted) _toast(context, 'تعذر الإلغاء.');
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final ok = _ok;
    if (ok == null) return const SizedBox.shrink();
    if (ok) {
      return ListTile(
        leading: const Icon(Icons.verified_rounded, color: Color(0xFF34C759)),
        title: const Text('رقمك موثّق'),
        subtitle: const Text('الطرف الثاني يشوف علامة التوثيق بمعلوماتك'),
        trailing: TextButton(onPressed: _remove, child: const Text('إلغاء')),
      );
    }
    return ListTile(
      leading: const Icon(Icons.verified_user_outlined),
      title: const Text('وثّق رقمك'),
      subtitle: const Text('عبر تلغرام، ما نحتفظ بالرقم نفسه'),
      trailing: _busy
          ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.open_in_new_rounded, size: 20),
      onTap: _start,
    );
  }
}

/// سطر «رقمه موثّق» بمعلومات الطرف الثاني (يختفي لو غير موثّق أو السيرفر ما فيه الميزة)
class _PartnerVerified extends StatelessWidget {
  const _PartnerVerified({required this.chatId});
  final String chatId;

  @override
  Widget build(BuildContext context) => FutureBuilder<dynamic>(
        future: _db.rpc('partner_verified', params: {'p_chat': chatId}),
        builder: (_, s) {
          if (s.data != true) return const SizedBox.shrink();
          return const Padding(
            padding: EdgeInsets.only(bottom: _Sp.sm),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.verified_rounded, size: 16, color: Color(0xFF34C759)),
              SizedBox(width: _Sp.xs),
              Text('رقمه موثّق', style: TextStyle(fontSize: _Fs.small, color: Color(0xFF34C759))),
            ]),
          );
        },
      );
}
