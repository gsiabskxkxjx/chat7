part of 'main.dart';

// ---------- المستخدمين ----------

class UsersPage extends StatefulWidget {
  const UsersPage({super.key});

  @override
  State<UsersPage> createState() => _UsersPageState();
}

class _UsersPageState extends State<UsersPage> {
  static const _page = 50;
  final _q = TextEditingController();
  final List<Map<String, dynamic>> _items = [];
  Timer? _debounce;
  int _gen = 0;
  bool _loading = true;
  bool _more = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _q.dispose();
    super.dispose();
  }

  Future<void> _load({bool reset = false}) async {
    final my = ++_gen;
    setState(() {
      _loading = true;
      if (reset) _error = null;
    });
    try {
      final off = reset ? 0 : _items.length;
      final r = _list(await _rpc('admin_users_list', {
        'p_q': _q.text.trim(),
        'p_limit': _page,
        'p_offset': off,
      }));
      if (!mounted || my != _gen) return;
      setState(() {
        if (reset) _items.clear();
        _items.addAll(r);
        _more = r.length >= _page;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || my != _gen) return;
      setState(() {
        _error = _err(e);
        _loading = false;
      });
    }
  }

  Future<void> _open(Map<String, dynamic> u) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => UserDetailScreen(id: _s(u['id']), username: _s(u['username'])),
    ));
    if (mounted) _load(reset: true);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 6),
          child: TextField(
            controller: _q,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'ابحث باسم المستخدم أو الاسم أو المعرّف',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _q.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () {
                        _q.clear();
                        _load(reset: true);
                      },
                    ),
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (_) {
              _debounce?.cancel();
              _debounce = Timer(const Duration(milliseconds: 400), () => _load(reset: true));
              setState(() {});
            },
            onSubmitted: (_) => _load(reset: true),
          ),
        ),
        Expanded(child: _body()),
      ],
    );
  }

  Widget _body() {
    if (_items.isEmpty) {
      if (_loading) return const Center(child: CircularProgressIndicator());
      if (_error != null) return _ErrorBox(message: _error!, onRetry: () => _load(reset: true));
      return const _Empty('ما في مستخدمين بهالبحث');
    }
    return RefreshIndicator(
      onRefresh: () => _load(reset: true),
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _items.length + (_more ? 1 : 0),
        itemBuilder: (context, i) {
          if (i >= _items.length) {
            return Padding(
              padding: const EdgeInsets.all(12),
              child: Center(
                child: FilledButton.tonal(
                  onPressed: _loading ? null : () => _load(),
                  child: const Text('عرض المزيد'),
                ),
              ),
            );
          }
          final u = _items[i];
          final name = _s(u['display_name']).isNotEmpty ? _s(u['display_name']) : '@${_s(u['username'])}';
          final tags = <Widget>[
            if (u['banned'] == true) const _Tag('محظور', color: Color(0xFFEF5350)),
            if (u['is_admin'] == true) const _Tag('أدمن', color: Color(0xFF7C4DFF)),
            if (u['online'] == true) const _Tag('أونلاين', color: Color(0xFF66BB6A)),
            if (u['linked'] != true) const _Tag('بدون محادثة'),
            if (u['e2e'] == true) const _Tag('مشفّر', color: Color(0xFF26A69A)),
            if (u['phone_verified'] == true) const _Tag('موثّق', color: Color(0xFF42A5F5)),
          ];
          return ListTile(
            leading: CircleAvatar(child: Text(_s(u['username'], '?').substring(0, 1).toUpperCase())),
            title: Text(name),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('@${_s(u['username'])} · آخر ظهور ${_ago(u['last_seen'])}'),
                if (tags.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Wrap(spacing: 4, runSpacing: 4, children: tags)),
              ],
            ),
            isThreeLine: tags.isNotEmpty,
            trailing: const Icon(Icons.chevron_left_rounded),
            onTap: () => _open(u),
          );
        },
      ),
    );
  }
}

class UserDetailScreen extends StatelessWidget {
  const UserDetailScreen({super.key, required this.id, required this.username});
  final String id;
  final String username;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('@$username')),
      body: _Async<Map<String, dynamic>>(
        load: () async => _map(await _rpc('admin_user_detail', {'p_id': id})),
        builder: (context, d, reload) => _UserBody(d: d, reload: reload),
      ),
    );
  }
}

class _UserBody extends StatelessWidget {
  const _UserBody({required this.d, required this.reload});
  final Map<String, dynamic> d;
  final Future<void> Function() reload;

  String get _id => _s(d['id']);
  bool get _banned {
    final b = _parse(d['banned_until']);
    return b != null && b.isAfter(DateTime.now());
  }

  Future<void> _run(BuildContext context, Future<dynamic> Function() f, String done) async {
    try {
      await f();
      if (context.mounted) _toast(context, done);
      await reload();
    } catch (e) {
      if (context.mounted) _toast(context, _err(e));
    }
  }

  Future<void> _ban(BuildContext context) async {
    if (_banned) {
      await _run(context, () => _rpc('admin_ban', {'p_id': _id, 'p_ban': false}), 'تم فك الحظر');
      return;
    }
    final r = await _fieldsDialog(context, 'حظر @${_s(d['username'])}', [('السبب (اختياري، يبقى بسجل الإدارة)', 200, 3)], ok: 'حظر');
    if (r == null || !context.mounted) return;
    await _run(context, () => _rpc('admin_ban', {'p_id': _id, 'p_ban': true, 'p_reason': r[0]}), 'تم الحظر وطلعناه من كل أجهزته');
  }

  Future<void> _logout(BuildContext context) async {
    final ok = await _confirm(context, title: 'تسجيل خروج', body: 'يطلع المستخدم من كل أجهزته ويدخل من جديد.');
    if (!ok || !context.mounted) return;
    await _run(context, () => _rpc('admin_logout_user', {'p_id': _id}), 'تم تسجيل الخروج');
  }

  Future<void> _unlink(BuildContext context) async {
    final ok = await _confirm(context,
        title: 'فك ربط المحادثة',
        body: 'تنحذف المحادثة بين @${_s(d['username'])} وشريكه مع كل محتواها، والاثنين يرجعون بدون ربط. ما ينرجع.',
        ok: 'فك الربط',
        danger: true);
    if (!ok || !context.mounted) return;
    await _run(context, () => _rpc('admin_unlink_user', {'p_id': _id}), 'تم فك الربط');
  }

  Future<void> _resetE2e(BuildContext context) async {
    final ok = await _confirm(context,
        title: 'إعادة ضبط مفاتيح التشفير',
        body: 'تنحذف مفاتيحه ورمز الاسترجاع من السيرفر. يسوي مفاتيح جديدة، والرسائل القديمة المشفّرة ما ترجع تنفتح له، وشريكه يشوف تنبيه تغيّر رمز الأمان. استعملها فقط لمن يضيّع كل شي.',
        ok: 'إعادة ضبط',
        danger: true);
    if (!ok || !context.mounted) return;
    await _run(context, () => _rpc('admin_reset_e2e', {'p_id': _id}), 'تمت إعادة الضبط');
  }

  Future<void> _push(BuildContext context) async {
    final r = await _fieldsDialog(context, 'إشعار لـ @${_s(d['username'])}', [('العنوان', 60, 1), ('النص', 240, 4)]);
    if (r == null || !context.mounted) return;
    try {
      final n = _int(await _rpc('admin_broadcast', {'p_title': r[0], 'p_body': r[1], 'p_user': _id}));
      if (context.mounted) _toast(context, n == 0 ? 'ما عنده جهاز يستقبل إشعارات' : 'انرسل ($n جهاز)');
    } catch (e) {
      if (context.mounted) _toast(context, _err(e));
    }
  }

  Future<void> _delete(BuildContext context) async {
    final name = _s(d['username']);
    final r = await _fieldsDialog(context, 'حذف نهائي', [('اكتب اسم المستخدم ($name) للتأكيد', 60, 1)], ok: 'حذف');
    if (r == null || !context.mounted) return;
    if (r[0].toLowerCase() != name.toLowerCase()) {
      _toast(context, 'الاسم ما يطابق. ما انحذف شي');
      return;
    }
    try {
      await _rpc('admin_delete_user', {'p_id': _id});
      if (context.mounted) {
        _toast(context, 'تم حذف الحساب');
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (context.mounted) _toast(context, _err(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final devices = _list(d['devices']);
    final errors = _list(d['errors']);
    final isAdmin = d['is_admin'] == true;
    return RefreshIndicator(
      onRefresh: reload,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 28),
        children: [
          _Section('الحساب', children: [
            _KV('الاسم', _s(d['display_name'], '—')),
            _KV('المعرّف', _s(d['id'])),
            _KV('انضم', _dt(d['created_at'])),
            _KV('آخر ظهور', '${_dt(d['last_seen'])} (${_ago(d['last_seen'])})'),
            _KV('آخر دخول', _dt(d['last_sign_in'])),
            _KV('الحالة', _banned ? 'محظور' : (d['online'] == true ? 'أونلاين' : 'عادي')),
            _KV('توثيق الرقم', d['phone_verified'] == true ? 'موثّق' : 'لا'),
            _KV('المنطقة الزمنية', _s(d['tz'], '—')),
            if (isAdmin) const _KV('الدور', 'أدمن'),
          ]),
          _Section('النشاط', children: [
            _KV('الشريك', _s(d['partner']).isEmpty ? 'بدون ربط' : '@${_s(d['partner'])}'),
            _KV('مرتبطين من', _dt(d['chat_since'])),
            _KV('رسائل أرسلها', '${_int(d['msgs_sent'])} (العدد فقط)'),
            _KV('أجهزة إشعارات', '${_int(d['push_tokens'])}'),
            _KV('تشفير E2EE', d['e2e_key'] == true ? 'مفعّل' : 'غير مفعّل'),
            _KV('رمز استرجاع', d['recovery_code'] == true ? 'محفوظ' : 'لا'),
            _KV('بلاغات عليه', '${_int(d['reports_against'])}'),
            _KV('بلاغات قدّمها', '${_int(d['reports_by'])}'),
          ]),
          _Section('الأجهزة', children: [
            if (devices.isEmpty) const _Empty('ما في أجهزة مسجّلة'),
            for (final v in devices)
              _KV(_s(v['name'], 'جهاز'), '${_s(v['platform'])} · ${_s(v['version'], '?')} · ${_ago(v['last_seen'])}'),
          ]),
          if (errors.isNotEmpty)
            _Section('آخر أخطاء من جهازه', children: [
              for (final e in errors)
                _KV(_ago(e['at']), '${_s(e['context'])}: ${_s(e['message'])}'),
            ]),
          if (!isAdmin)
            _Section('إجراءات', children: [
              ListTile(
                leading: Icon(_banned ? Icons.lock_open_rounded : Icons.block_rounded),
                title: Text(_banned ? 'فك الحظر' : 'حظر الحساب'),
                onTap: () => _ban(context),
              ),
              ListTile(
                leading: const Icon(Icons.notifications_active_rounded),
                title: const Text('إرسال إشعار له'),
                onTap: () => _push(context),
              ),
              ListTile(
                leading: const Icon(Icons.logout_rounded),
                title: const Text('تسجيل خروج من كل أجهزته'),
                onTap: () => _logout(context),
              ),
              if (_s(d['partner']).isNotEmpty)
                ListTile(
                  leading: const Icon(Icons.link_off_rounded),
                  title: const Text('فك ربط المحادثة'),
                  onTap: () => _unlink(context),
                ),
              ListTile(
                leading: const Icon(Icons.vpn_key_off_rounded),
                title: const Text('إعادة ضبط مفاتيح التشفير'),
                onTap: () => _resetE2e(context),
              ),
              ListTile(
                leading: const Icon(Icons.delete_forever_rounded, color: Color(0xFFEF5350)),
                title: const Text('حذف الحساب نهائياً', style: TextStyle(color: Color(0xFFEF5350))),
                onTap: () => _delete(context),
              ),
            ]),
        ],
      ),
    );
  }
}
