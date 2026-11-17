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
                    tooltip: 'رجوع',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back_rounded)),
                const Text('ملفي الشخصي',
                    style:
                        TextStyle(fontSize: _Fs.display, fontWeight: FontWeight.w700)),
              ]),
            ),
            Expanded(
              child: p == null
                  ? Center(
                      child: _err == null
                          ? const CircularProgressIndicator()
                          : Text(_err!))
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(_Sp.lg),
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
                                        : const Icon(Icons.camera_alt_rounded,
                                            size: 18, color: Colors.black),
                                  ),
                                ),
                              ]),
                            ),
                            const SizedBox(height: _Sp.lg),
                            Text('@${p.username}',
                                textDirection: TextDirection.ltr,
                                style: const TextStyle(
                                    fontSize: _Fs.title, color: Color(0xCCFFFFFF))),
                            const SizedBox(height: _Sp.lg),
                            TextField(
                              controller: _name,
                              inputFormatters: [
                                LengthLimitingTextInputFormatter(40)
                              ],
                              onSubmitted: (_) => _saveName(),
                              decoration: InputDecoration(
                                labelText: 'الاسم الظاهر',
                                prefixIcon: const Icon(Icons.badge_rounded),
                                filled: true,
                                fillColor: const Color(0x1FFFFFFF),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  borderSide: const BorderSide(color: _edge),
                                ),
                              ),
                            ),
                            const SizedBox(height: _Sp.md),
                            SizedBox(
                              width: double.infinity,
                              child: _Btn(
                                  label: 'حفظ الاسم',
                                  onTap: _saveName,
                                  busy: _busy),
                            ),
                          ]),
                        ),
                        const SizedBox(height: _Sp.lg),
                        Glass(
                          radius: 28,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 14),
                          child: Row(children: [
                            const Icon(Icons.wc_rounded),
                            const SizedBox(width: _Sp.md),
                            const Text('الجنس',
                                style: TextStyle(fontSize: _Fs.title)),
                            const Spacer(),
                            ChoiceChip(
                              label: const Text('ذكر'),
                              selected: p.gender == 'male',
                              onSelected: (_) => _setGender('male'),
                            ),
                            const SizedBox(width: _Sp.sm),
                            ChoiceChip(
                              label: const Text('أنثى'),
                              selected: p.gender == 'female',
                              onSelected: (_) => _setGender('female'),
                            ),
                          ]),
                        ),
                        const SizedBox(height: _Sp.lg),
                        _secTitle('الخصوصية والأمان'),
                        Glass(
                          radius: 28,
                          padding: const EdgeInsets.symmetric(vertical: _Sp.xs),
                          child: ValueListenableBuilder<bool>(
                            valueListenable: _lockNotifier,
                            builder: (_, on, __) => SwitchListTile(
                              value: on,
                              onChanged: (_) => _toggleLockAuth(context),
                              title: const Text('قفل التطبيق بالبصمة أو الوجه'),
                              subtitle: const Text(
                                  'المدة تختارها من «القفل بعد الخروج» تحت'),
                            ),
                          ),
                        ),
                        const SizedBox(height: _Sp.lg),
                        Glass(
                          radius: 28,
                          padding: const EdgeInsets.symmetric(vertical: _Sp.xs),
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
                            const _OnlineAlertTile(),
                          ]),
                        ),
                        const SizedBox(height: _Sp.lg),
                        _secTitle('الإشعارات'),
                        Glass(
                          radius: 28,
                          padding: const EdgeInsets.symmetric(vertical: _Sp.xs),
                          child: ListTile(
                            leading: const Icon(Icons.notifications_rounded),
                            title: const Text('الإشعارات'),
                            subtitle: Text(Push.status),
                            trailing: const Icon(Icons.refresh_rounded),
                            onTap: () async {
                              await Push.start();
                              if (mounted) setState(() {});
                            },
                          ),
                        ),
                        const SizedBox(height: _Sp.lg),
                        _secTitle('الحساب'),
                        Glass(
                          radius: 28,
                          padding: const EdgeInsets.symmetric(vertical: _Sp.xs),
                          child: Column(children: [
                            const _PhoneVerifyTile(),
                            ListTile(
                              leading: const Icon(Icons.feedback_rounded),
                              title: const Text('إرسال ملاحظة'),
                              subtitle: const Text('مشكلة أو اقتراح يوصل للمطوّر'),
                              onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                      builder: (_) => const FeedbackScreen())),
                            ),
                            ListTile(
                              leading: const Icon(Icons.alternate_email_rounded),
                              title: const Text('تغيير اسم المستخدم'),
                              subtitle: Text('@${p.username} (مرة كل 30 يوم)'),
                              onTap: _busy ? null : _changeUsername,
                            ),
                            ListTile(
                              leading: const Icon(Icons.interests_rounded),
                              title: const Text('اهتماماتي'),
                              subtitle: const Text('تظهر لما تبحث عن شريك'),
                              onTap: () => _editInterests(context),
                            ),
                            ListTile(
                              leading: const Icon(Icons.key_rounded),
                              title: const Text('تغيير كلمة السر'),
                              onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                      builder: (_) =>
                                          const ChangePasswordScreen())),
                            ),
                            ListTile(
                              leading: const Icon(Icons.vpn_key_rounded),
                              title: const Text('رمز استرجاع الحساب'),
                              subtitle:
                                  const Text('ينشئ رمز جديد ويلغي القديم'),
                              onTap: _busy ? null : _newRecovery,
                            ),
                            ListTile(
                              leading: const Icon(Icons.logout_rounded),
                              title: const Text('تسجيل الخروج'),
                              onTap: _busy ? null : _logout,
                            ),
                            ListTile(
                              leading: const Icon(Icons.delete_forever_rounded,
                                  color: Color(0xFFFF6B60)),
                              title: const Text('حذف الحساب',
                                  style: TextStyle(color: Color(0xFFFF6B60))),
                              onTap: _busy ? null : _deleteAccount,
                            ),
                          ]),
                        ),
                        if (widget.chat != null) ...[
                          const SizedBox(height: _Sp.lg),
                          _secTitle('المحادثة'),
                          Glass(
                            radius: 28,
                            padding: const EdgeInsets.symmetric(vertical: _Sp.xs),
                            child: ListTile(
                              leading: const Icon(Icons.delete_sweep_rounded,
                                  color: Color(0xFFFF6B60)),
                              title: const Text('مسح سجل المحادثة',
                                  style: TextStyle(color: Color(0xFFFF6B60))),
                              subtitle: const Text(
                                  'يحذف الرسائل والوسائط عند الطرفين، والربط يبقى'),
                              onTap: _busy ? null : _clearHistory,
                            ),
                          ),
                          const SizedBox(height: _Sp.lg),
                          Glass(
                            radius: 28,
                            padding: const EdgeInsets.symmetric(vertical: _Sp.xs),
                            child: ListTile(
                              leading: const Icon(Icons.palette_rounded),
                              title: const Text('مظهر التطبيق'),
                              subtitle: const Text(
                                  'الثيم والخلفية للتطبيق كله، يشوفها الطرفين'),
                              onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                      builder: (_) => ThemeSettingsScreen(
                                          chatId: widget.chat!.id))),
                            ),
                          ),
                          const SizedBox(height: _Sp.lg),
                          Glass(
                            radius: 28,
                            padding: const EdgeInsets.symmetric(vertical: _Sp.xs),
                            child: ListTile(
                              leading: const Icon(Icons.link_off_rounded,
                                  color: Color(0xFFFF6B60)),
                              title: const Text('إلغاء الارتباط',
                                  style: TextStyle(color: Color(0xFFFF6B60))),
                              subtitle: Text(
                                  'مع @${widget.chat!.partner} وحذف المحادثة'),
                              onTap: _busy ? null : _unlink,
                            ),
                          ),
                        ],
                        const SizedBox(height: _Sp.lg),
                        _secTitle('تخصيص'),
                        const _PrefsCard(),
                        const SizedBox(height: _Sp.lg),
                        _secTitle('الأجهزة والبيانات'),
                        const _R2Tiles(),
                        const SizedBox(height: _Sp.lg),
                        _secTitle('عن التطبيق'),
                        Glass(
                          radius: 28,
                          padding: const EdgeInsets.symmetric(vertical: _Sp.xs),
                          child: ListTile(
                            leading: const Icon(Icons.info_rounded),
                            title: const Text('حول بيناتنا'),
                            subtitle: const Text('الإصدار وسياسة الخصوصية'),
                            onTap: () => _showAbout(context),
                          ),
                        ),
                      ]),
                    ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// عنوان صغير فوق كل مجموعة إعدادات
Widget _secTitle(String t) => Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(14, 4, 14, 8),
      child: Text(t,
          style: const TextStyle(
              fontSize: _Fs.meta,
              fontWeight: FontWeight.w700,
              color: Color(0xB3FFFFFF))),
    );

const _privacyUrl = 'https://gsiabskxkxjx.github.io/bainatna/';

/// صفحة "حول": الإصدار، سياسة الخصوصية، حذف الحساب، الدعم
Future<void> _showAbout(BuildContext context) => showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const _Rings(),
        title: const Text(appName, textAlign: TextAlign.center),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(
              _buildNo == 0
                  ? 'الإصدار 0.14'
                  : 'الإصدار 0.14 (بناء $_buildNo)',
              style: const TextStyle(color: Color(0xB3FFFFFF))),
          const SizedBox(height: 6),
          const Text('محادثة خاصة لشخصين.', textAlign: TextAlign.center),
          const SizedBox(height: _Sp.md),
          ListTile(
            leading: const Icon(Icons.privacy_tip_rounded),
            title: const Text('سياسة الخصوصية'),
            onTap: () => _openUrl(ctx, _privacyUrl),
          ),
          ListTile(
            leading: const Icon(Icons.person_remove_rounded),
            title: const Text('طريقة حذف الحساب'),
            onTap: () => _openUrl(ctx, _privacyUrl),
          ),
          ListTile(
            leading: const Icon(Icons.support_agent_rounded),
            title: const Text('الدعم والملاحظات'),
            onTap: () {
              Navigator.pop(ctx);
              Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const FeedbackScreen()));
            },
          ),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('إغلاق')),
        ],
      ),
    );
