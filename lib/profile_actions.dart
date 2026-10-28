part of 'main.dart';

// عمليات الملف الشخصي: صورة، اسم، خروج، حذف الحساب، إلغاء الارتباط
extension _ProfileActions on _ProfileState {
  Future<void> _changePhoto() async {
    final p = _p;
    if (p == null || _busy) return;
    final act = await _photoSheet(context, canRemove: p.avatarPath != null);
    if (!mounted || act == null) return;
    setState(() => _busy = true);
    try {
      if (act == 'remove') {
        await _db.from('profiles').update({'avatar_path': null}).eq('id', _uid);
        await _dropFile(p.avatarPath);
        if (mounted) setState(() => _p = p.copyWith(clearAvatar: true));
      } else {
        final x = await _picker.pickImage(
          source: act == 'camera' ? ImageSource.camera : ImageSource.gallery,
          maxWidth: 512,
          maxHeight: 512,
          imageQuality: 85,
        );
        if (x != null) {
          final path =
              '$_uid/avatar_${DateTime.now().millisecondsSinceEpoch}.${_extFor(x.path)}';
          await _db.storage.from('avatars').upload(path, File(x.path),
              fileOptions: FileOptions(contentType: _mimeFor(x.path)));
          await _db.from('profiles').update({'avatar_path': path}).eq('id', _uid);
          await _dropFile(p.avatarPath);
          if (mounted) setState(() => _p = p.copyWith(avatarPath: path));
        }
      }
    } catch (_) {
      if (mounted) _toast(context, 'تعذر تغيير الصورة. جرّب مرة ثانية.');
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _dropFile(String? path) async {
    if (path == null) return;
    try {
      await _db.storage.from('avatars').remove([path]);
    } catch (_) {}
  }

  Future<void> _saveName() async {
    final p = _p;
    if (p == null || _busy) return;
    final n = _name.text.trim();
    setState(() => _busy = true);
    try {
      await _db
          .from('profiles')
          .update({'display_name': n.isEmpty ? null : n}).eq('id', _uid);
      if (mounted) {
        setState(() => _p = n.isEmpty
            ? Profile(
                id: p.id,
                username: p.username,
                avatarPath: p.avatarPath,
                showOnline: p.showOnline,
                readReceipts: p.readReceipts,
                gender: p.gender)
            : p.copyWith(displayName: n));
        _toast(context, 'تم حفظ الاسم');
      }
    } catch (_) {
      if (mounted) _toast(context, 'تعذر حفظ الاسم.');
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _toggle(String column, bool v) async {
    final p = _p;
    if (p == null) return;
    setState(() => _p = column == 'show_online'
        ? p.copyWith(showOnline: v)
        : p.copyWith(readReceipts: v));
    try {
      await _db.from('profiles').update({column: v}).eq('id', _uid);
    } catch (_) {
      if (!mounted) return;
      setState(() => _p = p);
      _toast(context, 'تعذر حفظ الإعداد.');
    }
  }

  Future<void> _newRecovery() async {
    setState(() => _busy = true);
    try {
      final code = await _issueRecoveryCode();
      if (!mounted) return;
      setState(() => _busy = false);
      await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => RecoveryCodeScreen(
              code: code, onDone: (c) => Navigator.of(c).pop())));
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      _toast(context, 'تعذر إنشاء الرمز. جرّب مرة ثانية.');
    }
  }

  Future<void> _logout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تسجيل الخروج؟'),
        content: const Text('تقدر ترجع تدخل بيوزرك وكلمة السر بأي وقت.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('تراجع')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('خروج')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    await Push.remove();
    try {
      await _db.auth.signOut();
    } catch (_) {}
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const Boot()), (_) => false);
  }

  Future<void> _deleteAccount() async {
    final p = _p;
    if (p == null) return;
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف الحساب نهائياً؟'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text(
              'راح ينحذف حسابك وكل رسائلك وصورك ومحادثتك عند الطرفين، وما يمكن التراجع.'),
          const SizedBox(height: 12),
          TextField(
            controller: ctrl,
            textDirection: TextDirection.ltr,
            decoration:
                InputDecoration(hintText: 'اكتب للتأكيد: ${p.username}'),
          ),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('تراجع')),
          TextButton(
              onPressed: () => Navigator.pop(
                  ctx, ctrl.text.trim().toLowerCase() == p.username),
              child: const Text('حذف نهائي',
                  style: TextStyle(color: Color(0xFFFF6B60)))),
        ],
      ),
    );
    ctrl.dispose();
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      // نمسح الملفات من التخزين (ما يهم لو فشل)
      final chat = widget.chat;
      if (chat != null) {
        try {
          final files =
              await _db.storage.from('chat-media').list(path: chat.id);
          if (files.isNotEmpty) {
            await _db.storage
                .from('chat-media')
                .remove(files.map((f) => '${chat.id}/${f.name}').toList());
          }
        } catch (_) {}
      }
      try {
        final mine = await _db.storage.from('avatars').list(path: _uid);
        if (mine.isNotEmpty) {
          await _db.storage
              .from('avatars')
              .remove(mine.map((f) => '$_uid/${f.name}').toList());
        }
      } catch (_) {}
      await Push.remove();
      await _db.rpc('delete_my_account');
      try {
        await _db.auth.signOut();
      } catch (_) {}
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const Boot()), (_) => false);
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      _toast(context, 'تعذر حذف الحساب. جرّب مرة ثانية.');
    }
  }

  Future<void> _setGender(String g) async {
    final p = _p;
    if (p == null || p.gender == g) return;
    setState(() => _p = p.copyWith(gender: g));
    try {
      await _db.from('profiles').update({'gender': g}).eq('id', _uid);
    } catch (_) {
      if (!mounted) return;
      setState(() => _p = p);
      _toast(context, 'تعذر حفظ الجنس.');
    }
  }

  Future<void> _unlink() async {
    final chat = widget.chat;
    final p = _p;
    if (chat == null || p == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إلغاء الارتباط؟'),
        content: const Text(
            'راح تنحذف المحادثة وكل الرسائل والصور عند الطرفين، وتقدر ترتبط بشخص جديد برمز دعوة.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('تراجع')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('إلغاء الارتباط',
                  style: TextStyle(color: Color(0xFFFF6B60)))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      // نمسح ملفات الصور من التخزين (ما يهم لو فشل)
      try {
        final files = await _db.storage.from('chat-media').list(path: chat.id);
        if (files.isNotEmpty) {
          await _db.storage
              .from('chat-media')
              .remove(files.map((f) => '${chat.id}/${f.name}').toList());
        }
      } catch (_) {}
      await _db.rpc('unlink_chat');
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => PairScreen(me: p.username)),
        (_) => false,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      _toast(context, 'تعذر إلغاء الارتباط. جرّب مرة ثانية.');
    }
  }
}
