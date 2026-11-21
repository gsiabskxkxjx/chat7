part of 'main.dart';

// ---------- التحكم عن بعد بتطبيق بيناتنا + الإشعار الجماعي ----------

class ControlPage extends StatelessWidget {
  const ControlPage({super.key});

  @override
  Widget build(BuildContext context) {
    return _Async<Map<String, dynamic>>(
      load: () async => _map(await _rpc('admin_config_get')),
      builder: (context, cfg, reload) => RefreshIndicator(
        onRefresh: reload,
        child: _ControlBody(key: ValueKey(cfg.toString()), cfg: cfg, reload: reload),
      ),
    );
  }
}

class _ControlBody extends StatefulWidget {
  const _ControlBody({super.key, required this.cfg, required this.reload});
  final Map<String, dynamic> cfg;
  final Future<void> Function() reload;

  @override
  State<_ControlBody> createState() => _ControlBodyState();
}

class _ControlBodyState extends State<_ControlBody> {
  late bool _maint = widget.cfg['maintenance'] == true;
  late final TextEditingController _maintMsg = TextEditingController(text: _s(widget.cfg['maintenance_msg']));
  late final TextEditingController _minBuild = TextEditingController(
      text: _int(widget.cfg['min_build']) > 0 ? '${_int(widget.cfg['min_build'])}' : '');
  late final TextEditingController _announce = TextEditingController(text: _s(widget.cfg['announce']));
  final _title = TextEditingController();
  final _body = TextEditingController();
  String? _busy;

  @override
  void dispose() {
    _maintMsg.dispose();
    _minBuild.dispose();
    _announce.dispose();
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<bool> _set(String key, String value, String done) async {
    setState(() => _busy = key);
    try {
      await _rpc('admin_config_set', {'p_key': key, 'p_value': value});
      if (mounted) _toast(context, done);
      return true;
    } catch (e) {
      if (mounted) _toast(context, _err(e));
      return false;
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _toggleMaint(bool on) async {
    if (on) {
      final ok = await _confirm(context,
          title: 'تشغيل وضع الصيانة',
          body: 'كل المستخدمين يشوفون شاشة صيانة ولا يقدرون يستعملون التطبيق لين تطفيه.',
          ok: 'تشغيل',
          danger: true);
      if (!ok) return;
    }
    final prev = _maint;
    setState(() => _maint = on);
    final ok = await _set('maintenance', on ? '1' : '0', on ? 'وضع الصيانة شغّال' : 'وضع الصيانة مطفي');
    if (!ok && mounted) setState(() => _maint = prev);
  }

  Future<void> _publishAnnounce({required bool clear}) async {
    final text = clear ? '' : _announce.text.trim();
    if (!clear && text.isEmpty) {
      _toast(context, 'اكتب نص الإعلان');
      return;
    }
    final ok = await _set('announce', text, clear ? 'انشال الإعلان' : 'تم نشر الإعلان');
    if (ok && clear) _announce.clear();
  }

  Future<void> _saveMinBuild() async {
    final v = _minBuild.text.trim();
    if (v.isNotEmpty) {
      final ok = await _confirm(context,
          title: 'إجبار على التحديث',
          body: 'كل من إصداره أقدم من $v ما يقدر يفتح التطبيق قبل ما يحدّث. تأكد إن النسخة $v موجودة بالإصدارات.',
          ok: 'حفظ');
      if (!ok) return;
    }
    await _set('min_build', v, v.isEmpty ? 'انلغى الإجبار' : 'تم حفظ الحد الأدنى');
  }

  Future<void> _sendBroadcast() async {
    final t = _title.text.trim();
    final b = _body.text.trim();
    if (t.isEmpty || b.isEmpty) {
      _toast(context, 'اكتب العنوان والنص');
      return;
    }
    final ok = await _confirm(context,
        title: 'إشعار لكل المستخدمين', body: 'يوصل لكل الأجهزة المسجّلة:\n\n$t\n$b', ok: 'إرسال');
    if (!ok) return;
    setState(() => _busy = 'broadcast');
    try {
      final n = _int(await _rpc('admin_broadcast', {'p_title': t, 'p_body': b}));
      if (!mounted) return;
      if (n == 0) {
        _toast(context, 'ما في أجهزة تستقبل إشعارات');
      } else {
        _toast(context, 'انرسل لـ $n جهاز');
        _title.clear();
        _body.clear();
      }
    } catch (e) {
      if (mounted) _toast(context, _err(e));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Widget _save(String key, String label, VoidCallback onTap) => Align(
        alignment: AlignmentDirectional.centerEnd,
        child: FilledButton(
          onPressed: _busy == null ? onTap : null,
          child: _busy == key
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(label),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 28),
      children: [
        _Section('وضع الصيانة', children: [
          SwitchListTile(
            title: const Text('تشغيل الصيانة'),
            subtitle: const Text('يمنع الجميع من استعمال التطبيق ويعرض لهم الرسالة'),
            value: _maint,
            onChanged: _busy == null ? _toggleMaint : null,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _maintMsg,
                  maxLength: 300,
                  minLines: 1,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'رسالة الصيانة', border: OutlineInputBorder()),
                ),
                _save('maintenance_msg', 'حفظ الرسالة',
                    () => _set('maintenance_msg', _maintMsg.text.trim(), 'تم حفظ الرسالة')),
              ],
            ),
          ),
        ]),
        _Section('إجبار على التحديث', children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'اكتب رقم أقل إصدار مسموح (مثل 236). النسخ الأقدم تنجبر تحدّث. اتركه فاضي لإلغاء الإجبار.',
                  style: TextStyle(fontSize: 12, color: Color(0xB3FFFFFF)),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _minBuild,
                  keyboardType: TextInputType.number,
                  textDirection: TextDirection.ltr,
                  decoration: const InputDecoration(labelText: 'أقل رقم بيلد', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 8),
                _save('min_build', 'حفظ', _saveMinBuild),
              ],
            ),
          ),
        ]),
        _Section('إعلان داخل التطبيق', children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'يطلع مرة وحدة لكل مستخدم عند فتح التطبيق. كل إعلان جديد يطلع من جديد.',
                  style: TextStyle(fontSize: 12, color: Color(0xB3FFFFFF)),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _announce,
                  maxLength: 400,
                  minLines: 2,
                  maxLines: 5,
                  decoration: const InputDecoration(labelText: 'نص الإعلان', border: OutlineInputBorder()),
                ),
                Row(
                  children: [
                    TextButton(
                      onPressed: _busy == null ? () => _publishAnnounce(clear: true) : null,
                      child: const Text('إزالة الإعلان'),
                    ),
                    const Spacer(),
                    FilledButton(
                      onPressed: _busy == null ? () => _publishAnnounce(clear: false) : null,
                      child: _busy == 'announce'
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('نشر'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ]),
        _Section('إشعار جماعي', children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'يوصل كإشعار على كل الأجهزة، حتى والتطبيق مسكّر. حد أقصى إشعار كل دقيقة.',
                  style: TextStyle(fontSize: 12, color: Color(0xB3FFFFFF)),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _title,
                  maxLength: 60,
                  decoration: const InputDecoration(labelText: 'العنوان', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 4),
                TextField(
                  controller: _body,
                  maxLength: 240,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(labelText: 'النص', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 4),
                _save('broadcast', 'إرسال للجميع', _sendBroadcast),
              ],
            ),
          ),
        ]),
      ],
    );
  }
}
