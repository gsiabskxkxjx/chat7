part of 'main.dart';

// ---------- الجولة الثانية: التخطيط والأنشطة المشتركة (جدول plans) ----------
// ادخار (344)، مهام بيتية (345)، تصويت موعد (348)، أكلات (349)، كتب (350)،
// ورق لاصق (357)، أسباب حبي (315)، أشياء نحبها (318)، لقاء (319)، هدف أسبوعي (377)،
// 365 سؤال (316)، رحلة بأيام وقوائم تجهيز (341/342)

typedef _PlanRow = Map<String, dynamic>;

Map<String, dynamic> _dataOf(_PlanRow r) {
  final d = r['data'];
  return d is Map ? Map<String, dynamic>.from(d) : <String, dynamic>{};
}

num _numOf(Object? v) => v is num ? v : (num.tryParse('$v') ?? 0);

/// الموعد الفعلي: لو متكرر وفات، يطلع أقرب تكرار جاي
DateTime? _effDate(Map<String, dynamic> e) {
  final d = DateTime.tryParse('${e['on_date']}');
  if (d == null) return null;
  final rep = '${e['repeat_every'] ?? 'none'}';
  final today = _today();
  if (rep == 'none' || !d.isBefore(today)) return d;
  DateTime clamp(int y, int m, int day) =>
      DateTime(y, m, math.min(day, DateTime(y, m + 1, 0).day));
  var x = d;
  var guard = 0;
  while (x.isBefore(today) && guard++ < 6000) {
    switch (rep) {
      case 'weekly':
        x = x.add(const Duration(days: 7));
      case 'monthly':
        x = clamp(x.year, x.month + 1, d.day);
      case 'yearly':
        x = clamp(x.year + 1, d.month, d.day);
      default:
        return d;
    }
  }
  return x;
}

class _PlanField {
  const _PlanField(this.key, this.label, {this.type = 'text', this.title = false, this.options});
  final String key;
  final String label;
  final String type; // text | num | date | long | choice
  final bool title; // يُحفظ بعمود title
  final List<String>? options;
}

class _PlanAct {
  const _PlanAct(this.label, this.key, this.mode);
  final String label;
  final String key; // مفتاح بـ data
  final String mode; // add | set | rate
}

class _PlanSpec {
  const _PlanSpec({
    required this.kind,
    required this.title,
    required this.emoji,
    required this.empty,
    required this.fields,
    required this.sub,
    this.check = false,
    this.progress,
    this.acts = const [],
    this.sticky = false,
    this.weekly = false,
  });
  final String kind;
  final String title;
  final String emoji;
  final String empty;
  final List<_PlanField> fields;
  final String Function(_PlanRow row, Map<String, dynamic> data) sub;
  final bool check;
  final double? Function(Map<String, dynamic> data)? progress;
  final List<_PlanAct> acts;
  final bool sticky;
  final bool weekly; // علامة الإنجاز تتصفّر كل أسبوع
}

String _weekId([DateTime? t]) {
  final d = t ?? DateTime.now();
  final first = DateTime(d.year, 1, 1);
  final w = (d.difference(first).inDays + first.weekday) ~/ 7;
  return '${d.year}-$w';
}

double? _ratio(Map<String, dynamic> d, String cur, String tot) {
  final t = _numOf(d[tot]);
  if (t <= 0) return null;
  return (_numOf(d[cur]) / t).clamp(0, 1).toDouble();
}

final _planSpecs = <String, _PlanSpec>{
  'savings': _PlanSpec(
    kind: 'savings',
    title: 'أهداف ادخار',
    emoji: '💰',
    empty: 'ضيفوا أول هدف ادخار مشترك (سفرة، بيت، هدية)',
    fields: const [
      _PlanField('title', 'الهدف', title: true),
      _PlanField('target', 'المبلغ المطلوب', type: 'num'),
      _PlanField('monthly', 'الادخار الشهري', type: 'num'),
    ],
    sub: (r, d) {
      final t = _numOf(d['target']), c = _numOf(d['current']), m = _numOf(d['monthly']);
      final left = t - c;
      final months = (m > 0 && left > 0) ? ' · باقي ${(left / m).ceil()} شهر' : '';
      return '${_Fmt.digits('${c.round()}')} من ${_Fmt.digits('${t.round()}')}$months';
    },
    progress: (d) => _ratio(d, 'current', 'target'),
    acts: const [_PlanAct('أضف مبلغ', 'current', 'add')],
  ),
  'chore': _PlanSpec(
    kind: 'chore',
    title: 'مهامنا البيتية',
    emoji: '🧹',
    empty: 'ضيفوا مهمة (غسل، تسوق، ترتيب) وتتصفّر علامتها كل أسبوع',
    fields: const [
      _PlanField('title', 'المهمة', title: true),
      _PlanField('who', 'عليها', type: 'choice', options: ['أنا', 'الطرف الثاني', 'بالتناوب']),
    ],
    sub: (r, d) => 'على: ${d['who'] ?? 'بالتناوب'}',
    check: true,
    weekly: true,
  ),
  'food': _PlanSpec(
    kind: 'food',
    title: 'أكلات نجربها',
    emoji: '🍽️',
    empty: 'ضيفوا مطعم أو أكلة تبون تجربونها',
    fields: const [
      _PlanField('title', 'الأكلة أو المطعم', title: true),
      _PlanField('where', 'وين؟'),
    ],
    sub: (r, d) {
      final rate = _numOf(d['rating']).round();
      final w = '${d['where'] ?? ''}'.trim();
      return [if (w.isNotEmpty) w, if (rate > 0) '⭐' * rate].join(' · ');
    },
    check: true,
    acts: const [_PlanAct('قيّم بعد التجربة', 'rating', 'rate')],
  ),
  'book': _PlanSpec(
    kind: 'book',
    title: 'كتب نقراها',
    emoji: '📚',
    empty: 'ضيفوا كتاب تقرونه سوا أو كل واحد لحاله',
    fields: const [
      _PlanField('title', 'اسم الكتاب', title: true),
      _PlanField('pages', 'عدد الصفحات', type: 'num'),
    ],
    sub: (r, d) => 'الصفحة ${_Fmt.digits('${_numOf(d['read']).round()}')} من ${_Fmt.digits('${_numOf(d['pages']).round()}')}',
    progress: (d) => _ratio(d, 'read', 'pages'),
    acts: const [_PlanAct('وصلت لصفحة', 'read', 'set')],
  ),
  'sticky': _PlanSpec(
    kind: 'sticky',
    title: 'ورق لاصق',
    emoji: '🗒️',
    empty: 'اكتبوا ملاحظة صغيرة مثل ثلاجة البيت',
    fields: const [_PlanField('title', 'الملاحظة', title: true, type: 'long')],
    sub: (r, d) => '',
    sticky: true,
  ),
  'reason': _PlanSpec(
    kind: 'reason',
    title: 'أسباب حبي لك',
    emoji: '💗',
    empty: 'اكتب أول سبب يخليك تحبه',
    fields: const [_PlanField('title', 'السبب', title: true, type: 'long')],
    sub: (r, d) => '',
  ),
  'wish': _PlanSpec(
    kind: 'wish',
    title: 'أشياء نحبها ببعض',
    emoji: '🫶',
    empty: 'ضيفوا بالتناوب أشياء تحبونها سوا',
    fields: const [_PlanField('title', 'شي نحبه', title: true)],
    sub: (r, d) => r['created_by'] == _db.auth.currentUser?.id ? 'أنا ضفتها' : 'هو ضافها',
  ),
  'meet': _PlanSpec(
    kind: 'meet',
    title: 'بعد كم يوم نلتقي',
    emoji: '✈️',
    empty: 'حددوا موعد لقاؤكم الجاي',
    fields: const [
      _PlanField('title', 'اللقاء', title: true),
      _PlanField('date', 'تاريخ اللقاء', type: 'date'),
      _PlanField('from', 'بدأنا العد من', type: 'date'),
    ],
    sub: (r, d) {
      final t = DateTime.tryParse('${d['date']}');
      if (t == null) return '';
      final n = DateTime(t.year, t.month, t.day).difference(_today()).inDays;
      return n > 0 ? 'باقي ${_Fmt.digits('$n')} يوم' : (n == 0 ? 'اليوم! 🎉' : 'صار');
    },
    progress: (d) {
      final t = DateTime.tryParse('${d['date']}');
      final f = DateTime.tryParse('${d['from']}');
      if (t == null || f == null) return null;
      final total = t.difference(f).inDays;
      if (total <= 0) return null;
      return (_today().difference(f).inDays / total).clamp(0, 1).toDouble();
    },
  ),
  'goal': _PlanSpec(
    kind: 'goal',
    title: 'هدفنا الأسبوعي',
    emoji: '🎯',
    empty: 'اختاروا هدف للأسبوع (مكالمتين، 3 صور...)',
    fields: const [
      _PlanField('title', 'الهدف', title: true),
      _PlanField('target', 'كم مرة؟', type: 'num'),
    ],
    sub: (r, d) {
      final cur = d['week'] == _weekId() ? _numOf(d['current']) : 0;
      return '${_Fmt.digits('${cur.round()}')} من ${_Fmt.digits('${_numOf(d['target']).round()}')} هذا الأسبوع';
    },
    progress: (d) {
      final cur = d['week'] == _weekId() ? _numOf(d['current']) : 0;
      final t = _numOf(d['target']);
      return t <= 0 ? null : (cur / t).clamp(0, 1).toDouble();
    },
    acts: const [_PlanAct('سجّلنا مرة', 'current', 'add')],
    weekly: true,
  ),
};

class PlansScreen extends StatefulWidget {
  const PlansScreen({super.key, required this.chatId, required this.kind});
  final String chatId;
  final String kind;

  @override
  State<PlansScreen> createState() => _PlansState();
}

class _PlansState extends State<PlansScreen> {
  late final _PlanSpec _spec = _planSpecs[widget.kind]!;
  late final Stream<List<Map<String, dynamic>>> _s = _db
      .from('plans')
      .stream(primaryKey: ['id'])
      .eq('chat_id', widget.chatId)
      .order('id', ascending: false);

  static const _stickyColors = [0xFFFFE066, 0xFFFFA8C5, 0xFF9AD8FF, 0xFFB6F2A0, 0xFFD3B6FF];

  Future<void> _add() async {
    final ctrls = {for (final f in _spec.fields) f.key: TextEditingController()};
    final dates = <String, DateTime>{};
    final choice = <String, String>{
      for (final f in _spec.fields)
        if (f.type == 'choice') f.key: f.options!.last,
    };
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text('${_spec.emoji} ${_spec.title}'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              for (final f in _spec.fields)
                if (f.type == 'date')
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.event_rounded),
                    title: Text(dates[f.key] == null ? f.label : _Fmt.date(dates[f.key]!)),
                    onTap: () async {
                      final now = DateTime.now();
                      final d = await showDatePicker(
                          context: ctx,
                          initialDate: now,
                          firstDate: DateTime(now.year - 1),
                          lastDate: DateTime(now.year + 5));
                      if (d != null) set(() => dates[f.key] = d);
                    },
                  )
                else if (f.type == 'choice')
                  DropdownButtonFormField<String>(
                    initialValue: choice[f.key],
                    decoration: InputDecoration(labelText: f.label),
                    items: [for (final o in f.options!) DropdownMenuItem(value: o, child: Text(o))],
                    onChanged: (v) => set(() => choice[f.key] = v ?? choice[f.key]!),
                  )
                else
                  TextField(
                    controller: ctrls[f.key],
                    autofocus: f.title,
                    maxLength: f.type == 'long' ? 200 : 60,
                    maxLines: f.type == 'long' ? 3 : 1,
                    keyboardType: f.type == 'num' ? TextInputType.number : TextInputType.text,
                    decoration: InputDecoration(hintText: f.label),
                  ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حفظ')),
          ],
        ),
      ),
    );
    final data = <String, dynamic>{};
    var title = '';
    for (final f in _spec.fields) {
      if (f.type == 'date') {
        final d = dates[f.key];
        if (d != null) data[f.key] = _dayStr(d);
      } else if (f.type == 'choice') {
        data[f.key] = choice[f.key];
      } else {
        final v = ctrls[f.key]!.text.trim();
        if (f.title) {
          title = v;
        } else if (v.isNotEmpty) {
          data[f.key] = f.type == 'num' ? (num.tryParse(_asciiDigits(v)) ?? 0) : v;
        }
      }
    }
    for (final c in ctrls.values) {
      c.dispose();
    }
    if (ok != true || title.isEmpty) return;
    if (_spec.sticky) data['color'] = _stickyColors[math.Random().nextInt(_stickyColors.length)];
    try {
      await _net(_db.from('plans').insert({
        'chat_id': widget.chatId,
        'kind': _spec.kind,
        'title': title,
        'data': data,
      }));
    } catch (e) {
      if (mounted) _toast(context, _friendlyError(e));
    }
  }

  Future<void> _patch(_PlanRow r, {Map<String, dynamic>? data, bool? done}) async {
    try {
      await _net(_db.from('plans').update({
        if (data != null) 'data': data,
        if (done != null) 'done': done,
      }).eq('id', r['id']));
    } catch (e) {
      if (mounted) _toast(context, _friendlyError(e));
    }
  }

  Future<void> _act(_PlanRow r, _PlanAct a) async {
    final d = _dataOf(r);
    if (a.mode == 'rate') {
      final v = await showDialog<int>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: const Text('شلون كانت؟'),
          children: [
            for (var i = 5; i >= 1; i--)
              SimpleDialogOption(onPressed: () => Navigator.pop(ctx, i), child: Text('⭐' * i)),
          ],
        ),
      );
      if (v == null) return;
      d[a.key] = v;
      await _patch(r, data: d, done: true);
      return;
    }
    if (a.mode == 'add' && _spec.weekly) {
      // هدف أسبوعي: يتصفّر عند أسبوع جديد
      if (d['week'] != _weekId()) {
        d['week'] = _weekId();
        d[a.key] = 0;
      }
      d[a.key] = _numOf(d[a.key]) + 1;
      await _patch(r, data: d);
      return;
    }
    final c = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(a.label),
        content: TextField(
            controller: c, autofocus: true, keyboardType: TextInputType.number, decoration: const InputDecoration(hintText: 'الرقم')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حفظ')),
        ],
      ),
    );
    final v = num.tryParse(_asciiDigits(c.text.trim()));
    c.dispose();
    if (ok != true || v == null) return;
    d[a.key] = a.mode == 'add' ? _numOf(d[a.key]) + v : v;
    final prog = _spec.progress?.call(d);
    await _patch(r, data: d, done: prog != null && prog >= 1 ? true : null);
  }

  Future<void> _delete(_PlanRow r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تحذف هذا العنصر؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('لا')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('احذف')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _net(_db.from('plans').delete().eq('id', r['id']));
    } catch (e) {
      if (mounted) _toast(context, _friendlyError(e));
    }
  }

  bool _isDone(_PlanRow r) {
    if (_spec.weekly && _spec.check) return r['done'] == true && _dataOf(r)['week'] == _weekId();
    return r['done'] == true;
  }

  Widget _tile(_PlanRow r) {
    final d = _dataOf(r);
    final prog = _spec.progress?.call(d);
    final sub = _spec.sub(r, d);
    if (_spec.sticky) {
      final col = Color((d['color'] as num?)?.toInt() ?? 0xFFFFE066);
      return GestureDetector(
        onLongPress: () => _delete(r),
        child: Container(
          padding: const EdgeInsets.all(_Sp.md),
          decoration: BoxDecoration(color: col, borderRadius: BorderRadius.circular(6), boxShadow: const [
            BoxShadow(color: Color(0x55000000), blurRadius: 6, offset: Offset(2, 3)),
          ]),
          child: Text('${r['title']}',
              style: const TextStyle(color: Color(0xFF2B2B2B), fontSize: _Fs.title, height: 1.4)),
        ),
      );
    }
    final done = _isDone(r);
    return Padding(
      padding: const EdgeInsets.only(bottom: _Sp.sm),
      child: GestureDetector(
        onLongPress: () => _delete(r),
        child: Glass(
          radius: 20,
          shadow: false,
          padding: const EdgeInsets.all(_Sp.md),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              if (_spec.check)
                Checkbox(
                  value: done,
                  onChanged: (v) {
                    final nd = _dataOf(r);
                    if (_spec.weekly) nd['week'] = _weekId();
                    unawaited(_patch(r, done: v ?? false, data: _spec.weekly ? nd : null));
                  },
                ),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${r['title']}',
                      style: TextStyle(
                          fontSize: _Fs.title,
                          fontWeight: FontWeight.w600,
                          decoration: done ? TextDecoration.lineThrough : null)),
                  if (sub.isNotEmpty)
                    Text(sub, style: const TextStyle(fontSize: _Fs.small, color: Color(0xB3FFFFFF))),
                ]),
              ),
              for (final a in _spec.acts)
                TextButton(onPressed: () => _act(r, a), child: Text(a.label)),
            ]),
            if (prog != null)
              Padding(
                padding: const EdgeInsets.only(top: _Sp.sm),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(value: prog, minHeight: 8),
                ),
              ),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        extendBodyBehindAppBar: true,
        appBar: AppBar(title: Text('${_spec.emoji} ${_spec.title}'), backgroundColor: Colors.transparent),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _add,
          icon: const Icon(Icons.add_rounded),
          label: const Text('إضافة'),
        ),
        body: Backdrop(
          child: SafeArea(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: _s,
              builder: (_, snap) {
                if (snap.hasError) {
                  return const Center(child: Text('تعذر التحميل. تأكد من الإنترنت.'));
                }
                final all = snap.data;
                if (all == null) return const Center(child: CircularProgressIndicator());
                final rows = all.where((r) => r['kind'] == _spec.kind).toList();
                if (rows.isEmpty) {
                  return Center(
                      child: Padding(
                          padding: const EdgeInsets.all(_Sp.xl),
                          child: Text(_spec.empty, textAlign: TextAlign.center)));
                }
                if (_spec.sticky) {
                  return GridView.count(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
                    crossAxisCount: 2,
                    mainAxisSpacing: 14,
                    crossAxisSpacing: 14,
                    children: [for (final r in rows) _tile(r)],
                  );
                }
                return ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 90), children: [for (final r in rows) _tile(r)]);
              },
            ),
          ),
        ),
      );
}

/// يحوّل الأرقام العربية لإنجليزية قبل التحليل
String _asciiDigits(String s) {
  const ar = '٠١٢٣٤٥٦٧٨٩';
  final b = StringBuffer();
  for (final c in s.split('')) {
    final i = ar.indexOf(c);
    b.write(i >= 0 ? '$i' : c);
  }
  return b.toString();
}

// ===== تصويت على موعد (348) =====

class DatePollScreen extends StatefulWidget {
  const DatePollScreen({super.key, required this.chatId});
  final String chatId;

  @override
  State<DatePollScreen> createState() => _DatePollState();
}

class _DatePollState extends State<DatePollScreen> {
  late final Stream<List<Map<String, dynamic>>> _s = _db
      .from('plans')
      .stream(primaryKey: ['id'])
      .eq('chat_id', widget.chatId)
      .order('id', ascending: false);
  String get _me => _db.auth.currentUser?.id ?? '';

  Future<void> _new() async {
    final c = TextEditingController();
    final slots = <DateTime>[];
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('تصويت على موعد'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: c, maxLength: 60, decoration: const InputDecoration(hintText: 'شنو الموعد؟ (عشاء، سفرة...)')),
              for (final s in slots)
                ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.schedule_rounded),
                    title: Text('${_Fmt.date(s)} · ${_Fmt.time(s)}'),
                    trailing: IconButton(
                        icon: const Icon(Icons.close_rounded, size: 18),
                        onPressed: () => set(() => slots.remove(s)))),
              TextButton.icon(
                onPressed: slots.length >= 6
                    ? null
                    : () async {
                        final now = DateTime.now();
                        final d = await showDatePicker(
                            context: ctx, initialDate: now, firstDate: now, lastDate: now.add(const Duration(days: 365)));
                        if (d == null || !ctx.mounted) return;
                        final t = await showTimePicker(context: ctx, initialTime: const TimeOfDay(hour: 20, minute: 0));
                        if (t == null) return;
                        set(() => slots.add(DateTime(d.year, d.month, d.day, t.hour, t.minute)));
                      },
                icon: const Icon(Icons.add_rounded),
                label: const Text('اقترح وقت'),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('إنشاء')),
          ],
        ),
      ),
    );
    final t = c.text.trim();
    c.dispose();
    if (ok != true || t.isEmpty || slots.length < 2) {
      if (ok == true && mounted) _toast(context, 'اكتب العنوان واقترح وقتين على الأقل.');
      return;
    }
    try {
      await _net(_db.from('plans').insert({
        'chat_id': widget.chatId,
        'kind': 'poll',
        'title': t,
        'data': {
          'slots': [for (final s in slots) s.toIso8601String()],
          'votes': <String, dynamic>{},
        },
      }));
    } catch (e) {
      if (mounted) _toast(context, _friendlyError(e));
    }
  }

  Future<void> _vote(_PlanRow r, int i) async {
    final d = _dataOf(r);
    final votes = Map<String, dynamic>.from((d['votes'] as Map?) ?? {});
    final mine = [...((votes[_me] as List?) ?? const []).map((e) => (e as num).toInt())];
    mine.contains(i) ? mine.remove(i) : mine.add(i);
    votes[_me] = mine;
    d['votes'] = votes;
    try {
      await _net(_db.from('plans').update({'data': d}).eq('id', r['id']));
    } catch (e) {
      if (mounted) _toast(context, _friendlyError(e));
    }
  }

  Future<void> _close(_PlanRow r, int best) async {
    final d = _dataOf(r);
    final slots = [for (final s in (d['slots'] as List)) DateTime.parse('$s')];
    final chosen = slots[best];
    try {
      await _net(_db.from('plans').update({'done': true, 'data': {...d, 'chosen': best}}).eq('id', r['id']));
      await _db.from('chat_events').insert({
        'chat_id': widget.chatId,
        'title': '${r['title']}',
        'on_date': _dayStr(chosen),
      });
      unawaited(_sendText(widget.chatId, '📅 اتفقنا على «${r['title']}»: ${_Fmt.date(chosen)} ${_Fmt.time(chosen)}'));
      if (mounted) _toast(context, 'انضاف للتقويم.');
    } catch (e) {
      if (mounted) _toast(context, _friendlyError(e));
    }
  }

  Widget _card(_PlanRow r) {
    final d = _dataOf(r);
    final slots = [for (final s in ((d['slots'] as List?) ?? const [])) DateTime.tryParse('$s') ?? DateTime.now()];
    final votes = Map<String, dynamic>.from((d['votes'] as Map?) ?? {});
    final counts = List<int>.filled(slots.length, 0);
    for (final v in votes.values) {
      for (final i in (v as List)) {
        final k = (i as num).toInt();
        if (k >= 0 && k < counts.length) counts[k]++;
      }
    }
    var best = 0;
    for (var i = 1; i < counts.length; i++) {
      if (counts[i] > counts[best]) best = i;
    }
    final mine = [...((votes[_me] as List?) ?? const []).map((e) => (e as num).toInt())];
    final closed = r['done'] == true;
    return Padding(
      padding: const EdgeInsets.only(bottom: _Sp.md),
      child: Glass(
        radius: 22,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('${r['title']}', style: const TextStyle(fontSize: _Fs.titleL, fontWeight: FontWeight.w700)),
          const SizedBox(height: _Sp.sm),
          for (var i = 0; i < slots.length; i++)
            InkWell(
              onTap: closed ? null : () => _vote(r, i),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(children: [
                  Icon(mine.contains(i) ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                      color: closed && d['chosen'] == i ? const Color(0xFF34C759) : null),
                  const SizedBox(width: _Sp.sm),
                  Expanded(child: Text('${_Fmt.date(slots[i])} · ${_Fmt.time(slots[i])}')),
                  Text(_Fmt.digits('${counts[i]}'), style: const TextStyle(fontWeight: FontWeight.w700)),
                ]),
              ),
            ),
          if (!closed && counts.isNotEmpty && counts[best] > 0)
            TextButton(
                onPressed: () => _close(r, best),
                child: Text('اعتمد المتفق عليه (${_Fmt.date(slots[best])})')),
          if (closed) const Text('✅ انتهى التصويت وانضاف للتقويم', style: TextStyle(fontSize: _Fs.small)),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        extendBodyBehindAppBar: true,
        appBar: AppBar(title: const Text('🗳️ تصويت موعد'), backgroundColor: Colors.transparent),
        floatingActionButton: FloatingActionButton.extended(
            onPressed: _new, icon: const Icon(Icons.add_rounded), label: const Text('تصويت جديد')),
        body: Backdrop(
          child: SafeArea(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: _s,
              builder: (_, snap) {
                final all = snap.data;
                if (all == null) return const Center(child: CircularProgressIndicator());
                final rows = all.where((r) => r['kind'] == 'poll').toList();
                if (rows.isEmpty) {
                  return const Center(
                      child: Padding(
                          padding: EdgeInsets.all(_Sp.xl),
                          child: Text('اقترحوا أوقات وصوّتوا، والتطبيق يطلع المتفق عليه.', textAlign: TextAlign.center)));
                }
                return ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 90), children: [for (final r in rows) _card(r)]);
              },
            ),
          ),
        ),
      );
}

// ===== رحلة بأيام وقوائم تجهيز (341/342) =====

const _packTemplates = <String, List<String>>{
  'سفر': ['جوازات السفر', 'التذاكر والحجوزات', 'الشواحن', 'أدوية', 'ملابس', 'معجون وفرشاة', 'عطر', 'نظارات شمس', 'فلوس نقد', 'بطاقة البنك'],
  'مخيّم': ['خيمة', 'أكياس نوم', 'كشاف', 'أعواد ثقاب', 'ماي', 'أكل جاهز', 'فحم', 'ملابس دافية', 'حقيبة إسعافات', 'أكياس زبالة'],
  'طلعة': ['ماي', 'مناديل', 'شاحن متنقل', 'سماعات', 'كاميرا', 'فرشة جلوس', 'سناكات', 'واقي شمس'],
};

class TripsScreen extends StatefulWidget {
  const TripsScreen({super.key, required this.chatId});
  final String chatId;

  @override
  State<TripsScreen> createState() => _TripsState();
}

class _TripsState extends State<TripsScreen> {
  late final Stream<List<Map<String, dynamic>>> _s = _db
      .from('plans')
      .stream(primaryKey: ['id'])
      .eq('chat_id', widget.chatId)
      .order('id', ascending: false);

  Future<void> _new() async {
    final c = TextEditingController();
    final n = TextEditingController(text: '3');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('خطة سفر جديدة'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: c, maxLength: 60, autofocus: true, decoration: const InputDecoration(hintText: 'وين؟')),
          TextField(controller: n, keyboardType: TextInputType.number, decoration: const InputDecoration(hintText: 'كم يوم؟')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('إنشاء')),
        ],
      ),
    );
    final t = c.text.trim();
    final days = (int.tryParse(_asciiDigits(n.text.trim())) ?? 3).clamp(1, 30);
    c.dispose();
    n.dispose();
    if (ok != true || t.isEmpty) return;
    try {
      await _net(_db.from('plans').insert({
        'chat_id': widget.chatId,
        'kind': 'trip',
        'title': t,
        'data': {
          'days': [for (var i = 0; i < days; i++) {'stops': <String>[], 'budget': 0}],
          'pack': <Map<String, dynamic>>[],
        },
      }));
    } catch (e) {
      if (mounted) _toast(context, _friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        extendBodyBehindAppBar: true,
        appBar: AppBar(title: const Text('🧳 خطط السفر'), backgroundColor: Colors.transparent),
        floatingActionButton: FloatingActionButton.extended(
            onPressed: _new, icon: const Icon(Icons.add_rounded), label: const Text('رحلة')),
        body: Backdrop(
          child: SafeArea(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: _s,
              builder: (_, snap) {
                final all = snap.data;
                if (all == null) return const Center(child: CircularProgressIndicator());
                final rows = all.where((r) => r['kind'] == 'trip').toList();
                if (rows.isEmpty) {
                  return const Center(
                      child: Padding(
                          padding: EdgeInsets.all(_Sp.xl),
                          child: Text('خططوا لرحلتكم: محطات كل يوم، ميزانية، وقائمة تجهيز.', textAlign: TextAlign.center)));
                }
                return ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 90), children: [
                  for (final r in rows)
                    Padding(
                      padding: const EdgeInsets.only(bottom: _Sp.sm),
                      child: Glass(
                        radius: 20,
                        padding: EdgeInsets.zero,
                        child: ListTile(
                          leading: const Text('🧳', style: TextStyle(fontSize: 26)),
                          title: Text('${r['title']}'),
                          subtitle: Text('${((_dataOf(r)['days'] as List?) ?? const []).length} أيام'),
                          onTap: () => _r2Push(context, TripDetailScreen(planId: (r['id'] as num).toInt())),
                          onLongPress: () async {
                            await _db.from('plans').delete().eq('id', r['id']);
                          },
                        ),
                      ),
                    ),
                ]);
              },
            ),
          ),
        ),
      );
}

class TripDetailScreen extends StatefulWidget {
  const TripDetailScreen({super.key, required this.planId});
  final int planId;

  @override
  State<TripDetailScreen> createState() => _TripDetailState();
}

class _TripDetailState extends State<TripDetailScreen> {
  late final Stream<List<Map<String, dynamic>>> _s =
      _db.from('plans').stream(primaryKey: ['id']).eq('id', widget.planId);

  Future<void> _save(Map<String, dynamic> d) async {
    try {
      await _net(_db.from('plans').update({'data': d}).eq('id', widget.planId));
    } catch (e) {
      if (mounted) _toast(context, _friendlyError(e));
    }
  }

  Future<String?> _ask(String title, {bool number = false}) async {
    final c = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
            controller: c, autofocus: true, keyboardType: number ? TextInputType.number : TextInputType.text),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حفظ')),
        ],
      ),
    );
    final v = c.text.trim();
    c.dispose();
    return ok == true && v.isNotEmpty ? v : null;
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<List<Map<String, dynamic>>>(
        stream: _s,
        builder: (_, snap) {
          final rows = snap.data;
          if (rows == null || rows.isEmpty) {
            return const _R2Page(title: 'الرحلة', child: Center(child: CircularProgressIndicator()));
          }
          final r = rows.first;
          final d = _dataOf(r);
          final days = [for (final x in ((d['days'] as List?) ?? const [])) Map<String, dynamic>.from(x as Map)];
          final pack = [for (final x in ((d['pack'] as List?) ?? const [])) Map<String, dynamic>.from(x as Map)];
          final total = days.fold<num>(0, (a, x) => a + _numOf(x['budget']));
          return _R2Page(
            title: '${r['title']}',
            child: ListView(padding: const EdgeInsets.all(_Sp.lg), children: [
              Center(
                  child: Text('الميزانية الكلية: ${_Fmt.digits('${total.round()}')}',
                      style: const TextStyle(fontSize: _Fs.title, fontWeight: FontWeight.w700))),
              const SizedBox(height: _Sp.md),
              for (var i = 0; i < days.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: _Sp.md),
                  child: Glass(
                    radius: 20,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Row(children: [
                        Expanded(
                            child: Text('اليوم ${_Fmt.digits('${i + 1}')}',
                                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: _Fs.title))),
                        TextButton(
                          onPressed: () async {
                            final v = await _ask('ميزانية اليوم', number: true);
                            final n = v == null ? null : num.tryParse(_asciiDigits(v));
                            if (n == null) return;
                            days[i]['budget'] = n;
                            d['days'] = days;
                            await _save(d);
                          },
                          child: Text('ميزانية: ${_Fmt.digits('${_numOf(days[i]['budget']).round()}')}'),
                        ),
                      ]),
                      for (final s in ((days[i]['stops'] as List?) ?? const []))
                        Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Text('📍 $s')),
                      TextButton.icon(
                        onPressed: () async {
                          final v = await _ask('محطة جديدة أو حجز');
                          if (v == null) return;
                          days[i]['stops'] = [...((days[i]['stops'] as List?) ?? const []), v];
                          d['days'] = days;
                          await _save(d);
                        },
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text('أضف محطة'),
                      ),
                    ]),
                  ),
                ),
              _secTitle('قائمة التجهيز'),
              Wrap(spacing: 8, children: [
                for (final t in _packTemplates.keys)
                  ActionChip(
                    label: Text('قالب $t'),
                    onPressed: () async {
                      final have = pack.map((p) => p['t']).toSet();
                      for (final it in _packTemplates[t]!) {
                        if (!have.contains(it)) pack.add({'t': it, 'd': false});
                      }
                      d['pack'] = pack;
                      await _save(d);
                    },
                  ),
              ]),
              for (var i = 0; i < pack.length; i++)
                CheckboxListTile(
                  dense: true,
                  value: pack[i]['d'] == true,
                  title: Text('${pack[i]['t']}'),
                  onChanged: (v) async {
                    pack[i]['d'] = v ?? false;
                    d['pack'] = pack;
                    await _save(d);
                  },
                ),
              TextButton.icon(
                onPressed: () async {
                  final v = await _ask('غرض جديد');
                  if (v == null) return;
                  pack.add({'t': v, 'd': false});
                  d['pack'] = pack;
                  await _save(d);
                },
                icon: const Icon(Icons.add_rounded),
                label: const Text('أضف غرض'),
              ),
            ]),
          );
        },
      );
}

// ===== رحلة 365 سؤال (316) =====

const _qaTopics = [
  'العيد', 'رمضان', 'السفر', 'المدرسة', 'الجامعة', 'الشغل', 'البيت', 'الأكل', 'القهوة', 'الشاي',
  'البحر', 'المطر', 'الشتاء', 'الصيف', 'الصداقة', 'العائلة', 'الطفولة', 'الأحلام', 'الموسيقى', 'الأفلام',
  'الكتب', 'الرياضة', 'السيارات', 'النوم', 'الصباح', 'الليل', 'الهدايا', 'الأعراس', 'الزواج', 'الأطفال',
  'الحيوانات', 'الطبخ', 'التسوق', 'الألعاب', 'الصور', 'الجوال', 'الفلوس', 'المستقبل', 'الذكريات', 'الخوف',
  'الضحك', 'الحب',
];

const _qaTemplates = [
  'شنو أحلى ذكرى عندك عن {t}؟',
  'أول شي يخطر ببالك لما تسمع كلمة «{t}»؟',
  'لو تقدر تغيّر شي واحد بخصوص {t}، شنو يكون؟',
  'شنو أغرب موقف صار لك مع {t}؟',
  'شنو تعلّمت من {t}؟',
  'كيف تتخيل {t} بعد عشر سنين؟',
  'شنو تتمنى نسوي سوا بخصوص {t}؟',
  'شنو أكثر شي يعجبك بخصوص {t}؟',
  'وصّف لي {t} بثلاث كلمات.',
];

/// سؤال اليوم رقم i (0..364): توزيع يضمن عدم التكرار بالسنة
String _qaQuestion(int i) {
  final n = _qaTopics.length, tl = _qaTemplates.length;
  final k = i % (n * tl);
  final p = k % n;
  final t = (k ~/ n + k) % tl;
  return _qaTemplates[t].replaceAll('{t}', _qaTopics[p]);
}

class YearQaScreen extends StatefulWidget {
  const YearQaScreen({super.key, required this.chatId});
  final String chatId;

  @override
  State<YearQaScreen> createState() => _YearQaState();
}

class _YearQaState extends State<YearQaScreen> {
  late final Stream<List<Map<String, dynamic>>> _s = _db
      .from('plans')
      .stream(primaryKey: ['id'])
      .eq('chat_id', widget.chatId)
      .order('id', ascending: false);
  final _c = TextEditingController();
  String get _me => _db.auth.currentUser?.id ?? '';
  int _day = DateTime.now().difference(DateTime(DateTime.now().year, 1, 1)).inDays % 365;
  bool _busy = false;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _answer() async {
    final t = _c.text.trim();
    if (t.isEmpty) return;
    setState(() => _busy = true);
    try {
      await _net(_db.from('plans').insert({
        'chat_id': widget.chatId,
        'kind': 'qa',
        'title': t.length > 120 ? t.substring(0, 120) : t,
        'data': {'q': _day, 'a': t},
      }));
      _c.clear();
    } catch (e) {
      if (mounted) _toast(context, _friendlyError(e));
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) => _R2Page(
        title: '365 سؤال',
        child: StreamBuilder<List<Map<String, dynamic>>>(
          stream: _s,
          builder: (_, snap) {
            final all = snap.data;
            if (all == null) return const Center(child: CircularProgressIndicator());
            final answers = all.where((r) => r['kind'] == 'qa' && _numOf(_dataOf(r)['q']) == _day).toList();
            final mine = answers.where((r) => r['created_by'] == _me).toList();
            final theirs = answers.where((r) => r['created_by'] != _me).toList();
            return ListView(padding: const EdgeInsets.all(_Sp.lg), children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                IconButton(onPressed: () => setState(() => _day = (_day + 1) % 365), icon: const Icon(Icons.chevron_right_rounded)),
                Text('السؤال ${_Fmt.digits('${_day + 1}')} من ${_Fmt.digits('365')}'),
                IconButton(onPressed: () => setState(() => _day = (_day + 364) % 365), icon: const Icon(Icons.chevron_left_rounded)),
              ]),
              Glass(
                radius: 24,
                child: Text(_qaQuestion(_day),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: _Fs.heading, fontWeight: FontWeight.w700, height: 1.6)),
              ),
              const SizedBox(height: _Sp.lg),
              if (mine.isEmpty) ...[
                TextField(controller: _c, maxLines: 3, minLines: 2, maxLength: 400, decoration: const InputDecoration(hintText: 'جوابك...')),
                _Btn(label: 'احفظ جوابي', onTap: _answer, busy: _busy),
              ] else
                Glass(radius: 20, child: Text('جوابي: ${mine.first['title']}')),
              const SizedBox(height: _Sp.md),
              if (theirs.isNotEmpty && mine.isNotEmpty)
                Glass(radius: 20, child: Text('جوابه: ${theirs.first['title']}'))
              else if (theirs.isNotEmpty)
                const Text('جاوب الطرف الثاني. جاوب أنت أول لتشوف جوابه 👀', textAlign: TextAlign.center),
            ]);
          },
        ),
      );
}

/// قائمة شاشات الجولة الثانية للتخطيط (تظهر بقائمة 🎮)
List<_MenuItem> _r2PlanItems(BuildContext context, String chatId) {
  void push(Widget w) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => w));
  return [
    (Icons.luggage_rounded, 'خطط السفر', 'أيام ومحطات وميزانية وقائمة تجهيز', () => push(TripsScreen(chatId: chatId))),
    (Icons.savings_rounded, 'أهداف ادخار', 'هدف ومبلغ شهري وشريط تقدّم', () => push(PlansScreen(chatId: chatId, kind: 'savings'))),
    (Icons.cleaning_services_rounded, 'مهامنا البيتية', 'تتصفّر كل أسبوع', () => push(PlansScreen(chatId: chatId, kind: 'chore'))),
    (Icons.how_to_vote_rounded, 'تصويت على موعد', 'اقترحوا أوقات والتطبيق يطلع المتفق عليه', () => push(DatePollScreen(chatId: chatId))),
    (Icons.restaurant_rounded, 'أكلات نجربها', 'مع تقييم بعد التجربة', () => push(PlansScreen(chatId: chatId, kind: 'food'))),
    (Icons.auto_stories_rounded, 'كتبنا', 'نسبة الإنجاز لكل كتاب', () => push(PlansScreen(chatId: chatId, kind: 'book'))),
    (Icons.sticky_note_2_rounded, 'ورق لاصق', 'ملاحظات سريعة مثل ثلاجة البيت', () => push(PlansScreen(chatId: chatId, kind: 'sticky'))),
    (Icons.flight_land_rounded, 'بعد كم يوم نلتقي', 'عدّاد وشريط تقدّم للأزواج البعيدين', () => push(PlansScreen(chatId: chatId, kind: 'meet'))),
    (Icons.track_changes_rounded, 'هدفنا الأسبوعي', 'مكالمتين، 3 صور...', () => push(PlansScreen(chatId: chatId, kind: 'goal'))),
  ];
}
