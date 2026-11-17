part of 'main.dart';

// ---------- تقارير الأعطال، المناسبات، ذكرى أول رسالة، تحدي 30 يوم، تصويت، تذكيرات لطيفة، خلفية متحركة، ملخص الشهر ----------

// ===== تقارير الأعطال (بدون محتوى رسائل، بس نوع الخطأ ومكانه) =====

class _Crash {
  static Future<File> _f() async =>
      File('${(await getApplicationSupportDirectory()).path}/last_crash.txt');

  static void install() {
    final prev = FlutterError.onError;
    FlutterError.onError = (d) {
      prev?.call(d);
      unawaited(_save('${d.exceptionAsString()}\n${_top(d.stack)}'));
    };
    PlatformDispatcher.instance.onError = (e, st) {
      unawaited(_save('$e\n${_top(st)}'));
      return false;
    };
  }

  static String _top(StackTrace? st) =>
      (st?.toString() ?? '').split('\n').take(8).join('\n');

  static Future<void> _save(String s) async {
    try {
      await (await _f()).writeAsString(s.length > 900 ? s.substring(0, 900) : s);
    } catch (_) {}
  }

  static Future<void> sendPending() async {
    try {
      final f = await _f();
      if (!await f.exists()) return;
      final body = await f.readAsString();
      await f.delete();
      if (!_Prefs.crashReports.value || _db.auth.currentUser == null) return;
      final lines = body.split('\n');
      await _R2Store.set('last_error', lines.first.length > 140 ? lines.first.substring(0, 140) : lines.first);
      await _db.rpc('log_error', params: {
        'p_context': 'crash',
        'p_message': lines.first,
        'p_stack': lines.skip(1).join('\n'),
        'p_version': _R2.verLabel(),
        'p_platform': defaultTargetPlatform.name,
      });
    } catch (_) {}
  }
}

// ===== المناسبات (التقويم الهجري التقريبي) =====

({int y, int m, int d}) _hijri(DateTime g) {
  final a = (14 - g.month) ~/ 12;
  final y2 = g.year + 4800 - a;
  final m2 = g.month + 12 * a - 3;
  final jd = g.day + (153 * m2 + 2) ~/ 5 + 365 * y2 + y2 ~/ 4 - y2 ~/ 100 + y2 ~/ 400 - 32045;
  var l = jd - 1948440 + 10632;
  final n = (l - 1) ~/ 10631;
  l = l - 10631 * n + 354;
  final j = ((10985 - l) ~/ 5316) * ((50 * l) ~/ 17719) + (l ~/ 5670) * ((43 * l) ~/ 15238);
  l = l - ((30 - j) ~/ 15) * ((17719 * j) ~/ 50) - (j ~/ 16) * ((15238 * j) ~/ 43) + 29;
  final m = (24 * l) ~/ 709;
  final d = l - (709 * m) ~/ 24;
  return (y: 30 * n + j - 30, m: m, d: d);
}

/// مناسبة اليوم (لو في): إيموجي، ونص الشريط
(String, String)? _season([DateTime? at]) {
  final now = at ?? DateTime.now();
  final h = _hijri(now);
  if (h.m == 9) return ('🌙', 'رمضان كريم! أرسل له بطاقة رمضان');
  if (h.m == 10 && h.d <= 3) return ('🎉', 'عيد فطر مبارك! هنّيه ببطاقة');
  if (h.m == 12 && h.d >= 9 && h.d <= 13) return ('🐑', 'عيد أضحى مبارك! هنّيه ببطاقة');
  if (now.month == 1 && now.day == 1) return ('🎆', 'سنة جديدة سعيدة! أرسل له تهنئة');
  if (now.weekday == DateTime.friday) return ('🕌', 'جمعة مباركة');
  return null;
}

// ===== تحدي 30 يوم (يستخدم القوائم المشتركة) =====

const _challenge30 = [
  'اكتب له 3 أشياء تحبها فيه', 'أرسل صورة من يومك', 'اتصلوا 10 دقايق بس للسوالف',
  'شاركه أغنية تذكرك فيه', 'أرسل له رسالة صوتية صباحية', 'اسأله عن حلم من أحلامه',
  'العبوا لعبة سوا', 'اكتب له ذكرى حلوة بينكم', 'أرسل له نكتة', 'سوّوا قائمة أفلام تشوفونها',
  'قل له شي ما قلته قبل', 'أرسل له صورة قديمة لك', 'خططوا لطلعة جاية', 'علّق له ملاحظة على جدار الحب',
  'اسأله: شنو يفرحك هالأسبوع؟', 'أرسل له بطاقة ملوّنة', 'جاوبوا سؤال اليوم', 'سوّوا تحدي الصورة',
  'اكتب له شكراً على شي سوّاه', 'شاركه هدف تبي تحققه', 'أرسل له فيديو دائري', 'اعترف بشي مضحك صار لك',
  'سوّوا قائمة أمنيات هدايا', 'اتصال فيديو قبل النوم', 'أرسل له «أفكر فيك» بوقت غير متوقع',
  'اكتب له وصف ليومكم المثالي', 'العبوا مين فينا؟', 'شاركوا أكلة تحبونها', 'اكتب له رسالة للمستقبل',
  'احتفلوا! خلّصتوا 30 يوم 🎉',
];

Future<void> _start30Day(BuildContext context, String chatId) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('تحدي 30 يوم'),
      content: const Text('كل يوم مهمة صغيرة لكم الاثنين. تنضاف لقائمة مشتركة، وتطلع لكم مهمة اليوم بالمحادثة.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('مو الحين')),
        TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('يلا نبدأ')),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  const list = 'تحدي 30 يوم';
  final today = _today();
  final rows = [
    for (var i = 0; i < _challenge30.length; i++)
      {
        'chat_id': chatId,
        'list_name': list,
        'body': 'يوم ${i + 1}: ${_challenge30[i]}',
        'due_on': _dayStr(today.add(Duration(days: i))),
      },
  ];
  try {
    try {
      await _db.from('shared_items').insert(rows);
    } on PostgrestException catch (e) {
      if (!e.message.contains('due_on')) rethrow;
      await _db.from('shared_items').insert([
        for (final r in rows) {...r}..remove('due_on'),
      ]);
    }
    unawaited(_sendText(chatId, '🏁 بدأنا تحدي 30 يوم! مهمة اليوم: ${_challenge30.first}'));
    if (context.mounted) {
      await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => SharedListsScreen(chatId: chatId, initialList: list)));
    }
  } catch (_) {
    if (context.mounted) _toast(context, 'تعذر بدء التحدي، جرّب مرة ثانية.');
  }
}

// ===== تصويت سريع (الأصوات = تفاعلات بالأرقام) =====

const _pollKeys = ['1️⃣', '2️⃣', '3️⃣', '4️⃣'];

/// يقرأ رسالة التصويت: السطر الأول السؤال، والباقي خيارات تبدأ برقم
({String q, List<String> opts})? _parsePoll(String text) {
  if (!text.startsWith('📊 ')) return null;
  final lines = text.split('\n');
  if (lines.length < 3) return null;
  final opts = <String>[];
  for (var i = 1; i < lines.length && opts.length < 4; i++) {
    final k = _pollKeys[opts.length];
    if (!lines[i].startsWith(k)) return null;
    opts.add(lines[i].substring(k.length).trim());
  }
  return opts.length >= 2 ? (q: lines.first.substring(3).trim(), opts: opts) : null;
}

class _PollMsg extends StatelessWidget {
  const _PollMsg({required this.q, required this.opts, required this.votes, this.onVote});
  final String q;
  final List<String> opts;
  final Map<String, String> votes; // رقم المستخدم -> الإيموجي
  final void Function(String key)? onVote;

  @override
  Widget build(BuildContext context) {
    final me = _meId;
    final total = votes.values.where(_pollKeys.contains).length;
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 220, maxWidth: 280),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Text('📊 $q', style: const TextStyle(fontSize: _Fs.title, fontWeight: FontWeight.w800, color: Colors.white)),
        const SizedBox(height: _Sp.sm),
        for (var i = 0; i < opts.length; i++)
          Builder(builder: (_) {
            final k = _pollKeys[i];
            final n = votes.values.where((v) => v == k).length;
            final mine = votes[me] == k;
            final theirs = votes.entries.any((e) => e.key != me && e.value == k);
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: _Press(
                onTap: onVote == null ? null : () => onVote!(k),
                scale: 0.98,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: _Sp.sm),
                  decoration: BoxDecoration(
                    color: mine ? const Color(0x55FFFFFF) : const Color(0x26000000),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: mine ? Colors.white : const Color(0x33FFFFFF)),
                  ),
                  child: Row(children: [
                    Expanded(child: Text(opts[i], style: const TextStyle(color: Colors.white))),
                    if (mine) const Text('أنت ', style: TextStyle(fontSize: _Fs.caption, color: Colors.white)),
                    if (theirs) const Text('هو ', style: TextStyle(fontSize: _Fs.caption, color: Colors.white)),
                    Text(total == 0 ? '' : '$n', style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white)),
                  ]),
                ),
              ),
            );
          }),
        if (total >= 2)
          Text(
              votes.values.toSet().length == 1 ? 'اتفقتوا! 🎉' : 'اختلفتوا 😄',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: _Fs.small, color: Color(0xCCFFFFFF))),
      ]),
    );
  }
}

// ===== تذكيرات لطيفة لبعض =====

const _gentle = [
  ('💧', 'اشرب ماي', 'اشرب ماي يا حلو 💧', 1),
  ('😴', 'نام بدري', 'نام بدري الليلة، تستاهل ترتاح 😴', 4),
  ('🍽️', 'لا تنسى تاكل', 'لا تنسى تاكل زين 🍽️', 2),
  ('☕', 'خذ استراحة', 'خذ استراحة شوي ☕', 7),
  ('🚶', 'تمشّى شوي', 'قوم تمشّى شوي، صحتك تهمني 🚶', 3),
  ('💊', 'دواك', 'لا تنسى دواك 💊', 6),
  ('📚', 'ذاكر', 'ركّز وذاكر، أنا فخور فيك 📚', 0),
  ('🤍', 'أنا هنا', 'أنا هنا إذا احتجت شي 🤍', 0),
];

Future<void> _sendGentle(BuildContext context, String chatId) async {
  final i = await showModalBottomSheet<int>(
    context: context,
    builder: (ctx) => SafeArea(
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: Text('تذكير لطيف', style: TextStyle(fontSize: _Fs.titleL, fontWeight: FontWeight.w600)),
          ),
          for (var k = 0; k < _gentle.length; k++)
            ListTile(
              leading: Text(_gentle[k].$1, style: const TextStyle(fontSize: _Fs.big)),
              title: Text(_gentle[k].$2),
              onTap: () => Navigator.pop(ctx, k),
            ),
        ]),
      ),
    ),
  );
  if (i == null) return;
  final g = _gentle[i];
  try {
    await _db.from('messages').insert({'chat_id': chatId, 'kind': 'card', 'body': g.$3, 'duration_ms': g.$4});
  } catch (_) {
    try {
      await _sendText(chatId, g.$3); // السيرفر قديم: نرسلها نص
    } catch (_) {
      if (context.mounted) _toast(context, 'تعذر الإرسال.');
    }
  }
}

// ===== خلفية متحركة للمحادثة =====

const _particleSets = [
  <String>[],
  ['❤️', '💕', '💗'],
  ['⭐', '✨', '🌟'],
  ['❄️', '❅', '❆'],
  ['🫧', '○', '◦'],
  ['🌸', '🌷', '🌼'],
];
const _particleNames = ['بدون', 'قلوب', 'نجوم', 'ثلج', 'فقاعات', 'ورود'];

class _FloatingParticles extends StatefulWidget {
  const _FloatingParticles({required this.kind});
  final int kind;

  @override
  State<_FloatingParticles> createState() => _FloatingParticlesState();
}

class _FloatingParticlesState extends State<_FloatingParticles>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 30))..repeat();
  final _seeds = List.generate(14, (i) => Random(i * 7919));
  late final _p = [
    for (final r in _seeds)
      (x: r.nextDouble(), off: r.nextDouble(), speed: 0.6 + r.nextDouble() * 0.8,
          size: 14 + r.nextDouble() * 16, sway: 10 + r.nextDouble() * 24, pick: r.nextInt(3)),
  ];

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final set = _particleSets[widget.kind % _particleSets.length];
    if (set.isEmpty) return const SizedBox.shrink();
    final down = widget.kind == 3; // الثلج ينزل، الباقي يطلع
    return IgnorePointer(
      child: RepaintBoundary(
        child: LayoutBuilder(
          builder: (_, box) => AnimatedBuilder(
            animation: _c,
            builder: (_, __) => Stack(children: [
              for (final p in _p)
                Builder(builder: (_) {
                  final t = (_c.value * p.speed + p.off) % 1.0;
                  final y = down ? t * (box.maxHeight + 40) - 40 : (1 - t) * (box.maxHeight + 40) - 20;
                  final x = p.x * box.maxWidth + math.sin(t * 2 * math.pi * 2) * p.sway;
                  return Positioned(
                    left: x,
                    top: y,
                    child: Opacity(
                      opacity: 0.30,
                      child: Text(set[p.pick % set.length],
                          style: TextStyle(fontSize: p.size, color: Colors.white)),
                    ),
                  );
                }),
            ]),
          ),
        ),
      ),
    );
  }
}

// ===== ملخص الشهر / السنة (ينحفظ كصورة) =====

const _stopWords = {
  'و', 'في', 'من', 'على', 'الى', 'إلى', 'عن', 'مع', 'انا', 'أنا', 'انت', 'أنت', 'هو', 'هي',
  'شي', 'شو', 'شنو', 'ما', 'لا', 'يا', 'اذا', 'إذا', 'بس', 'كان', 'هذا', 'هذي', 'ذا', 'اللي',
  'عشان', 'لو', 'او', 'أو', 'ثم', 'قد', 'كل', 'بعد', 'قبل', 'الحين', 'هسه', 'زين', 'اي', 'إي',
};

class SummaryScreen extends StatefulWidget {
  const SummaryScreen({super.key, required this.chatId});
  final String chatId;

  @override
  State<SummaryScreen> createState() => _SummaryState();
}

class _SummaryState extends State<SummaryScreen> {
  final _key = GlobalKey();
  bool _year = false;
  Future<Map<String, Object?>>? _f;

  @override
  void initState() {
    super.initState();
    _f = _load();
  }

  (DateTime, DateTime) get _range {
    final now = DateTime.now();
    return _year
        ? (DateTime(now.year), DateTime(now.year + 1))
        : (DateTime(now.year, now.month), DateTime(now.year, now.month + 1));
  }

  Future<int> _count(String? kind, {bool? mine}) async {
    final (a, b) = _range;
    var q = _db
        .from('messages')
        .select('id')
        .eq('chat_id', widget.chatId)
        .gte('created_at', a.toUtc().toIso8601String())
        .lt('created_at', b.toUtc().toIso8601String());
    if (kind != null) q = q.eq('kind', kind);
    if (mine == true) q = q.eq('sender_id', _meId);
    final r = await q.count(CountOption.exact);
    return r.count;
  }

  Future<Map<String, Object?>> _load() async {
    final (a, b) = _range;
    final res = await Future.wait([
      _count(null),
      _count('image'),
      _count('audio'),
      _count('call'),
      _count('think'),
      _count(null, mine: true),
    ]);
    final texts = await _db
        .from('messages')
        .select('body')
        .eq('chat_id', widget.chatId)
        .eq('kind', 'text')
        .gte('created_at', a.toUtc().toIso8601String())
        .lt('created_at', b.toUtc().toIso8601String())
        .order('id', ascending: false)
        .limit(1500);
    final freq = <String, int>{};
    for (final t in texts) {
      for (final w in '${t['body'] ?? ''}'.split(RegExp(r'[\s\p{P}]+', unicode: true))) {
        final k = w.trim();
        if (k.length < 2 || _stopWords.contains(k) || RegExp(r'^\d+$').hasMatch(k)) continue;
        freq[k] = (freq[k] ?? 0) + 1;
      }
    }
    final top = freq.entries.toList()..sort((x, y) => y.value.compareTo(x.value));
    return {
      'total': res[0],
      'photos': res[1],
      'voice': res[2],
      'calls': res[3],
      'hearts': res[4],
      'mine': res[5],
      'words': top.take(3).map((e) => e.key).toList(),
    };
  }

  Future<void> _export({required bool share}) async {
    try {
      final box = _key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final img = await box.toImage(pixelRatio: 3);
      final data = await img.toByteData(format: ImageByteFormat.png);
      img.dispose();
      final dir = await getTemporaryDirectory();
      final f = File('${dir.path}/summary_${DateTime.now().millisecondsSinceEpoch}.png');
      await f.writeAsBytes(data!.buffer.asUint8List());
      if (share) {
        await SharePlus.instance.share(ShareParams(files: [XFile(f.path)]));
      } else {
        await Gal.putImage(f.path, album: appName);
        if (mounted) _toast(context, 'انحفظت بالمعرض');
      }
    } catch (_) {
      if (mounted) _toast(context, 'تعذر الحفظ.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final (a, _) = _range;
    final title = _year ? 'سنتكم ${a.year} بيناتنا' : 'شهركم: ${_months[a.month - 1]} ${a.year}';
    return Scaffold(
      appBar: AppBar(title: const Text('ملخصنا'), backgroundColor: Colors.transparent),
      extendBodyBehindAppBar: true,
      body: Backdrop(
        child: SafeArea(
          child: ListView(padding: const EdgeInsets.all(_Sp.lg), children: [
            Center(
              child: SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('هالشهر')),
                  ButtonSegment(value: true, label: Text('هالسنة')),
                ],
                selected: {_year},
                onSelectionChanged: (s) => setState(() {
                  _year = s.first;
                  _f = _load();
                }),
              ),
            ),
            const SizedBox(height: _Sp.lg),
            FutureBuilder<Map<String, Object?>>(
              future: _f,
              builder: (_, snap) {
                if (snap.hasError) {
                  return const Center(child: Text('تعذر التحميل، تأكد من الإنترنت.'));
                }
                final d = snap.data;
                if (d == null) {
                  return const Padding(
                      padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()));
                }
                final total = d['total'] as int;
                final mine = d['mine'] as int;
                final words = d['words'] as List;
                Widget stat(String e, Object v, String l) => Column(children: [
                      Text(e, style: const TextStyle(fontSize: _Fs.big)),
                      Text('$v', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white)),
                      Text(l, style: const TextStyle(fontSize: _Fs.caption, color: Color(0xDDFFFFFF))),
                    ]);
                return Column(children: [
                  RepaintBoundary(
                    key: _key,
                    child: Container(
                      padding: const EdgeInsets.all(22),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(28),
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFFFF5FA2), Color(0xFF7B5CFA), Color(0xFF0A84FF)],
                        ),
                      ),
                      child: Column(children: [
                        const _Rings(),
                        const SizedBox(height: 10),
                        Text(title,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white)),
                        const SizedBox(height: 18),
                        Text('$total',
                            style: const TextStyle(fontSize: 54, fontWeight: FontWeight.w900, color: Colors.white)),
                        const Text('رسالة بيناتكم', style: TextStyle(color: Colors.white)),
                        if (total > 0)
                          Text('منك ${(mine * 100 / total).round()}% ومنه ${100 - (mine * 100 / total).round()}%',
                              style: const TextStyle(fontSize: _Fs.small, color: Color(0xDDFFFFFF))),
                        const SizedBox(height: 18),
                        Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                          stat('📷', d['photos']!, 'صورة'),
                          stat('🎙️', d['voice']!, 'صوتية'),
                          stat('📞', d['calls']!, 'مكالمة'),
                          stat('❤️', d['hearts']!, 'أفكر فيك'),
                        ]),
                        if (words.isNotEmpty) ...[
                          const SizedBox(height: 18),
                          const Text('أكثر كلمات قلتوها', style: TextStyle(fontSize: _Fs.small, color: Color(0xDDFFFFFF))),
                          const SizedBox(height: _Sp.xs),
                          Text(words.map((w) => '«$w»').join('  '),
                              style: const TextStyle(fontSize: _Fs.heading, fontWeight: FontWeight.w700, color: Colors.white)),
                        ],
                        const SizedBox(height: 14),
                        const Text(appName, style: TextStyle(fontSize: _Fs.small, color: Color(0xCCFFFFFF))),
                      ]),
                    ),
                  ),
                  const SizedBox(height: _Sp.lg),
                  Row(children: [
                    Expanded(child: _Btn(label: 'حفظ بالمعرض', onTap: () => _export(share: false))),
                    const SizedBox(width: 10),
                    Expanded(child: _Btn(label: 'مشاركة', onTap: () => _export(share: true))),
                  ]),
                ]);
              },
            ),
          ]),
        ),
      ),
    );
  }
}

// ===== بالمحادثة: المناسبة اليوم، ذكرى أول رسالة =====

extension _ChatSeason on _ChatState {
  Future<void> _loadAnniv() async {
    try {
      final r = await _db
          .from('messages')
          .select('created_at')
          .eq('chat_id', widget.chat.id)
          .order('id', ascending: true)
          .limit(1);
      if (r.isEmpty) return;
      final first = DateTime.tryParse('${r.first['created_at']}')?.toLocal();
      final now = DateTime.now();
      if (first == null || first.month != now.month || first.day != now.day) return;
      final years = now.year - first.year;
      if (years >= 1 && mounted) setState(() => _annivYears = years);
    } catch (_) {}
  }
}

extension _ChatPoll on _ChatState {
  Future<void> _sendPoll() async {
    final q = TextEditingController();
    final opts = List.generate(4, (_) => TextEditingController());
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تصويت سريع'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: q,
              autofocus: true,
              maxLength: 80,
              decoration: const InputDecoration(labelText: 'السؤال', hintText: 'مثل: وين نتعشى؟'),
            ),
            for (var i = 0; i < 4; i++)
              TextField(
                controller: opts[i],
                maxLength: 40,
                decoration: InputDecoration(
                    labelText: '${_pollKeys[i]} خيار ${i + 1}${i >= 2 ? ' (اختياري)' : ''}',
                    counterText: ''),
              ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('أرسل')),
        ],
      ),
    );
    final question = q.text.trim().replaceAll('\n', ' ');
    final list = [
      for (final o in opts)
        if (o.text.trim().isNotEmpty) o.text.trim().replaceAll('\n', ' '),
    ];
    q.dispose();
    for (final o in opts) {
      o.dispose();
    }
    if (ok != true) return;
    if (question.isEmpty || list.length < 2) {
      if (mounted) _toast(context, 'اكتب سؤال وخيارين على الأقل.');
      return;
    }
    final body = StringBuffer('📊 $question');
    for (var i = 0; i < list.length; i++) {
      body.write('\n${_pollKeys[i]} ${list[i]}');
    }
    try {
      await _sendText(widget.chat.id, body.toString());
    } catch (_) {
      if (mounted) _toast(context, 'تعذر الإرسال.');
    }
  }
}
