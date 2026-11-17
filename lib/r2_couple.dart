part of 'main.dart';

// ---------- الجولة الثانية: الثنائي ----------
// اسم دلع (312)، شنو أحتاج اليوم (313)، نبض العلاقة ومستوياتها (314/378)،
// كبسولة زمنية ورسالة للمستقبل (311/317)، وضع المسافة (320)، حالة قصيرة بمؤقت (354)

/// شريط معلومات موحّد بأعلى المحادثة
Widget _r2Bar(String emoji, String text, {VoidCallback? onTap, VoidCallback? onClose}) => Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Glass(
          radius: 20,
          shadow: false,
          padding: const EdgeInsets.fromLTRB(14, 8, 4, 8),
          child: Row(children: [
            Text(emoji, style: const TextStyle(fontSize: _Fs.display)),
            const SizedBox(width: 10),
            Expanded(
                child: Text(text,
                    maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: _Fs.meta))),
            if (onClose != null)
              IconButton(
                  tooltip: 'إغلاق', onPressed: onClose, icon: const Icon(Icons.close_rounded, size: 18))
            else
              const SizedBox(width: 10),
          ]),
        ),
      ),
    );

Duration? _parseOffset(String? s) => pure.parseOffset(s);

String _offsetStr(Duration d) => pure.offsetStr(d);

extension _R2Live on _ChatState {
  Future<void> _loadLive() async {
    try {
      final pid = await _R2.partnerId(widget.chat.id);
      if (pid == null) return;
      final me = _db.auth.currentUser?.id;
      final p = await _db.from('profiles').select('status_text,status_until,tz').eq('id', pid).maybeSingle();
      final needs = await _db
          .from('daily_needs')
          .select('user_id,need')
          .eq('chat_id', widget.chat.id)
          .eq('day', _dayStr(DateTime.now()));
      final nicks = await _db.from('chat_nicknames').select('setter,nick').eq('chat_id', widget.chat.id);
      String? need;
      for (final r in needs) {
        if (r['user_id'] == pid) need = r['need'] as String?;
      }
      String? nick;
      for (final r in nicks) {
        if (r['setter'] == me) nick = r['nick'] as String?;
      }
      if (!mounted) return;
      setState(() {
        _pLive = p;
        _pNeed = need;
        _myNick = nick;
      });
    } catch (_) {}
  }

  List<Widget> _liveBars() {
    final out = <Widget>[];
    final name = _title();
    final p = _pLive;
    if (p != null) {
      final txt = '${p['status_text'] ?? ''}'.trim();
      final until = DateTime.tryParse('${p['status_until']}')?.toLocal();
      if (txt.isNotEmpty && (until == null || until.isAfter(DateTime.now()))) {
        out.add(_r2Bar('💬', '$name: $txt${until == null ? '' : ' (لين ${_Fmt.time(until)})'}'));
      }
      if (_R2Store.get<bool>('distance') == true) {
        final off = _parseOffset(p['tz'] as String?);
        if (off != null) {
          final there = DateTime.now().toUtc().add(off);
          final diff = off - DateTime.now().timeZoneOffset;
          final h = diff.inMinutes / 60;
          out.add(_r2Bar('🌍',
              'الساعة عنده ${_Fmt.time(there)}${h == 0 ? ' (نفس توقيتك)' : ' · الفرق ${_Fmt.digits(h.abs().toStringAsFixed(h.abs() % 1 == 0 ? 0 : 1))} ساعة ${h > 0 ? 'قدّامك' : 'ورا منك'}'}'));
        }
      }
    }
    if (_pNeed != null && _pNeed!.isNotEmpty) {
      out.add(_r2Bar('🫶', '$name يحتاج اليوم: $_pNeed'));
    }
    return out;
  }
}

// ===== شنو أحتاج اليوم =====

const _needOptions = [
  ('🎧', 'أسمعني'),
  ('💪', 'شجّعني'),
  ('🤫', 'أبي هدوء'),
  ('🤗', 'أبي حضن'),
  ('😂', 'أضحكني'),
  ('🍽️', 'اهتم بيّ شوي'),
  ('😴', 'تعبان'),
  ('🥰', 'قول لي كلمة حلوة'),
];

class NeedScreen extends StatefulWidget {
  const NeedScreen({super.key, required this.chatId});
  final String chatId;

  @override
  State<NeedScreen> createState() => _NeedState();
}

class _NeedState extends State<NeedScreen> {
  String? _cur;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(() async {
      try {
        final me = _db.auth.currentUser?.id;
        final r = await _db
            .from('daily_needs')
            .select('need')
            .eq('chat_id', widget.chatId)
            .eq('user_id', me ?? '')
            .eq('day', _dayStr(DateTime.now()))
            .maybeSingle();
        if (mounted) setState(() => _cur = r?['need'] as String?);
      } catch (_) {}
    }());
  }

  Future<void> _set(String? need) async {
    setState(() => _busy = true);
    final me = _db.auth.currentUser?.id;
    try {
      if (need == null) {
        await _net(_db
            .from('daily_needs')
            .delete()
            .eq('chat_id', widget.chatId)
            .eq('user_id', me ?? '')
            .eq('day', _dayStr(DateTime.now())));
      } else {
        await _net(_db.from('daily_needs').upsert({
          'chat_id': widget.chatId,
          'user_id': me,
          'day': _dayStr(DateTime.now()),
          'need': need,
        }, onConflict: 'chat_id,user_id,day'));
      }
      if (mounted) setState(() => _cur = need);
    } catch (e) {
      if (mounted) _toast(context, _friendlyError(e));
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) => _R2Page(
        title: 'شنو أحتاج اليوم',
        child: ListView(padding: const EdgeInsets.all(_Sp.lg), children: [
          const Text('اختر شنو تحتاج اليوم، وتظهر للطرف الثاني بأعلى المحادثة. بدون ما تشرح.',
              style: TextStyle(height: 1.6, color: Color(0xCCFFFFFF))),
          const SizedBox(height: _Sp.lg),
          Wrap(spacing: 10, runSpacing: 10, children: [
            for (final o in _needOptions)
              ChoiceChip(
                label: Text('${o.$1} ${o.$2}', style: const TextStyle(fontSize: _Fs.title)),
                selected: _cur == o.$2,
                onSelected: _busy ? null : (_) => _set(o.$2),
              ),
          ]),
          const SizedBox(height: _Sp.lg),
          if (_cur != null) TextButton(onPressed: () => _set(null), child: const Text('مسح اختيار اليوم')),
        ]),
      );
}

// ===== اسم الدلع =====

class NickScreen extends StatefulWidget {
  const NickScreen({super.key, required this.chatId});
  final String chatId;

  @override
  State<NickScreen> createState() => _NickState();
}

class _NickState extends State<NickScreen> {
  final _c = TextEditingController();
  String? _theirs;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(() async {
      try {
        final me = _db.auth.currentUser?.id;
        final rows = await _db.from('chat_nicknames').select('setter,nick').eq('chat_id', widget.chatId);
        for (final r in rows) {
          if (r['setter'] == me) {
            _c.text = '${r['nick']}';
          } else {
            _theirs = '${r['nick']}';
          }
        }
        if (mounted) setState(() {});
      } catch (_) {}
    }());
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final t = _c.text.trim();
    setState(() => _busy = true);
    final me = _db.auth.currentUser?.id;
    try {
      if (t.isEmpty) {
        await _net(_db.from('chat_nicknames').delete().eq('chat_id', widget.chatId).eq('setter', me ?? ''));
      } else {
        await _net(_db.from('chat_nicknames').upsert(
            {'chat_id': widget.chatId, 'setter': me, 'nick': t}, onConflict: 'chat_id,setter'));
      }
      if (mounted) _toast(context, t.isEmpty ? 'انمسح الاسم.' : 'انحفظ الاسم. يظهر عندك بالمحادثة.');
    } catch (e) {
      if (mounted) _toast(context, _friendlyError(e));
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) => _R2Page(
        title: 'اسم الدلع',
        child: ListView(padding: const EdgeInsets.all(_Sp.lg), children: [
          const Text('اسم تناديه فيه بالمحادثة. يظهر عندك بس، والطرف الثاني يحط لك اسمك.',
              style: TextStyle(height: 1.6, color: Color(0xCCFFFFFF))),
          const SizedBox(height: _Sp.lg),
          TextField(
              controller: _c,
              maxLength: 20,
              decoration: const InputDecoration(hintText: 'مثلاً: قلبي، حياتي...')),
          _Btn(label: 'احفظ', onTap: _save, busy: _busy),
          if (_theirs != null) ...[
            const SizedBox(height: _Sp.xl),
            Glass(radius: 20, child: Text('الطرف الثاني ينادينك: $_theirs 💞', textAlign: TextAlign.center)),
          ],
        ]),
      );
}

// ===== حالتي القصيرة ووضع المسافة =====

const _statusOptions = ['مشغول', 'نايم', 'بالدوام', 'بالطريق', 'رايق', 'أدرس', 'بالاجتماع'];

class StatusScreen extends StatefulWidget {
  const StatusScreen({super.key});

  @override
  State<StatusScreen> createState() => _StatusState();
}

class _StatusState extends State<StatusScreen> {
  String? _cur;

  @override
  void initState() {
    super.initState();
    unawaited(() async {
      try {
        final r = await _db
            .from('profiles')
            .select('status_text,status_until')
            .eq('id', _db.auth.currentUser?.id ?? '')
            .maybeSingle();
        final u = DateTime.tryParse('${r?['status_until']}')?.toLocal();
        if (mounted && (u == null || u.isAfter(DateTime.now()))) {
          setState(() => _cur = r?['status_text'] as String?);
        }
      } catch (_) {}
    }());
  }

  Future<void> _set(String? text, Duration? d) async {
    try {
      await _net(_db.from('profiles').update({
        'status_text': text,
        'status_until': text == null || d == null ? null : DateTime.now().add(d).toUtc().toIso8601String(),
      }).eq('id', _db.auth.currentUser?.id ?? ''));
      if (mounted) setState(() => _cur = text);
    } catch (e) {
      if (mounted) _toast(context, _friendlyError(e));
    }
  }

  Future<void> _pick(String t) async {
    final d = await showModalBottomSheet<Duration>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final o in const [
            ('نصف ساعة', Duration(minutes: 30)),
            ('ساعة', Duration(hours: 1)),
            ('3 ساعات', Duration(hours: 3)),
            ('لين نهاية اليوم', Duration(hours: 12)),
          ])
            ListTile(title: Text(o.$1), onTap: () => Navigator.pop(ctx, o.$2)),
        ]),
      ),
    );
    if (d != null) await _set(t, d);
  }

  @override
  Widget build(BuildContext context) => _R2Page(
        title: 'حالتي',
        child: ListView(padding: const EdgeInsets.all(_Sp.lg), children: [
          const Text('حالة قصيرة تظهر للطرف الثاني وتنتهي لحالها.',
              style: TextStyle(color: Color(0xCCFFFFFF))),
          const SizedBox(height: _Sp.lg),
          Wrap(spacing: 10, runSpacing: 10, children: [
            for (final s in _statusOptions)
              ChoiceChip(label: Text(s), selected: _cur == s, onSelected: (_) => _pick(s)),
          ]),
          if (_cur != null) TextButton(onPressed: () => _set(null, null), child: const Text('امسح الحالة')),
          const SizedBox(height: _Sp.xl),
          Glass(
            radius: 24,
            padding: EdgeInsets.zero,
            child: SwitchListTile(
              title: const Text('وضع المسافة'),
              subtitle: const Text('يعرض ساعة الطرف الثاني والفرق بالوقت بأعلى المحادثة'),
              value: _R2Store.get<bool>('distance') ?? false,
              onChanged: (v) async {
                await _R2Store.set('distance', v);
                if (v) unawaited(_R2.saveTimezone());
                if (mounted) setState(() {});
              },
            ),
          ),
        ]),
      );
}

// ===== نبض العلاقة ومستوياتها =====

class PulseScreen extends StatefulWidget {
  const PulseScreen({super.key, required this.chatId});
  final String chatId;

  @override
  State<PulseScreen> createState() => _PulseState();
}

class _PulseState extends State<PulseScreen> {
  int? _week, _prev, _total, _calls, _photos;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<int> _n(String? kind, {DateTime? from, DateTime? to}) async {
    var q = _db.from('messages').select('id').eq('chat_id', widget.chatId);
    if (kind != null) q = q.eq('kind', kind);
    if (from != null) q = q.gte('created_at', from.toUtc().toIso8601String());
    if (to != null) q = q.lt('created_at', to.toUtc().toIso8601String());
    final r = await q.count(CountOption.exact);
    return r.count;
  }

  Future<void> _load() async {
    try {
      final now = DateTime.now();
      final w = now.subtract(const Duration(days: 7));
      final p = now.subtract(const Duration(days: 14));
      final res = await Future.wait([
        _n(null, from: w),
        _n(null, from: p, to: w),
        _n(null),
        _n('call'),
        _n('image'),
      ]);
      if (mounted) {
        setState(() {
          _week = res[0];
          _prev = res[1];
          _total = res[2];
          _calls = res[3];
          _photos = res[4];
        });
      }
    } catch (_) {
      if (mounted) setState(() => _week = -1);
    }
  }

  static const _levels = [
    ('🥉', 'برونزي', 0),
    ('🥈', 'فضي', 1500),
    ('🥇', 'ذهبي', 6000),
    ('💎', 'بلاتيني', 20000),
    ('👑', 'ماسي', 60000),
  ];

  @override
  Widget build(BuildContext context) {
    final w = _week;
    if (w == null) return const _R2Page(title: 'نبضنا', child: Center(child: CircularProgressIndicator()));
    if (w < 0) return const _R2Page(title: 'نبضنا', child: Center(child: Text('تعذر التحميل.')));
    final calls = _calls ?? 0, photos = _photos ?? 0, total = _total ?? 0, prev = _prev ?? 0;
    final points = total + calls * 20 + photos * 5;
    var li = 0;
    for (var i = 0; i < _levels.length; i++) {
      if (points >= _levels[i].$3) li = i;
    }
    final next = li + 1 < _levels.length ? _levels[li + 1] : null;
    final (emoji, word) = w >= 300
        ? ('🔥', 'مشتعلة')
        : w >= 100
            ? ('☀️', 'دافية')
            : w >= 20
                ? ('🌤️', 'هادية')
                : ('🌙', 'نايمة');
    final trend = w > prev ? 'أنشط من الأسبوع الماضي ↗' : (w < prev ? 'أهدى من الأسبوع الماضي ↘' : 'مثل الأسبوع الماضي');
    return _R2Page(
      title: 'نبضنا',
      child: ListView(padding: const EdgeInsets.all(_Sp.lg), children: [
        Glass(
          radius: 28,
          child: Column(children: [
            Text(emoji, style: const TextStyle(fontSize: 60)),
            Text('علاقتكم $word هالأسبوع', style: const TextStyle(fontSize: _Fs.heading, fontWeight: FontWeight.w700)),
            const SizedBox(height: _Sp.xs),
            Text(trend, style: const TextStyle(color: Color(0xCCFFFFFF))),
          ]),
        ),
        const SizedBox(height: _Sp.lg),
        Glass(
          radius: 28,
          child: Column(children: [
            Text('${_levels[li].$1} المستوى ${_levels[li].$2}',
                style: const TextStyle(fontSize: _Fs.heading, fontWeight: FontWeight.w700)),
            const SizedBox(height: _Sp.sm),
            if (next != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                    value: ((points - _levels[li].$3) / (next.$3 - _levels[li].$3)).clamp(0, 1).toDouble(), minHeight: 8),
              ),
              const SizedBox(height: _Sp.xs),
              Text('للمستوى ${next.$2}: ${_Fmt.digits('${next.$3 - points}')} نقطة',
                  style: const TextStyle(fontSize: _Fs.small, color: Color(0xB3FFFFFF))),
            ] else
              const Text('وصلتوا لأعلى مستوى 👑'),
            const SizedBox(height: _Sp.sm),
            const Text('النقاط من الرسائل والمكالمات والصور. لعبة خفيفة، بدون ضغط.',
                textAlign: TextAlign.center, style: TextStyle(fontSize: _Fs.small, color: Color(0xB3FFFFFF))),
          ]),
        ),
      ]),
    );
  }
}

// ===== كبسولة زمنية ورسالة للمستقبل =====

class CapsulesScreen extends StatefulWidget {
  const CapsulesScreen({super.key, required this.chatId});
  final String chatId;

  @override
  State<CapsulesScreen> createState() => _CapsulesState();
}

class _CapsulesState extends State<CapsulesScreen> {
  List<Map<String, dynamic>>? _rows;
  String? _err;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final r = await _net(_db.rpc('capsules_list', params: {'p_chat': widget.chatId}));
      final rows = [for (final e in (r as List)) Map<String, dynamic>.from(e as Map)];
      if (mounted) setState(() => _rows = rows);
    } catch (e) {
      if (mounted) setState(() => _err = _friendlyError(e));
    }
  }

  Future<void> _new() async {
    final me = _db.auth.currentUser?.id;
    final pid = await _R2.partnerId(widget.chatId);
    if (!mounted) return;
    final c = TextEditingController();
    var forMe = false;
    var at = DateTime.now().add(const Duration(days: 365));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('كبسولة زمنية ⏳'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: c, maxLines: 4, minLines: 3, maxLength: 3000, decoration: const InputDecoration(hintText: 'اكتب رسالتك للمستقبل...')),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('للطرف الثاني')),
                  ButtonSegment(value: true, label: Text('لنفسي')),
                ],
                selected: {forMe},
                onSelectionChanged: (s) => set(() => forMe = s.first),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.lock_clock_rounded),
                title: Text('تنفتح: ${_Fmt.date(at)}'),
                onTap: () async {
                  final d = await showDatePicker(
                      context: ctx,
                      initialDate: at,
                      firstDate: DateTime.now().add(const Duration(days: 1)),
                      lastDate: DateTime.now().add(const Duration(days: 365 * 10)));
                  if (d != null) set(() => at = DateTime(d.year, d.month, d.day, 9));
                },
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('اقفلها')),
          ],
        ),
      ),
    );
    final t = c.text.trim();
    c.dispose();
    if (ok != true || t.isEmpty) return;
    final target = forMe ? me : pid;
    if (target == null) {
      if (mounted) _toast(context, 'تعذر تحديد المستلم.');
      return;
    }
    try {
      await _net(_db.from('time_capsules').insert({
        'chat_id': widget.chatId,
        'to_user': target,
        'body': t,
        'unlock_at': at.toUtc().toIso8601String(),
      }));
      await _load();
      if (mounted) _toast(context, 'انقفلت الكبسولة لين ${_Fmt.date(at)}.');
    } catch (e) {
      if (mounted) _toast(context, _friendlyError(e));
    }
  }

  Future<void> _open(Map<String, dynamic> r) async {
    try {
      await _net(_db.rpc('capsule_open', params: {'p_id': r['id']}));
    } catch (_) {}
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('💌 كبسولة مفتوحة'),
        content: SingleChildScrollView(child: Text('${r['body'] ?? ''}', style: const TextStyle(height: 1.7))),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('تمام'))],
      ),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final me = _db.auth.currentUser?.id;
    final rows = _rows;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(title: const Text('⏳ كبسولة زمنية'), backgroundColor: Colors.transparent),
      floatingActionButton: FloatingActionButton.extended(
          onPressed: _new, icon: const Icon(Icons.add_rounded), label: const Text('كبسولة')),
      body: Backdrop(
        child: SafeArea(
          child: _err != null
              ? Center(child: Text(_err!))
              : rows == null
                  ? const _SkeletonList()
                  : rows.isEmpty
                      ? const Center(
                          child: Padding(
                              padding: EdgeInsets.all(_Sp.xl),
                              child: Text('اكتب رسالة تنقفل وتنفتح بتاريخ تحدده: ميلاد، ذكرى، أو سنة جاية.',
                                  textAlign: TextAlign.center)))
                      : ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 90), children: [
                          for (final r in rows)
                            Padding(
                              padding: const EdgeInsets.only(bottom: _Sp.sm),
                              child: Glass(
                                radius: 20,
                                padding: EdgeInsets.zero,
                                child: ListTile(
                                  leading: Text(r['locked'] == true ? '🔒' : '💌', style: const TextStyle(fontSize: 26)),
                                  title: Text(r['author'] == me
                                      ? (r['to_user'] == me ? 'لنفسي' : 'منّي للطرف الثاني')
                                      : 'منه لك'),
                                  subtitle: Text(r['locked'] == true
                                      ? 'تنفتح ${_Fmt.date(DateTime.tryParse('${r['unlock_at']}')?.toLocal() ?? DateTime.now())}'
                                      : (r['body'] == null ? '' : '${r['body']}'),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis),
                                  onTap: r['locked'] == true || r['body'] == null ? null : () => _open(r),
                                ),
                              ),
                            ),
                        ]),
        ),
      ),
    );
  }
}

List<_MenuItem> _r2CoupleItems(BuildContext context, String chatId) {
  void push(Widget w) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => w));
  return [
    (Icons.record_voice_over_rounded, 'شنو أحتاج اليوم', 'تظهر للطرف الثاني بأعلى المحادثة', () => push(NeedScreen(chatId: chatId))),
    (Icons.badge_rounded, 'اسم الدلع', 'تناديه فيه بالمحادثة', () => push(NickScreen(chatId: chatId))),
    (Icons.circle_notifications_rounded, 'حالتي ووضع المسافة', 'مشغول، نايم... بمؤقت', () => push(const StatusScreen())),
    (Icons.monitor_heart_rounded, 'نبضنا ومستوانا', 'برونزي إلى ماسي', () => push(PulseScreen(chatId: chatId))),
    (Icons.lock_clock_rounded, 'كبسولة زمنية', 'رسالة تنفتح بتاريخ تحدده', () => push(CapsulesScreen(chatId: chatId))),
  ];
}
