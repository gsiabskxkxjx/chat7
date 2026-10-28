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
    this.gender,
    this.muteMessages = false,
    this.muteCalls = false,
  });

  final String id;
  final String username;
  final String? displayName;
  final String? avatarPath;
  final bool showOnline;
  final bool readReceipts;
  final String? gender; // male | female
  final bool muteMessages; // كتم إشعارات الرسائل
  final bool muteCalls; // كتم إشعارات المكالمات

  factory Profile.fromRow(Map<String, dynamic> r) => Profile(
        id: r['id'] as String,
        username: r['username'] as String,
        displayName: r['display_name'] as String?,
        avatarPath: r['avatar_path'] as String?,
        showOnline: (r['show_online'] as bool?) ?? true,
        readReceipts: (r['read_receipts'] as bool?) ?? true,
        gender: r['gender'] as String?,
        muteMessages: (r['mute_messages'] as bool?) ?? false,
        muteCalls: (r['mute_calls'] as bool?) ?? false,
      );

  Profile copyWith({
    String? displayName,
    String? avatarPath,
    bool clearAvatar = false,
    bool? showOnline,
    bool? readReceipts,
    String? gender,
    bool? muteMessages,
    bool? muteCalls,
  }) =>
      Profile(
        id: id,
        username: username,
        displayName: displayName ?? this.displayName,
        avatarPath: clearAvatar ? null : (avatarPath ?? this.avatarPath),
        showOnline: showOnline ?? this.showOnline,
        readReceipts: readReceipts ?? this.readReceipts,
        gender: gender ?? this.gender,
        muteMessages: muteMessages ?? this.muteMessages,
        muteCalls: muteCalls ?? this.muteCalls,
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
                                _Avatar(path: p.avatarPath, radius: 56, gender: p.gender),
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
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 14),
                          child: Row(children: [
                            const Icon(Icons.wc_outlined),
                            const SizedBox(width: 12),
                            const Text('الجنس',
                                style: TextStyle(fontSize: 16)),
                            const Spacer(),
                            ChoiceChip(
                              label: const Text('ذكر'),
                              selected: p.gender == 'male',
                              onSelected: (_) => _setGender('male'),
                            ),
                            const SizedBox(width: 8),
                            ChoiceChip(
                              label: const Text('أنثى'),
                              selected: p.gender == 'female',
                              onSelected: (_) => _setGender('female'),
                            ),
                          ]),
                        ),
                        const SizedBox(height: 16),
                        Glass(
                          radius: 28,
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: ValueListenableBuilder<bool>(
                            valueListenable: _lockNotifier,
                            builder: (_, on, __) => SwitchListTile(
                              value: on,
                              onChanged: (_) => _toggleLockAuth(context),
                              title: const Text('قفل التطبيق بالبصمة أو الوجه'),
                              subtitle: const Text(
                                  'يتقفل إذا طلعت من التطبيق أكثر من 30 ثانية'),
                            ),
                          ),
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
                            SwitchListTile(
                              value: p.muteMessages,
                              onChanged: (v) => _toggle('mute_messages', v),
                              title: const Text('كتم إشعارات الرسائل'),
                              subtitle: const Text(
                                  'ما توصلك إشعارات الرسائل، والمحادثة تبقى شغالة عادي'),
                            ),
                            SwitchListTile(
                              value: p.muteCalls,
                              onChanged: (v) => _toggle('mute_calls', v),
                              title: const Text('كتم إشعارات المكالمات'),
                              subtitle: const Text(
                                  'ما توصلك إشعارات المكالمات والتطبيق مسكّر (المكالمات داخل التطبيق ما تتأثر)'),
                            ),
                          ]),
                        ),
                        const SizedBox(height: 16),
                        Glass(
                          radius: 28,
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: ListTile(
                            leading: const Icon(Icons.notifications_outlined),
                            title: const Text('الإشعارات'),
                            subtitle: Text(Push.status),
                            trailing: const Icon(Icons.refresh),
                            onTap: () async {
                              await Push.start();
                              if (mounted) setState(() {});
                            },
                          ),
                        ),
                        const SizedBox(height: 16),
                        Glass(
                          radius: 28,
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Column(children: [
                            ListTile(
                              leading: const Icon(Icons.feedback_outlined),
                              title: const Text('إرسال ملاحظة'),
                              subtitle: const Text('مشكلة أو اقتراح يوصل للمطوّر'),
                              onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                      builder: (_) => const FeedbackScreen())),
                            ),
                            ListTile(
                              leading: const Icon(Icons.alternate_email),
                              title: const Text('تغيير اسم المستخدم'),
                              subtitle: Text('@${p.username} (مرة كل 30 يوم)'),
                              onTap: _busy ? null : _changeUsername,
                            ),
                            ListTile(
                              leading: const Icon(Icons.key_outlined),
                              title: const Text('تغيير كلمة السر'),
                              onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                      builder: (_) =>
                                          const ChangePasswordScreen())),
                            ),
                            ListTile(
                              leading: const Icon(Icons.vpn_key_outlined),
                              title: const Text('رمز استرجاع الحساب'),
                              subtitle:
                                  const Text('ينشئ رمز جديد ويلغي القديم'),
                              onTap: _busy ? null : _newRecovery,
                            ),
                            ListTile(
                              leading: const Icon(Icons.logout),
                              title: const Text('تسجيل الخروج'),
                              onTap: _busy ? null : _logout,
                            ),
                            ListTile(
                              leading: const Icon(Icons.delete_forever,
                                  color: Color(0xFFFF6B60)),
                              title: const Text('حذف الحساب',
                                  style: TextStyle(color: Color(0xFFFF6B60))),
                              onTap: _busy ? null : _deleteAccount,
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
