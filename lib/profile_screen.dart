part of 'main.dart';

// ---------- الملف الشخصي والإعدادات ----------

class Profile {
  const Profile({
    required this.id,
    required this.username,
    this.displayName,
    this.avatarPath,
    this.showOnline = true,
    this.readReceipts = true,
  });

  final String id;
  final String username;
  final String? displayName;
  final String? avatarPath;
  final bool showOnline;
  final bool readReceipts;

  factory Profile.fromRow(Map<String, dynamic> r) => Profile(
        id: r['id'] as String,
        username: r['username'] as String,
        displayName: r['display_name'] as String?,
        avatarPath: r['avatar_path'] as String?,
        showOnline: (r['show_online'] as bool?) ?? true,
        readReceipts: (r['read_receipts'] as bool?) ?? true,
      );

  Profile copyWith({
    String? displayName,
    String? avatarPath,
    bool clearAvatar = false,
    bool? showOnline,
    bool? readReceipts,
  }) =>
      Profile(
        id: id,
        username: username,
        displayName: displayName ?? this.displayName,
        avatarPath: clearAvatar ? null : (avatarPath ?? this.avatarPath),
        showOnline: showOnline ?? this.showOnline,
        readReceipts: readReceipts ?? this.readReceipts,
      );
}

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, this.chat});

  /// المحادثة الحالية (null إذا غير مربوط).
  final ChatInfo? chat;

  @override
  State<ProfileScreen> createState() => _ProfileState();
}

class _ProfileState extends State<ProfileScreen> {
  final _name = TextEditingController();
  final _picker = ImagePicker();
  Profile? _p;
  String? _err;
  bool _busy = false;

  String get _uid => _db.auth.currentUser!.id;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await _db.from('profiles').select().eq('id', _uid).single();
      if (!mounted) return;
      final p = Profile.fromRow(r);
      setState(() {
        _p = p;
        _name.text = p.displayName ?? '';
      });
    } catch (_) {
      if (mounted) setState(() => _err = 'تعذر تحميل الملف الشخصي.');
    }
  }

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
                readReceipts: p.readReceipts)
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

  @override
  Widget build(BuildContext context) {
    final p = _p;
    return Scaffold(
      body: Backdrop(
        child: SafeArea(
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
              child: Row(children: [
                IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back)),
                const Text('ملفي الشخصي',
                    style:
                        TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              ]),
            ),
            Expanded(
              child: p == null
                  ? Center(
                      child: _err == null
                          ? const CircularProgressIndicator()
                          : Text(_err!))
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(children: [
                        Glass(
                          radius: 28,
                          padding: const EdgeInsets.all(20),
                          child: Column(children: [
                            GestureDetector(
                              onTap: _changePhoto,
                              child: Stack(children: [
                                _Avatar(path: p.avatarPath, radius: 56),
                                PositionedDirectional(
                                  bottom: 0,
                                  end: 0,
                                  child: CircleAvatar(
                                    radius: 18,
                                    backgroundColor: Colors.white,
                                    child: _busy
                                        ? const SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(
                                                strokeWidth: 2))
                                        : const Icon(Icons.camera_alt,
                                            size: 18, color: Colors.black),
                                  ),
                                ),
                              ]),
                            ),
                            const SizedBox(height: 16),
                            Text('@${p.username}',
                                textDirection: TextDirection.ltr,
                                style: const TextStyle(
                                    fontSize: 16, color: Color(0xCCFFFFFF))),
                            const SizedBox(height: 16),
                            TextField(
                              controller: _name,
                              inputFormatters: [
                                LengthLimitingTextInputFormatter(40)
                              ],
                              onSubmitted: (_) => _saveName(),
                              decoration: InputDecoration(
                                labelText: 'الاسم الظاهر',
                                prefixIcon: const Icon(Icons.badge_outlined),
                                filled: true,
                                fillColor: const Color(0x1FFFFFFF),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  borderSide: const BorderSide(color: _edge),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: _Btn(
                                  label: 'حفظ الاسم',
                                  onTap: _saveName,
                                  busy: _busy),
                            ),
                          ]),
                        ),
                        const SizedBox(height: 16),
                        Glass(
                          radius: 28,
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Column(children: [
                            SwitchListTile(
                              value: p.showOnline,
                              onChanged: (v) => _toggle('show_online', v),
                              title: const Text('إظهار حالة الاتصال'),
                              subtitle: const Text(
                                  'الطرف الثاني يشوف إذا كنت متصل وآخر ظهور'),
                            ),
                            SwitchListTile(
                              value: p.readReceipts,
                              onChanged: (v) => _toggle('read_receipts', v),
                              title: const Text('علامات القراءة'),
                              subtitle: const Text(
                                  'يعرف الطرف الثاني إنك قرأت رسالته'),
                            ),
                          ]),
                        ),
                        if (widget.chat != null) ...[
                          const SizedBox(height: 16),
                          Glass(
                            radius: 28,
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: ListTile(
                              leading: const Icon(Icons.link_off,
                                  color: Color(0xFFFF6B60)),
                              title: const Text('إلغاء الارتباط',
                                  style: TextStyle(color: Color(0xFFFF6B60))),
                              subtitle: Text(
                                  'مع @${widget.chat!.partner} وحذف المحادثة'),
                              onTap: _busy ? null : _unlink,
                            ),
                          ),
                        ],
                      ]),
                    ),
            ),
          ]),
        ),
      ),
    );
  }
}
