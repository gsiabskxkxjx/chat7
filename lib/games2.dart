part of 'main.dart';

// ---------- ألعاب جديدة: مين فينا، صح أو غلط، الذاكرة، 20 سؤال، خمّن من الإيموجي، ارسم وخمّن ----------
// كلها بجدول chat_games (نفس طريقة إكس أو): الحالة بعمود state.

String get _meId => _db.auth.currentUser?.id ?? '';

/// يقرأ الحالة الحالية من السيرفر، يعدّلها، ويحفظها (حتى ما نمسح حركة الطرف الثاني)
Future<bool> _gameMutate(
    BuildContext context, Object id, Map<String, dynamic>? Function(Map<String, dynamic> st) f,
    {String? Function(Map<String, dynamic> st)? winner}) async {
  try {
    final fresh = await _db.from('chat_games').select('state').eq('id', id).single();
    final st = f(Map<String, dynamic>.from(fresh['state'] as Map));
    if (st == null) return false;
    await _db.from('chat_games').update({
      'state': st,
      if (winner != null) 'winner': winner(st),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', id);
    return true;
  } catch (_) {
    if (context.mounted) _toast(context, 'تعذر تسجيل الحركة، جرّب مرة ثانية.');
    return false;
  }
}

Future<void> _gameNew(BuildContext context, String chatId, String kind,
    Map<String, dynamic> state) async {
  try {
    await _db.from('chat_games').insert(
        {'chat_id': chatId, 'kind': kind, 'turn': _meId, 'state': state});
  } catch (e) {
    if (context.mounted) {
      _toast(
          context,
          e.toString().contains('check')
              ? 'اللعبة تحتاج تحديث السيرفر (update_4).'
              : 'تعذر بدء اللعبة، جرّب مرة ثانية.');
    }
  }
}

/// شاشة لعبة عامة: تجيب آخر جولة من نوعها وتعرضها
class _GameFrame extends StatefulWidget {
  const _GameFrame({
    required this.title,
    required this.chatId,
    required this.kind,
    required this.start,
    required this.body,
    this.intro,
  });
  final String title;
  final String chatId;
  final String kind;
  final String? intro;
  final VoidCallback start;
  final Widget Function(Map<String, dynamic> row, Map<String, dynamic> st) body;

  @override
  State<_GameFrame> createState() => _GameFrameState();
}

class _GameFrameState extends State<_GameFrame> {
  late final Stream<List<Map<String, dynamic>>> _s = _db
      .from('chat_games')
      .stream(primaryKey: ['id'])
      .eq('chat_id', widget.chatId)
      .order('id', ascending: false)
      .limit(30);

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(widget.title),
          backgroundColor: Colors.transparent,
          actions: [
            IconButton(
                tooltip: 'جولة جديدة',
                onPressed: widget.start,
                icon: const Icon(Icons.restart_alt_rounded)),
          ],
        ),
        extendBodyBehindAppBar: true,
        body: Backdrop(
          child: SafeArea(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: _s,
              builder: (_, snap) {
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                Map<String, dynamic>? cur;
                for (final r in snap.data!) {
                  if (r['kind'] == widget.kind) {
                    cur = r;
                    break;
                  }
                }
                if (cur == null) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(28),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        if (widget.intro != null) ...[
                          Text(widget.intro!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 16, height: 1.6)),
                          const SizedBox(height: 20),
                        ],
                        _Btn(label: 'ابدأ', onTap: widget.start),
                      ]),
                    ),
                  );
                }
                return widget.body(cur, Map<String, dynamic>.from(cur['state'] as Map));
              },
            ),
          ),
        ),
      );
}

Widget _bigChoice(String label, VoidCallback? onTap, {Color? color}) => Expanded(
      child: _Press(
        onTap: onTap,
        child: Glass(
          radius: 22,
          shadow: false,
          tint: color,
          padding: const EdgeInsets.symmetric(vertical: 18),
          child: Text(label,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        ),
      ),
    );

// ======================= مين فينا؟ =======================

const _whoQs = [
  'مين أكثر واحد يغار؟', 'مين أكثر واحد ينسى؟', 'مين يتأخر بالرد؟', 'مين يزعل بسرعة؟',
  'مين يعتذر أول؟', 'مين أكثر واحد رومانسي؟', 'مين ياكل أكثر؟', 'مين ينام أول؟',
  'مين يضحك أكثر؟', 'مين أكثر واحد عنيد؟', 'مين يصرف أكثر؟', 'مين يحب السفر أكثر؟',
  'مين يشتاق أكثر؟', 'مين أكثر واحد يهتم بالتفاصيل؟', 'مين يطبخ أحسن؟', 'مين يتصل أول؟',
  'مين يحب الصور أكثر؟', 'مين أكثر واحد صبور؟', 'مين يخاف من الأفلام المرعبة؟', 'مين يبدأ الكلام الصبح؟',
  'مين أكثر واحد يحب المفاجآت؟', 'مين يكتب رسائل أطول؟', 'مين أكثر واحد يضيّع أغراضه؟', 'مين أشطر بالألعاب؟',
  'مين يقول «أحبك» أكثر؟', 'مين أكثر واحد يتدلع؟', 'مين ينسى المواعيد؟', 'مين يحب الحلويات أكثر؟',
];

class WhoOfUsScreen extends StatelessWidget {
  const WhoOfUsScreen({super.key, required this.chatId});
  final String chatId;

  void _start(BuildContext context) {
    final idx = List<int>.generate(_whoQs.length, (i) => i)..shuffle();
    unawaited(_gameNew(context, chatId, 'whoof',
        {'qs': idx.take(8).toList(), 'ans': <String, dynamic>{}, 'status': 'playing'}));
  }

  @override
  Widget build(BuildContext context) => _GameFrame(
        title: 'مين فينا؟',
        chatId: chatId,
        kind: 'whoof',
        intro: '8 أسئلة. كل واحد يجاوب لحاله: أنا ولا هو؟\nبالأخير نشوف كم مرة اتفقتوا.',
        start: () => _start(context),
        body: (row, st) {
          final qs = List<int>.from(st['qs'] as List);
          final ans = Map<String, dynamic>.from((st['ans'] ?? {}) as Map);
          final mine = List<String>.from((ans[_meId] ?? const []) as List);
          final otherId = ans.keys.firstWhere((k) => k != _meId, orElse: () => '');
          final theirs = List<String>.from((ans[otherId] ?? const []) as List);
          if (mine.length < qs.length) {
            final q = _whoQs[qs[mine.length] % _whoQs.length];
            Future<void> pick(String who) => _gameMutate(context, row['id'] as Object, (s) {
                  final a = Map<String, dynamic>.from((s['ans'] ?? {}) as Map);
                  final m = List<String>.from((a[_meId] ?? const []) as List);
                  if (m.length >= qs.length) return null;
                  a[_meId] = [...m, who];
                  return {...s, 'ans': a};
                });
            return Padding(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text('${mine.length + 1} / ${qs.length}',
                    style: const TextStyle(color: Color(0xB3FFFFFF))),
                const SizedBox(height: 14),
                Text(q,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
                const SizedBox(height: 30),
                Row(children: [
                  _bigChoice('🙋 أنا', () => pick('me'), color: const Color(0xFF0A84FF)),
                  const SizedBox(width: 14),
                  _bigChoice('👉 هو', () => pick('you'), color: const Color(0xFFFF5FA2)),
                ]),
              ]),
            );
          }
          if (theirs.length < qs.length) {
            return const Center(
                child: Text('خلّصت! ننتظره يخلّص ⏳', style: TextStyle(fontSize: 18)));
          }
          var agree = 0;
          final lines = <Widget>[];
          for (var i = 0; i < qs.length; i++) {
            final a = mine[i], b = theirs[i];
            final ok = a != b; // أنا قلت "أنا" وهو قال "هو" = اتفقنا
            if (ok) agree++;
            final who = a == 'me' ? 'أنت' : 'هو';
            final whoThem = b == 'me' ? 'هو' : 'أنت';
            lines.add(Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Glass(
                radius: 18,
                shadow: false,
                padding: const EdgeInsets.all(12),
                child: Row(children: [
                  Text(ok ? '✅' : '🤔', style: const TextStyle(fontSize: 20)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(_whoQs[qs[i] % _whoQs.length],
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      Text('أنت قلت: $who · هو قال: $whoThem',
                          style: const TextStyle(fontSize: 12, color: Color(0xB3FFFFFF))),
                    ]),
                  ),
                ]),
              ),
            ));
          }
          return ListView(padding: const EdgeInsets.all(16), children: [
            Text('اتفقتوا $agree من ${qs.length}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
            Text(agree >= qs.length - 1 ? 'تعرفون بعض زين 💞' : 'في أشياء تحتاج نقاش 😄',
                textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ...lines,
            const SizedBox(height: 8),
            _Btn(label: 'جولة جديدة', onTap: () => _start(context)),
          ]);
        },
      );
}

// ======================= صح أو غلط عني =======================

class TrueFalseScreen extends StatelessWidget {
  const TrueFalseScreen({super.key, required this.chatId});
  final String chatId;

  Future<void> _start(BuildContext context) async {
    final cs = List.generate(3, (_) => TextEditingController());
    final truth = [true, false, true];
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('3 جمل عنك'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('اكتب 3 جمل، وحدد الصح منها والغلط. هو لازم يخمّن.',
                  style: TextStyle(fontSize: 13, color: Color(0xB3FFFFFF))),
              for (var i = 0; i < 3; i++)
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: cs[i],
                      maxLength: 80,
                      decoration: InputDecoration(labelText: 'الجملة ${i + 1}'),
                    ),
                  ),
                  TextButton(
                    onPressed: () => set(() => truth[i] = !truth[i]),
                    child: Text(truth[i] ? 'صح ✅' : 'غلط ❌'),
                  ),
                ]),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('أرسل')),
          ],
        ),
      ),
    );
    final items = [
      for (var i = 0; i < 3; i++)
        if (cs[i].text.trim().isNotEmpty) {'t': cs[i].text.trim(), 'v': truth[i]},
    ];
    for (final c in cs) {
      c.dispose();
    }
    if (ok != true || items.isEmpty || !context.mounted) return;
    await _gameNew(context, chatId, 'truefalse',
        {'author': _meId, 'items': items, 'guesses': <bool>[], 'status': 'guessing'});
    unawaited(_sendText(chatId, '🤔 كتبت لك جمل عني، خمّن الصح من الغلط! (صح أو غلط)'));
  }

  @override
  Widget build(BuildContext context) => _GameFrame(
        title: 'صح أو غلط عني',
        chatId: chatId,
        kind: 'truefalse',
        intro: 'اكتب 3 جمل عن نفسك (بعضها صح وبعضها غلط)، وهو يخمّن.',
        start: () => unawaited(_start(context)),
        body: (row, st) {
          final items = List<Map>.from(st['items'] as List);
          final guesses = List<bool>.from((st['guesses'] ?? const []) as List);
          final iAmAuthor = st['author'] == _meId;
          final done = guesses.length >= items.length;
          if (!done && iAmAuthor) {
            return const Center(
                child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('أرسلت جملك. ننتظره يخمّن ⏳',
                  textAlign: TextAlign.center, style: TextStyle(fontSize: 18)),
            ));
          }
          if (!done) {
            final it = items[guesses.length];
            Future<void> guess(bool v) => _gameMutate(context, row['id'] as Object, (s) {
                  final g = List<bool>.from((s['guesses'] ?? const []) as List);
                  if (g.length >= items.length) return null;
                  final next = [...g, v];
                  return {
                    ...s,
                    'guesses': next,
                    'status': next.length >= items.length ? 'done' : 'guessing'
                  };
                });
            return Padding(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text('${guesses.length + 1} / ${items.length}',
                    style: const TextStyle(color: Color(0xB3FFFFFF))),
                const SizedBox(height: 14),
                Text('«${it['t']}»',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
                const SizedBox(height: 30),
                Row(children: [
                  _bigChoice('✅ صح', () => guess(true), color: const Color(0xFF34C759)),
                  const SizedBox(width: 14),
                  _bigChoice('❌ غلط', () => guess(false), color: const Color(0xFFFF453A)),
                ]),
              ]),
            );
          }
          var right = 0;
          for (var i = 0; i < items.length; i++) {
            if (guesses[i] == (items[i]['v'] == true)) right++;
          }
          return ListView(padding: const EdgeInsets.all(16), children: [
            Text(iAmAuthor ? 'خمّن $right من ${items.length} صح' : 'خمّنت $right من ${items.length} صح',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
            const SizedBox(height: 16),
            for (var i = 0; i < items.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Glass(
                  radius: 18,
                  shadow: false,
                  padding: const EdgeInsets.all(12),
                  child: Row(children: [
                    Text(guesses[i] == (items[i]['v'] == true) ? '🎯' : '😅',
                        style: const TextStyle(fontSize: 20)),
                    const SizedBox(width: 10),
                    Expanded(child: Text('${items[i]['t']}')),
                    Text(items[i]['v'] == true ? 'صح' : 'غلط',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                  ]),
                ),
              ),
            const SizedBox(height: 8),
            _Btn(label: 'دورك تكتب جمل', onTap: () => unawaited(_start(context))),
          ]);
        },
      );
}

// ======================= لعبة الذاكرة =======================

const _memoryEmojis = ['❤️', '🌹', '🍓', '⭐', '🎈', '🐱', '🌙', '☕', '🍩', '🎵', '🦋', '🌸'];

class MemoryGameScreen extends StatefulWidget {
  const MemoryGameScreen({super.key, required this.chatId});
  final String chatId;

  @override
  State<MemoryGameScreen> createState() => _MemoryState();
}

class _MemoryState extends State<MemoryGameScreen> {
  String? _other;
  Timer? _clear;

  @override
  void initState() {
    super.initState();
    unawaited(_loadOther());
  }

  @override
  void dispose() {
    _clear?.cancel();
    super.dispose();
  }

  Future<void> _loadOther() async {
    try {
      final r = await _db
          .from('chats')
          .select('user_a,user_b')
          .eq('id', widget.chatId)
          .single();
      final o = r['user_a'] == _meId ? r['user_b'] : r['user_a'];
      if (mounted) setState(() => _other = '$o');
    } catch (_) {}
  }

  void _start() {
    final e = [..._memoryEmojis]..shuffle();
    final cards = [...e.take(8), ...e.take(8)]..shuffle();
    unawaited(_gameNew(context, widget.chatId, 'memory', {
      'cards': cards,
      'matched': List<bool>.filled(16, false),
      'flips': <int>[],
      'turn': _meId,
      'scores': <String, int>{},
      'status': 'playing',
    }));
  }

  String? _winnerOf(Map<String, dynamic> s) {
    if (s['status'] != 'done') return null;
    final sc = Map<String, dynamic>.from((s['scores'] ?? {}) as Map);
    final me = (sc[_meId] as num?)?.toInt() ?? 0;
    final ot = _other == null ? 0 : ((sc[_other] as num?)?.toInt() ?? 0);
    if (me == ot) return null;
    return me > ot ? _meId : _other;
  }

  Future<void> _flip(Map<String, dynamic> row, int i) async {
    final other = _other;
    if (other == null) return;
    final ok = await _gameMutate(context, row['id'] as Object, (s) {
      if (s['status'] != 'playing' || s['turn'] != _meId) return null;
      final flips = List<int>.from((s['flips'] ?? const []) as List);
      final matched = List<bool>.from(s['matched'] as List);
      if (flips.length >= 2 || flips.contains(i) || matched[i]) return null;
      flips.add(i);
      final next = {...s, 'flips': flips};
      if (flips.length == 2) {
        final cards = List<String>.from(s['cards'] as List);
        if (cards[flips[0]] == cards[flips[1]]) {
          matched[flips[0]] = true;
          matched[flips[1]] = true;
          final sc = Map<String, dynamic>.from((s['scores'] ?? {}) as Map);
          sc[_meId] = ((sc[_meId] as num?)?.toInt() ?? 0) + 1;
          next['matched'] = matched;
          next['scores'] = sc;
          next['flips'] = <int>[];
          if (!matched.contains(false)) next['status'] = 'done';
        }
      }
      return next;
    }, winner: _winnerOf);
    if (!ok) return;
    // بطاقتين مختلفات: نخليهم ظاهرين لحظة، وبعدها الدور ينتقل
    _clear?.cancel();
    _clear = Timer(const Duration(milliseconds: 1300), () {
      unawaited(_gameMutate(context, row['id'] as Object, (s) {
        final flips = List<int>.from((s['flips'] ?? const []) as List);
        if (flips.length < 2 || s['turn'] != _meId) return null;
        return {...s, 'flips': <int>[], 'turn': other};
      }));
    });
  }

  /// لو الطرف الثاني طلع قبل ما تنقلب البطاقات: نقدر نكمّل
  Future<void> _unstick(Map<String, dynamic> row) => _gameMutate(context, row['id'] as Object, (s) {
        final flips = List<int>.from((s['flips'] ?? const []) as List);
        if (flips.length < 2) return null;
        return {...s, 'flips': <int>[], 'turn': _meId};
      });

  @override
  Widget build(BuildContext context) => _GameFrame(
        title: 'لعبة الذاكرة',
        chatId: widget.chatId,
        kind: 'memory',
        intro: 'اقلبوا البطاقات بالدور ولاقوا الأزواج. اللي يلاقي زوج يكمّل دوره.',
        start: _start,
        body: (row, st) {
          final cards = List<String>.from(st['cards'] as List);
          final matched = List<bool>.from(st['matched'] as List);
          final flips = List<int>.from((st['flips'] ?? const []) as List);
          final sc = Map<String, dynamic>.from((st['scores'] ?? {}) as Map);
          final myTurn = st['turn'] == _meId && st['status'] == 'playing';
          final me = (sc[_meId] as num?)?.toInt() ?? 0;
          final ot = _other == null ? 0 : ((sc[_other] as num?)?.toInt() ?? 0);
          final updated = DateTime.tryParse('${row['updated_at']}');
          final stuck = !myTurn &&
              flips.length == 2 &&
              updated != null &&
              DateTime.now().toUtc().difference(updated.toUtc()) > const Duration(seconds: 5);
          final done = st['status'] == 'done';
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              Text(
                  done
                      ? (me == ot ? 'تعادل! $me - $ot' : (me > ot ? 'فزت! $me - $ot 🎉' : 'فاز هو $ot - $me'))
                      : (myTurn ? 'دورك · أنت $me · هو $ot' : 'دوره · أنت $me · هو $ot'),
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              Expanded(
                child: GridView.count(
                  crossAxisCount: 4,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  children: [
                    for (var i = 0; i < cards.length; i++)
                      _Press(
                        onTap: myTurn && !matched[i] && !flips.contains(i) && flips.length < 2
                            ? () => _flip(row, i)
                            : null,
                        dimWhenOff: false,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            color: matched[i]
                                ? const Color(0x3334C759)
                                : flips.contains(i)
                                    ? const Color(0x55FFFFFF)
                                    : const Color(0x22FFFFFF),
                            border: Border.all(color: const Color(0x44FFFFFF)),
                          ),
                          child: Text(
                              matched[i] || flips.contains(i) ? cards[i] : '❔',
                              style: const TextStyle(fontSize: 30)),
                        ),
                      ),
                  ],
                ),
              ),
              if (stuck) TextButton(onPressed: () => _unstick(row), child: const Text('كمّل اللعب')),
              if (done) _Btn(label: 'جولة جديدة', onTap: _start),
            ]),
          );
        },
      );
}

// ======================= 20 سؤال =======================

String _norm(String s) {
  var t = s.trim().toLowerCase();
  t = t.replaceAll(RegExp('[ً-ْـ]'), ''); // التشكيل والتطويل
  t = t
      .replaceAll(RegExp('[أإآٱ]'), 'ا')
      .replaceAll('ة', 'ه')
      .replaceAll('ى', 'ي')
      .replaceAll('ؤ', 'و')
      .replaceAll('ئ', 'ي');
  t = t.replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ').trim();
  t = t.split(' ').map((w) => w.startsWith('ال') && w.length > 3 ? w.substring(2) : w).join(' ');
  return t;
}

bool _sameAnswer(String guess, List<String> answers) {
  final g = _norm(guess);
  if (g.isEmpty) return false;
  for (final a in answers) {
    final n = _norm(a);
    if (n.isEmpty) continue;
    if (g == n || g.contains(n) || (n.contains(g) && g.length >= 4)) return true;
  }
  return false;
}

class TwentyQScreen extends StatelessWidget {
  const TwentyQScreen({super.key, required this.chatId});
  final String chatId;

  Future<void> _start(BuildContext context) async {
    final c = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('فكّر بشي'),
        content: TextField(
          controller: c,
          autofocus: true,
          maxLength: 40,
          decoration: const InputDecoration(
              labelText: 'الشي اللي يخمّنه (سري)',
              hintText: 'مثل: قطة، باريس، قهوة'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('ابدأ')),
        ],
      ),
    );
    final secret = c.text.trim();
    c.dispose();
    if (ok != true || secret.isEmpty || !context.mounted) return;
    await _gameNew(context, chatId, 'guess20',
        {'thinker': _meId, 'secret': secret, 'qa': <Map>[], 'status': 'playing'});
    unawaited(_sendText(chatId, '🧠 فكّرت بشي، عندك 20 سؤال تخمّنه! (20 سؤال)'));
  }

  @override
  Widget build(BuildContext context) => _GameFrame(
        title: '20 سؤال',
        chatId: chatId,
        kind: 'guess20',
        intro: 'واحد يفكر بشي، والثاني يسأل أسئلة جوابها «إي» أو «لا» لين يخمّنه. عندك 20 سؤال.',
        start: () => unawaited(_start(context)),
        body: (row, st) => _TwentyQBody(row: row, st: st, restart: () => unawaited(_start(context))),
      );
}

class _TwentyQBody extends StatefulWidget {
  const _TwentyQBody({required this.row, required this.st, required this.restart});
  final Map<String, dynamic> row;
  final Map<String, dynamic> st;
  final VoidCallback restart;

  @override
  State<_TwentyQBody> createState() => _TwentyQBodyState();
}

class _TwentyQBodyState extends State<_TwentyQBody> {
  final _c = TextEditingController();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _ask({required bool isGuess}) async {
    final t = _c.text.trim();
    if (t.isEmpty) return;
    _c.clear();
    final secret = '${widget.st['secret']}';
    await _gameMutate(context, widget.row['id'] as Object, (s) {
      final qa = List<Map>.from((s['qa'] ?? const []) as List);
      if (s['status'] != 'playing' || qa.isNotEmpty && qa.last['a'] == null) return null;
      if (isGuess) {
        final right = _sameAnswer(t, [secret]);
        qa.add({'q': t, 'guess': true, 'a': right ? 'right' : 'wrong'});
        return {
          ...s,
          'qa': qa,
          'status': right ? 'guessed' : (qa.length >= 20 ? 'lost' : 'playing'),
        };
      }
      qa.add({'q': t});
      return {...s, 'qa': qa};
    }, winner: (s) {
      if (s['status'] == 'guessed') return _meId;
      if (s['status'] == 'lost') return '${s['thinker']}';
      return null;
    });
  }

  Future<void> _answer(String a) => _gameMutate(context, widget.row['id'] as Object, (s) {
        final qa = List<Map>.from((s['qa'] ?? const []) as List);
        if (qa.isEmpty || qa.last['a'] != null) return null;
        qa[qa.length - 1] = {...qa.last, 'a': a};
        return {...s, 'qa': qa, 'status': qa.length >= 20 ? 'lost' : 'playing'};
      }, winner: (s) => s['status'] == 'lost' ? _meId : null);

  String _label(String? a) => switch (a) {
        'yes' => 'إي ✅',
        'no' => 'لا ❌',
        'maybe' => 'يمكن 🤷',
        'right' => 'صح! 🎉',
        'wrong' => 'غلط',
        _ => '...',
      };

  @override
  Widget build(BuildContext context) {
    final st = widget.st;
    final qa = List<Map>.from((st['qa'] ?? const []) as List);
    final thinker = st['thinker'] == _meId;
    final status = '${st['status']}';
    final waitingAnswer = qa.isNotEmpty && qa.last['a'] == null;
    final over = status != 'playing';
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(14),
        child: Glass(
          radius: 20,
          padding: const EdgeInsets.all(14),
          child: Column(children: [
            Text(
                over
                    ? (status == 'guessed'
                        ? (thinker ? 'خمّنها! 🎉' : 'خمّنتها! 🎉')
                        : (thinker ? 'ما خمّنها، فزت 😎' : 'خلصت الأسئلة 😅'))
                    : (thinker ? 'أنت المفكّر' : 'سؤال ${qa.length + (waitingAnswer ? 0 : 1)} من 20'),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            if (thinker || over)
              Text('الجواب: ${st['secret']}', style: const TextStyle(color: Color(0xCCFFFFFF))),
          ]),
        ),
      ),
      Expanded(
        child: ListView(padding: const EdgeInsets.symmetric(horizontal: 14), children: [
          for (var i = 0; i < qa.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(children: [
                Text('${i + 1}. ', style: const TextStyle(color: Color(0x99FFFFFF))),
                Expanded(
                    child: Text('${qa[i]['guess'] == true ? '🎯 ' : ''}${qa[i]['q']}')),
                Text(_label(qa[i]['a'] as String?),
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ]),
            ),
        ]),
      ),
      if (over)
        Padding(
          padding: const EdgeInsets.all(14),
          child: _Btn(label: 'دورك تفكر بشي', onTap: widget.restart),
        )
      else if (thinker && waitingAnswer)
        Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            _bigChoice('إي', () => _answer('yes'), color: const Color(0xFF34C759)),
            const SizedBox(width: 8),
            _bigChoice('يمكن', () => _answer('maybe')),
            const SizedBox(width: 8),
            _bigChoice('لا', () => _answer('no'), color: const Color(0xFFFF453A)),
          ]),
        )
      else if (thinker)
        const Padding(
          padding: EdgeInsets.all(20),
          child: Text('ننتظر سؤاله ⏳'),
        )
      else if (waitingAnswer)
        const Padding(
          padding: EdgeInsets.all(20),
          child: Text('ننتظر جوابه ⏳'),
        )
      else
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: Glass(
            radius: 24,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _c,
                  maxLength: 80,
                  decoration: const InputDecoration(
                      hintText: 'اسأل سؤال جوابه إي أو لا', border: InputBorder.none, counterText: ''),
                  onSubmitted: (_) => _ask(isGuess: false),
                ),
              ),
              TextButton(onPressed: () => _ask(isGuess: false), child: const Text('اسأل')),
              TextButton(onPressed: () => _ask(isGuess: true), child: const Text('خمّن')),
            ]),
          ),
        ),
    ]);
  }
}

// ======================= خمّن من الإيموجي =======================

const _emojiPuzzles = [
  ('🦁👑', 'فيلم كرتون', ['الأسد الملك', 'lion king']),
  ('🕷️🧑', 'فيلم', ['سبايدرمان', 'الرجل العنكبوت', 'spiderman', 'spider man']),
  ('❄️👸', 'فيلم كرتون', ['ملكة الثلج', 'frozen', 'فروزن']),
  ('🚢🧊💔', 'فيلم', ['تايتانك', 'titanic']),
  ('🦇🧑', 'فيلم', ['باتمان', 'الرجل الوطواط', 'batman']),
  ('🐠🔍', 'فيلم كرتون', ['البحث عن نيمو', 'نيمو', 'nemo']),
  ('🧸🤠🚀', 'فيلم كرتون', ['حكاية لعبة', 'toy story']),
  ('🍫🏭', 'فيلم', ['مصنع الشوكولاتة', 'تشارلي', 'charlie']),
  ('🏴‍☠️🌊⚓', 'فيلم', ['قراصنة الكاريبي', 'pirates']),
  ('🦖🏞️', 'فيلم', ['الحديقة الجوراسية', 'جوراسيك', 'jurassic']),
  ('🧞‍♂️🪔', 'فيلم كرتون', ['علاء الدين', 'aladdin']),
  ('🐭👨‍🍳', 'فيلم كرتون', ['راتاتوي', 'ratatouille']),
  ('🌌⚔️', 'فيلم', ['حرب النجوم', 'star wars']),
  ('🏠🎈', 'فيلم كرتون', ['فوق', 'up']),
  ('🐼🥋', 'فيلم كرتون', ['كونغ فو باندا', 'كونج فو باندا', 'kung fu panda']),
  ('🧊🦣', 'فيلم كرتون', ['العصر الجليدي', 'ice age']),
  ('🚗⚡', 'فيلم كرتون', ['سيارات', 'cars', 'ماكوين']),
  ('👸🍎💤', 'قصة', ['بياض الثلج', 'سنو وايت', 'snow white']),
  ('👠🎃🕛', 'قصة', ['سندريلا', 'cinderella']),
  ('🧜‍♀️🐚', 'فيلم كرتون', ['حورية البحر', 'الحورية الصغيرة', 'little mermaid']),
  ('🐻🍯', 'كرتون', ['ويني الدبدوب', 'ويني', 'winnie']),
  ('🐱🐭', 'كرتون', ['توم وجيري', 'tom and jerry']),
  ('🧽🍍', 'كرتون', ['سبونج بوب', 'سبونجبوب', 'spongebob']),
  ('💛🍌👓', 'كرتون', ['المينيونز', 'مينيونز', 'minions']),
  ('🤖🚗', 'فيلم', ['المتحولون', 'ترانسفورمرز', 'transformers']),
  ('🗼🥐', 'مدينة', ['باريس', 'paris']),
  ('🗽🍎', 'مدينة', ['نيويورك', 'new york']),
  ('🏙️🏜️☀️', 'مدينة', ['دبي', 'dubai']),
  ('🍣🗻', 'دولة', ['اليابان', 'japan']),
  ('🍕🛵', 'أكلة', ['بيتزا', 'pizza']),
  ('☕🥛🍫', 'مشروب', ['موكا', 'كابتشينو', 'mocha']),
  ('🐦✋🌳', 'مثل', ['عصفور باليد', 'عصفور في اليد']),
  ('🤐🥇', 'مثل', ['السكوت من ذهب', 'سكوت من ذهب']),
  ('⏰⚔️', 'مثل', ['الوقت كالسيف', 'الوقت سيف']),
  ('🔑😌', 'مثل', ['الصبر مفتاح الفرج', 'صبر مفتاح']),
  ('⚽🏆🌍', 'بطولة', ['كاس العالم', 'كأس العالم', 'المونديال', 'world cup']),
];

class EmojiGuessScreen extends StatelessWidget {
  const EmojiGuessScreen({super.key, required this.chatId});
  final String chatId;

  void _start(BuildContext context) {
    final idx = List<int>.generate(_emojiPuzzles.length, (i) => i)..shuffle();
    unawaited(_gameNew(context, chatId, 'emoji',
        {'ps': idx.take(5).toList(), 'ans': <String, dynamic>{}, 'status': 'playing'}));
  }

  @override
  Widget build(BuildContext context) => _GameFrame(
        title: 'خمّن من الإيموجي',
        chatId: chatId,
        kind: 'emoji',
        intro: '5 ألغاز بالإيموجي (أفلام، أماكن، أمثال). كل واحد يجاوب لحاله، واللي يجيب أكثر يفوز.',
        start: () => _start(context),
        body: (row, st) => _EmojiBody(row: row, st: st, restart: () => _start(context)),
      );
}

class _EmojiBody extends StatefulWidget {
  const _EmojiBody({required this.row, required this.st, required this.restart});
  final Map<String, dynamic> row;
  final Map<String, dynamic> st;
  final VoidCallback restart;

  @override
  State<_EmojiBody> createState() => _EmojiBodyState();
}

class _EmojiBodyState extends State<_EmojiBody> {
  final _c = TextEditingController();
  bool _hint = false;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  int _score(List<int> ps, List<String> a) {
    var n = 0;
    for (var i = 0; i < a.length && i < ps.length; i++) {
      if (_sameAnswer(a[i], _emojiPuzzles[ps[i] % _emojiPuzzles.length].$3)) n++;
    }
    return n;
  }

  Future<void> _submit(List<int> ps, {bool skip = false}) async {
    final t = skip ? '' : _c.text.trim();
    if (!skip && t.isEmpty) return;
    _c.clear();
    setState(() => _hint = false);
    await _gameMutate(context, widget.row['id'] as Object, (s) {
      final a = Map<String, dynamic>.from((s['ans'] ?? {}) as Map);
      final m = List<String>.from((a[_meId] ?? const []) as List);
      if (m.length >= ps.length) return null;
      a[_meId] = [...m, t];
      final allDone = a.length >= 2 &&
          a.values.every((v) => (v as List).length >= ps.length);
      return {...s, 'ans': a, 'status': allDone ? 'done' : 'playing'};
    }, winner: (s) {
      if (s['status'] != 'done') return null;
      final a = Map<String, dynamic>.from(s['ans'] as Map);
      String? best;
      var top = -1;
      var tie = false;
      a.forEach((k, v) {
        final sc = _score(ps, List<String>.from(v as List));
        if (sc > top) {
          top = sc;
          best = k;
          tie = false;
        } else if (sc == top) {
          tie = true;
        }
      });
      return tie ? null : best;
    });
  }

  @override
  Widget build(BuildContext context) {
    final st = widget.st;
    final ps = List<int>.from(st['ps'] as List);
    final ans = Map<String, dynamic>.from((st['ans'] ?? {}) as Map);
    final mine = List<String>.from((ans[_meId] ?? const []) as List);
    final otherId = ans.keys.firstWhere((k) => k != _meId, orElse: () => '');
    final theirs = List<String>.from((ans[otherId] ?? const []) as List);
    if (mine.length < ps.length) {
      final p = _emojiPuzzles[ps[mine.length] % _emojiPuzzles.length];
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text('${mine.length + 1} / ${ps.length}', style: const TextStyle(color: Color(0xB3FFFFFF))),
          const SizedBox(height: 10),
          Text(p.$1, style: const TextStyle(fontSize: 64)),
          const SizedBox(height: 6),
          if (_hint)
            Text('تلميح: ${p.$2}', style: const TextStyle(color: Color(0xCCFFFFFF)))
          else
            TextButton(onPressed: () => setState(() => _hint = true), child: const Text('تلميح')),
          const SizedBox(height: 14),
          Glass(
            radius: 24,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
            child: TextField(
              controller: _c,
              textAlign: TextAlign.center,
              decoration: const InputDecoration(hintText: 'جوابك', border: InputBorder.none),
              onSubmitted: (_) => _submit(ps),
            ),
          ),
          const SizedBox(height: 14),
          Row(children: [
            _bigChoice('تخطّي', () => _submit(ps, skip: true)),
            const SizedBox(width: 12),
            _bigChoice('جاوب', () => _submit(ps), color: const Color(0xFF0A84FF)),
          ]),
        ]),
      );
    }
    final myScore = _score(ps, mine);
    if (theirs.length < ps.length) {
      return Center(
          child: Text('جبت $myScore من ${ps.length}. ننتظره يخلّص ⏳',
              style: const TextStyle(fontSize: 18)));
    }
    final theirScore = _score(ps, theirs);
    return ListView(padding: const EdgeInsets.all(16), children: [
      Text(
          myScore == theirScore
              ? 'تعادل $myScore - $theirScore'
              : (myScore > theirScore ? 'فزت $myScore - $theirScore 🎉' : 'فاز هو $theirScore - $myScore'),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
      const SizedBox(height: 14),
      for (var i = 0; i < ps.length; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Glass(
            radius: 18,
            shadow: false,
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              Text(_emojiPuzzles[ps[i] % _emojiPuzzles.length].$1, style: const TextStyle(fontSize: 26)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_emojiPuzzles[ps[i] % _emojiPuzzles.length].$3.first,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text(
                      'أنت: ${mine[i].isEmpty ? '—' : mine[i]} · هو: ${theirs[i].isEmpty ? '—' : theirs[i]}',
                      style: const TextStyle(fontSize: 12, color: Color(0xB3FFFFFF))),
                ]),
              ),
            ]),
          ),
        ),
      _Btn(label: 'جولة جديدة', onTap: widget.restart),
    ]);
  }
}

// ======================= ارسم وخمّن =======================

const _drawWords = [
  'قطة', 'بيت', 'شمس', 'سيارة', 'وردة', 'قلب', 'شجرة', 'سمكة', 'طيارة', 'قمر',
  'نظارة', 'كيك', 'بحر', 'جبل', 'مظلة', 'ساعة', 'كوب قهوة', 'بيتزا', 'دراجة', 'نجمة',
  'كتاب', 'فراشة', 'مفتاح', 'تلفون', 'قارب', 'آيس كريم', 'بالون', 'شمعة', 'هدية', 'تاج',
];

Future<void> _drawAndGuess(BuildContext context, String chatId) async {
  final w = _drawWords[Random().nextInt(_drawWords.length)];
  await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => DrawScreen(chatId: chatId, prompt: w)));
}

// ======================= نتائجنا وشاراتنا =======================

const _gameNames = {
  'tictactoe': 'إكس أو',
  'rps': 'حجر ورقة مقص',
  'quiz': 'كم تعرفني',
  'memory': 'الذاكرة',
  'guess20': '20 سؤال',
  'emoji': 'خمّن من الإيموجي',
  'checkers': 'داما',
  'chess': 'شطرنج',
};

class ScoresScreen extends StatelessWidget {
  const ScoresScreen({super.key, required this.chatId});
  final String chatId;

  Future<({Map<String, (int, int)> wins, int games, Map<String, dynamic>? stats, int streak})>
      _load() async {
    final rows = await _db
        .from('chat_games')
        .select('kind,winner')
        .eq('chat_id', chatId)
        .limit(1000);
    final wins = <String, (int, int)>{};
    for (final r in rows) {
      final k = '${r['kind']}';
      final w = r['winner'];
      if (w == null || !_gameNames.containsKey(k)) continue;
      final cur = wins[k] ?? (0, 0);
      wins[k] = w == _meId ? (cur.$1 + 1, cur.$2) : (cur.$1, cur.$2 + 1);
    }
    Map<String, dynamic>? stats;
    try {
      final s = await _db.rpc('chat_stats', params: {'p_chat': chatId});
      if (s is Map) stats = Map<String, dynamic>.from(s);
    } catch (_) {}
    var streak = 0;
    try {
      final s = await _db.rpc('chat_streak', params: {'p_chat': chatId, 'p_tz': 'Asia/Baghdad'});
      streak = (s as num?)?.toInt() ?? 0;
    } catch (_) {}
    return (wins: wins, games: rows.length, stats: stats, streak: streak);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
            title: const Text('نتائجنا وشاراتنا'), backgroundColor: Colors.transparent),
        extendBodyBehindAppBar: true,
        body: Backdrop(
          child: SafeArea(
            child: FutureBuilder(
              future: _load(),
              builder: (_, snap) {
                if (snap.hasError) {
                  return const Center(child: Text('تعذر التحميل، تأكد من الإنترنت.'));
                }
                final d = snap.data;
                if (d == null) return const Center(child: CircularProgressIndicator());
                var myTotal = 0, theirTotal = 0;
                d.wins.forEach((_, v) {
                  myTotal += v.$1;
                  theirTotal += v.$2;
                });
                int n(String k) => (d.stats?[k] as num?)?.toInt() ?? 0;
                final badges = <(String, String, bool)>[
                  ('💬', 'أول رسالة', n('total') >= 1),
                  ('💯', '100 رسالة', n('total') >= 100),
                  ('🏅', '1000 رسالة', n('total') >= 1000),
                  ('👑', '10000 رسالة', n('total') >= 10000),
                  ('📞', 'أول مكالمة', n('calls') >= 1),
                  ('☎️', '50 مكالمة', n('calls') >= 50),
                  ('📷', 'أول صورة', n('photos') >= 1),
                  ('🖼️', '100 صورة', n('photos') >= 100),
                  ('🎙️', 'أول رسالة صوتية', n('voice') >= 1),
                  ('❤️', '10 «أفكر فيك»', n('hearts') >= 10),
                  ('🎮', 'أول لعبة', d.games >= 1),
                  ('🕹️', '20 لعبة', d.games >= 20),
                  ('🗓️', '7 أيام كلام', n('days') >= 7),
                  ('🌙', '30 يوم كلام', n('days') >= 30),
                  ('💎', '100 يوم كلام', n('days') >= 100),
                  ('🔥', 'سلسلة 7 أيام', d.streak >= 7),
                  ('☄️', 'سلسلة 30 يوم', d.streak >= 30),
                ];
                final got = badges.where((b) => b.$3).length;
                return ListView(padding: const EdgeInsets.all(16), children: [
                  Glass(
                    radius: 24,
                    padding: const EdgeInsets.all(16),
                    child: Column(children: [
                      const Text('النقاط', style: TextStyle(color: Color(0xB3FFFFFF))),
                      const SizedBox(height: 6),
                      Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                        Column(children: [
                          Text('${myTotal * 10}',
                              style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
                          const Text('أنت'),
                        ]),
                        const Text('⚔️', style: TextStyle(fontSize: 26)),
                        Column(children: [
                          Text('${theirTotal * 10}',
                              style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
                          const Text('هو'),
                        ]),
                      ]),
                    ]),
                  ),
                  const SizedBox(height: 14),
                  if (d.wins.isNotEmpty)
                    Glass(
                      radius: 24,
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Column(children: [
                        for (final e in d.wins.entries)
                          ListTile(
                            title: Text(_gameNames[e.key] ?? e.key),
                            trailing: Text('${e.value.$1} - ${e.value.$2}',
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                          ),
                      ]),
                    ),
                  const SizedBox(height: 18),
                  Text('الشارات ($got من ${badges.length})',
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 10),
                  GridView.count(
                    crossAxisCount: 3,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 0.95,
                    children: [
                      for (final b in badges)
                        Opacity(
                          opacity: b.$3 ? 1 : 0.35,
                          child: Glass(
                            radius: 20,
                            shadow: false,
                            padding: const EdgeInsets.all(8),
                            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                              Text(b.$3 ? b.$1 : '🔒', style: const TextStyle(fontSize: 30)),
                              const SizedBox(height: 6),
                              Text(b.$2,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(fontSize: 12)),
                            ]),
                          ),
                        ),
                    ],
                  ),
                ]);
              },
            ),
          ),
        ),
      );
}
