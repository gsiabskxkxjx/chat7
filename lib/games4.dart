part of 'main.dart';

// ---------- ألعاب الجولة الثانية (1): أربعة بالصف، حرب السفن، كلمة اليوم، من قال، صراحة وجرأة ----------
// كلها بجدول chat_games: الحالة بعمود state، واللاعبين بـ state.players = [أنا, الطرف الثاني]

/// خطوة لعبة: نقرأ الحالة من السيرفر، نعدّلها، ونحدّث الدور والفائز
Future<bool> _g4Step(BuildContext context, Object id, Map<String, dynamic>? Function(Map<String, dynamic> st) f) async {
  try {
    final fresh = await _net(_db.from('chat_games').select('state').eq('id', id).single());
    final st = f(Map<String, dynamic>.from(fresh['state'] as Map));
    if (st == null) return false;
    final players = (st['players'] as List?)?.map((e) => '$e').toList();
    String? turn;
    String? winner;
    if (players != null && players.length == 2) {
      final nxt = st['next'];
      if (st['status'] == 'playing' && nxt is int) turn = players[nxt];
      final by = st['by'];
      if (st['status'] == 'won' && by is int) winner = players[by];
    }
    await _net(_db.from('chat_games').update({
      'state': st,
      'turn': turn,
      'winner': winner,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', id));
    return true;
  } catch (e) {
    if (context.mounted) _toast(context, _friendlyError(e, fallback: 'تعذر تسجيل الحركة، جرّب مرة ثانية.'));
    return false;
  }
}

/// جولة جديدة بين الطرفين
Future<void> _g4New(BuildContext context, String chatId, String kind, Map<String, dynamic> state) async {
  final pid = await _R2.partnerId(chatId);
  if (pid == null) {
    if (context.mounted) _toast(context, 'تعذر تحديد الطرف الثاني.');
    return;
  }
  state['players'] = [_meId, pid];
  state['next'] = 0;
  state['status'] ??= 'playing';
  try {
    await _net(_db.from('chat_games').insert({'chat_id': chatId, 'kind': kind, 'turn': _meId, 'state': state}));
  } catch (e) {
    if (context.mounted) _toast(context, _friendlyError(e, fallback: 'تعذر بدء اللعبة، جرّب مرة ثانية.'));
  }
}

int _myIdx(Map<String, dynamic> st) => ((st['players'] as List?) ?? const []).map((e) => '$e').toList().indexOf(_meId);

String _turnMsg(Map<String, dynamic> st) {
  final status = st['status'];
  final me = _myIdx(st);
  if (status == 'won') return st['by'] == me ? 'فزت! 🎉' : 'الطرف الثاني فاز 👏';
  if (status == 'draw') return 'تعادل 🤝';
  return st['next'] == me ? 'دورك' : 'دور الطرف الثاني';
}

// ======================= أربعة بالصف =======================

const _c4Cols = 7, _c4Rows = 6;

List<int>? _c4Line(List<int> b, int p) {
  const dirs = [(1, 0), (0, 1), (1, 1), (1, -1)];
  for (var r = 0; r < _c4Rows; r++) {
    for (var c = 0; c < _c4Cols; c++) {
      for (final d in dirs) {
        final cells = <int>[];
        for (var k = 0; k < 4; k++) {
          final rr = r + d.$2 * k, cc = c + d.$1 * k;
          if (rr < 0 || rr >= _c4Rows || cc < 0 || cc >= _c4Cols) break;
          if (b[rr * _c4Cols + cc] != p) break;
          cells.add(rr * _c4Cols + cc);
        }
        if (cells.length == 4) return cells;
      }
    }
  }
  return null;
}

class Connect4Screen extends StatelessWidget {
  const Connect4Screen({super.key, required this.chatId});
  final String chatId;

  @override
  Widget build(BuildContext context) => _GameFrame(
        title: 'أربعة بالصف',
        chatId: chatId,
        kind: 'connect4',
        intro: 'اسقط قطعك بالأعمدة، وأول من يجمع أربع بالصف يفوز.',
        start: () => unawaited(_g4New(context, chatId, 'connect4', {'board': List<int>.filled(_c4Cols * _c4Rows, -1)})),
        body: (row, st) {
          final board = [for (final e in (st['board'] as List)) (e as num).toInt()];
          final me = _myIdx(st);
          final myTurn = st['status'] == 'playing' && st['next'] == me;
          final win = ((st['line'] as List?) ?? const []).map((e) => (e as num).toInt()).toSet();
          Future<void> drop(int col) => _g4Step(context, row['id'] as Object, (s) {
                final b = [for (final e in (s['board'] as List)) (e as num).toInt()];
                if (s['status'] != 'playing' || s['next'] != me) return null;
                var at = -1;
                for (var r = _c4Rows - 1; r >= 0; r--) {
                  if (b[r * _c4Cols + col] == -1) {
                    at = r * _c4Cols + col;
                    break;
                  }
                }
                if (at < 0) return null;
                b[at] = me;
                s['board'] = b;
                final line = _c4Line(b, me);
                if (line != null) {
                  s['status'] = 'won';
                  s['by'] = me;
                  s['line'] = line;
                } else if (!b.contains(-1)) {
                  s['status'] = 'draw';
                } else {
                  s['next'] = 1 - me;
                }
                return s;
              }).then((_) {});
          return Padding(
            padding: const EdgeInsets.all(20),
            child: Column(children: [
              Text(_turnMsg(st), style: const TextStyle(fontSize: _Fs.heading, fontWeight: FontWeight.w600)),
              const SizedBox(height: _Sp.lg),
              AspectRatio(
                aspectRatio: _c4Cols / _c4Rows,
                child: Container(
                  decoration: BoxDecoration(color: const Color(0xFF1E4DB7), borderRadius: BorderRadius.circular(18)),
                  padding: const EdgeInsets.all(6),
                  child: Row(children: [
                    for (var c = 0; c < _c4Cols; c++)
                      Expanded(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: myTurn ? () => drop(c) : null,
                          child: Column(children: [
                            for (var r = 0; r < _c4Rows; r++)
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.all(2),
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: switch (board[r * _c4Cols + c]) {
                                        0 => const Color(0xFFFF5F57),
                                        1 => const Color(0xFFFFD60A),
                                        _ => const Color(0x33000000),
                                      },
                                      border: win.contains(r * _c4Cols + c) ? Border.all(color: Colors.white, width: 3) : null,
                                    ),
                                    child: const SizedBox.expand(),
                                  ),
                                ),
                              ),
                          ]),
                        ),
                      ),
                  ]),
                ),
              ),
              const SizedBox(height: _Sp.md),
              Text(me == 0 ? 'أنت الأحمر 🔴' : 'أنت الأصفر 🟡', style: const TextStyle(color: Color(0xCCFFFFFF))),
              if (st['status'] != 'playing') ...[
                const SizedBox(height: _Sp.lg),
                _Btn(label: 'جولة جديدة', onTap: () => unawaited(_g4New(context, chatId, 'connect4', {'board': List<int>.filled(_c4Cols * _c4Rows, -1)}))),
              ],
            ]),
          );
        },
      );
}

// ======================= حرب السفن =======================

const _bsN = 6;
const _bsShips = [3, 2, 2];

List<int> _bsPlace() {
  final rnd = math.Random();
  final used = <int>{};
  for (final len in _bsShips) {
    for (var tries = 0; tries < 200; tries++) {
      final horiz = rnd.nextBool();
      final r = rnd.nextInt(horiz ? _bsN : _bsN - len + 1);
      final c = rnd.nextInt(horiz ? _bsN - len + 1 : _bsN);
      final cells = [for (var k = 0; k < len; k++) (horiz ? r : r + k) * _bsN + (horiz ? c + k : c)];
      // نترك فراغ حول السفينة
      final near = <int>{};
      for (final x in cells) {
        final xr = x ~/ _bsN, xc = x % _bsN;
        for (var dr = -1; dr <= 1; dr++) {
          for (var dc = -1; dc <= 1; dc++) {
            final rr = xr + dr, cc = xc + dc;
            if (rr >= 0 && rr < _bsN && cc >= 0 && cc < _bsN) near.add(rr * _bsN + cc);
          }
        }
      }
      if (near.any(used.contains)) continue;
      used.addAll(cells);
      break;
    }
  }
  return used.toList()..sort();
}

class BattleshipScreen extends StatelessWidget {
  const BattleshipScreen({super.key, required this.chatId});
  final String chatId;

  @override
  Widget build(BuildContext context) {
    void start() => unawaited(_g4New(context, chatId, 'battleship', {
          'status': 'setup',
          'ships': <String, dynamic>{},
          'shots': <String, dynamic>{},
        }));
    return _GameFrame(
      title: 'حرب السفن',
      chatId: chatId,
      kind: 'battleship',
      intro: 'كل واحد عنده 3 سفن على لوحة 6×6. ترمون بالدور وتغرّقون سفن بعض.\n(لوحتك تنخفي بالواجهة بس).',
      start: start,
      body: (row, st) {
        final id = row['id'] as Object;
        final me = _myIdx(st);
        final players = [for (final p in (st['players'] as List)) '$p'];
        final opp = players[1 - me];
        final ships = Map<String, dynamic>.from((st['ships'] as Map?) ?? {});
        final shots = Map<String, dynamic>.from((st['shots'] as Map?) ?? {});
        List<int> listOf(Object? v) => [for (final e in ((v as List?) ?? const [])) (e as num).toInt()];
        final myShips = listOf(ships[_meId]);
        final oppShips = listOf(ships[opp]);
        final myShots = listOf(shots[_meId]);
        final oppShots = listOf(shots[opp]);
        final status = '${st['status']}';

        if (status == 'setup') {
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(myShips.isEmpty ? 'جهّز لوحتك' : 'جاهز. ننتظر الطرف الثاني...',
                  style: const TextStyle(fontSize: _Fs.heading)),
              const SizedBox(height: _Sp.lg),
              if (myShips.isEmpty)
                _Btn(
                    label: 'وزّع سفني عشوائياً',
                    onTap: () => unawaited(_g4Step(context, id, (s) {
                          final sh = Map<String, dynamic>.from((s['ships'] as Map?) ?? {});
                          sh[_meId] = _bsPlace();
                          s['ships'] = sh;
                          if (sh.length == 2) s['status'] = 'playing';
                          return s;
                        }))),
            ]),
          );
        }

        final myTurn = status == 'playing' && st['next'] == me;
        Widget board(List<int> sh, List<int> shotsAt, {required bool showShips, VoidCallback? Function(int)? tap}) => AspectRatio(
              aspectRatio: 1,
              child: GridView.count(
                crossAxisCount: _bsN,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 3,
                crossAxisSpacing: 3,
                children: [
                  for (var i = 0; i < _bsN * _bsN; i++)
                    GestureDetector(
                      onTap: tap?.call(i),
                      child: Container(
                        decoration: BoxDecoration(
                          color: shotsAt.contains(i)
                              ? (sh.contains(i) ? const Color(0xFFFF5F57) : const Color(0x55FFFFFF))
                              : (showShips && sh.contains(i) ? const Color(0xFF5E8BFF) : const Color(0x26FFFFFF)),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        alignment: Alignment.center,
                        child: shotsAt.contains(i) ? Text(sh.contains(i) ? '💥' : '•', style: const TextStyle(fontSize: 16)) : null,
                      ),
                    ),
                ],
              ),
            );
        final won = status == 'won';
        return ListView(padding: const EdgeInsets.all(20), children: [
          Center(child: Text(_turnMsg(st), style: const TextStyle(fontSize: _Fs.heading, fontWeight: FontWeight.w600))),
          const SizedBox(height: _Sp.md),
          const Text('لوحة الخصم (اضغط للرمي)', style: TextStyle(color: Color(0xCCFFFFFF))),
          const SizedBox(height: _Sp.xs),
          board(oppShips, myShots, showShips: won, tap: (i) {
            if (!myTurn || myShots.contains(i)) return null;
            return () => unawaited(_g4Step(context, id, (s) {
                  if (s['status'] != 'playing' || s['next'] != me) return null;
                  final shs = Map<String, dynamic>.from((s['shots'] as Map?) ?? {});
                  final mine = listOf(shs[_meId]);
                  if (mine.contains(i)) return null;
                  mine.add(i);
                  shs[_meId] = mine;
                  s['shots'] = shs;
                  final targets = listOf((s['ships'] as Map)[opp]);
                  if (targets.every(mine.contains)) {
                    s['status'] = 'won';
                    s['by'] = me;
                  } else {
                    s['next'] = 1 - me;
                  }
                  return s;
                }));
          }),
          const SizedBox(height: _Sp.lg),
          const Text('لوحتي', style: TextStyle(color: Color(0xCCFFFFFF))),
          const SizedBox(height: _Sp.xs),
          board(myShips, oppShots, showShips: true),
          if (status != 'playing') ...[
            const SizedBox(height: _Sp.lg),
            _Btn(label: 'جولة جديدة', onTap: start),
          ],
        ]);
      },
    );
  }
}

// ======================= كلمة اليوم (عربي) =======================

const _wordleWords = [
  'مدرسة', 'سيارة', 'حديقة', 'مكتبة', 'طيارة', 'دراجة', 'مفتاح', 'نافذة', 'طاولة', 'حقيبة',
  'فنجان', 'ملعقة', 'صحراء', 'عصفور', 'فراشة', 'سحابة', 'عاصفة', 'بحيرة', 'جزيرة', 'زنبقة',
  'تفاحة', 'بسكوت', 'مدينة', 'سفينة', 'سياحة', 'حكاية', 'رواية', 'قصيدة', 'أغنية', 'ألحان',
  'كمنجة', 'ممثلة', 'صداقة', 'سعادة', 'أمنية', 'حبيبي', 'حبيبة', 'إجازة', 'عيدية', 'رمضان',
  'ضيافة', 'كليجة', 'دولمة', 'تشريب', 'فلافل',
];

String _wNorm(String s) => s
    .replaceAll(RegExp('[أإآ]'), 'ا')
    .replaceAll('ى', 'ي')
    .replaceAll('ة', 'ه')
    .replaceAll('ؤ', 'و')
    .replaceAll('ئ', 'ي');

/// 2 = مكانها صح، 1 = موجودة بمكان ثاني، 0 = مو موجودة
List<int> _wEval(String guess, String answer) {
  final g = _wNorm(guess).split(''), a = _wNorm(answer).split('');
  final res = List<int>.filled(g.length, 0);
  final left = <String, int>{};
  for (var i = 0; i < a.length; i++) {
    if (i < g.length && g[i] == a[i]) {
      res[i] = 2;
    } else {
      left[a[i]] = (left[a[i]] ?? 0) + 1;
    }
  }
  for (var i = 0; i < g.length; i++) {
    if (res[i] == 2) continue;
    if ((left[g[i]] ?? 0) > 0) {
      res[i] = 1;
      left[g[i]] = left[g[i]]! - 1;
    }
  }
  return res;
}

const _wLetters = 'ابتثجحخدذرزسشصضطظعغفقكلمنهوي';

class WordleScreen extends StatefulWidget {
  const WordleScreen({super.key, required this.chatId});
  final String chatId;

  @override
  State<WordleScreen> createState() => _WordleState();
}

class _WordleState extends State<WordleScreen> {
  late final Stream<List<Map<String, dynamic>>> _s = _db
      .from('chat_games')
      .stream(primaryKey: ['id'])
      .eq('chat_id', widget.chatId)
      .order('id', ascending: false)
      .limit(30);
  String _cur = '';
  bool _creating = false;

  String get _today => _dayStr(DateTime.now());

  Future<void> _create() async {
    if (_creating) return;
    _creating = true;
    final idx = DateTime.now().difference(DateTime(2026, 1, 1)).inDays.abs() % _wordleWords.length;
    await _g4New(context, widget.chatId, 'wordle', {
      'day': _today,
      'word': _wordleWords[idx],
      'guesses': <String, dynamic>{},
      'status': 'open',
    });
    _creating = false;
  }

  Future<void> _submit(Map<String, dynamic> row, Map<String, dynamic> st) async {
    if (_cur.length != 5) return;
    final g = _cur;
    setState(() => _cur = '');
    await _g4Step(context, row['id'] as Object, (s) {
      final all = Map<String, dynamic>.from((s['guesses'] as Map?) ?? {});
      final mine = [for (final e in ((all[_meId] as List?) ?? const [])) '$e'];
      if (mine.length >= 6 || (mine.isNotEmpty && _wNorm(mine.last) == _wNorm('${s['word']}'))) return null;
      mine.add(g);
      all[_meId] = mine;
      s['guesses'] = all;
      return s;
    });
  }

  Color _col(int v) => switch (v) {
        2 => const Color(0xFF34C759),
        1 => const Color(0xFFFFB020),
        _ => const Color(0x40FFFFFF),
      };

  Widget _grid(String word, List<String> guesses, {bool hide = false, String live = ''}) => Column(children: [
        for (var r = 0; r < 6; r++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              for (var c = 0; c < 5; c++)
                Builder(builder: (_) {
                  final has = r < guesses.length;
                  final ev = has ? _wEval(guesses[r], word) : null;
                  final letter = has
                      ? (hide ? '' : _wNorm(guesses[r]).split('')[c])
                      : (r == guesses.length && c < live.length ? live[c] : '');
                  return Container(
                    width: hide ? 22 : 44,
                    height: hide ? 22 : 44,
                    margin: const EdgeInsets.all(2),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: ev != null ? _col(ev[c]) : const Color(0x26FFFFFF),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(letter, style: const TextStyle(fontSize: _Fs.heading, fontWeight: FontWeight.w700)),
                  );
                }),
            ]),
          ),
      ]);

  @override
  Widget build(BuildContext context) => Scaffold(
        extendBodyBehindAppBar: true,
        appBar: AppBar(title: const Text('كلمة اليوم'), backgroundColor: Colors.transparent),
        body: Backdrop(
          child: SafeArea(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: _s,
              builder: (_, snap) {
                final all = snap.data;
                if (all == null) return const Center(child: CircularProgressIndicator());
                Map<String, dynamic>? row;
                for (final r in all) {
                  if (r['kind'] == 'wordle' && (r['state'] as Map)['day'] == _today) {
                    row = r;
                    break;
                  }
                }
                if (row == null) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(28),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        const Text('كلمة من 5 حروف، 6 محاولات. وتشوفون مين خمّنها أسرع.',
                            textAlign: TextAlign.center, style: TextStyle(fontSize: _Fs.title, height: 1.6)),
                        const SizedBox(height: 20),
                        _Btn(label: 'ابدأ كلمة اليوم', onTap: _create),
                      ]),
                    ),
                  );
                }
                final st = Map<String, dynamic>.from(row['state'] as Map);
                final word = '${st['word']}';
                final players = [for (final p in (st['players'] as List)) '$p'];
                final guesses = Map<String, dynamic>.from((st['guesses'] as Map?) ?? {});
                List<String> gs(String id) => [for (final e in ((guesses[id] as List?) ?? const [])) '$e'];
                final mine = gs(_meId);
                final theirs = gs(players.firstWhere((p) => p != _meId, orElse: () => ''));
                bool solved(List<String> g) => g.isNotEmpty && _wNorm(g.last) == _wNorm(word);
                final over = solved(mine) || mine.length >= 6;
                final theirOver = solved(theirs) || theirs.length >= 6;
                final used = <String, int>{};
                for (final g in mine) {
                  final ev = _wEval(g, word);
                  final n = _wNorm(g).split('');
                  for (var i = 0; i < 5; i++) {
                    used[n[i]] = math.max(used[n[i]] ?? 0, ev[i] + 1);
                  }
                }
                return ListView(padding: const EdgeInsets.all(16), children: [
                  Center(
                    child: Text(
                        solved(mine)
                            ? 'خمّنتها بـ ${mine.length} محاولات 🎉'
                            : mine.length >= 6
                                ? 'الكلمة كانت: $word'
                                : 'محاولتك ${mine.length + 1} من 6',
                        style: const TextStyle(fontSize: _Fs.title, fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(height: _Sp.sm),
                  _grid(word, mine, live: _cur),
                  const SizedBox(height: _Sp.md),
                  if (!over)
                    Wrap(alignment: WrapAlignment.center, spacing: 5, runSpacing: 5, children: [
                      for (final l in _wLetters.split(''))
                        GestureDetector(
                          onTap: _cur.length < 5 ? () => setState(() => _cur += l) : null,
                          child: Container(
                            width: 34,
                            height: 42,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: switch (used[l]) {
                                3 => const Color(0xFF34C759),
                                2 => const Color(0xFFFFB020),
                                1 => const Color(0x14FFFFFF),
                                _ => const Color(0x33FFFFFF),
                              },
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(l, style: const TextStyle(fontSize: _Fs.title)),
                          ),
                        ),
                    ]),
                  if (!over)
                    Padding(
                      padding: const EdgeInsets.only(top: _Sp.sm),
                      child: Row(children: [
                        Expanded(
                            child: OutlinedButton(
                                onPressed: _cur.isEmpty ? null : () => setState(() => _cur = _cur.substring(0, _cur.length - 1)),
                                child: const Text('مسح'))),
                        const SizedBox(width: _Sp.md),
                        Expanded(child: _Btn(label: 'أرسل', onTap: () => unawaited(_submit(row!, st)))),
                      ]),
                    ),
                  const SizedBox(height: _Sp.lg),
                  const Center(child: Text('الطرف الثاني', style: TextStyle(color: Color(0xCCFFFFFF)))),
                  const SizedBox(height: _Sp.xs),
                  _grid(word, theirs, hide: !over),
                  if (over && theirOver)
                    Padding(
                      padding: const EdgeInsets.only(top: _Sp.md),
                      child: Center(
                        child: Text(
                            solved(mine) && (!solved(theirs) || mine.length < theirs.length)
                                ? 'أنت أسرع 🏆'
                                : solved(theirs) && (!solved(mine) || theirs.length < mine.length)
                                    ? 'الطرف الثاني أسرع 👏'
                                    : 'تعادل 🤝',
                            style: const TextStyle(fontSize: _Fs.titleL)),
                      ),
                    ),
                ]);
              },
            ),
          ),
        ),
      );
}

// ======================= من قال؟ =======================

class WhoSaidScreen extends StatelessWidget {
  const WhoSaidScreen({super.key, required this.chatId});
  final String chatId;

  Future<void> _start(BuildContext context) async {
    try {
      final rows = await _net(_db
          .from('messages')
          .select('sender_id,body')
          .eq('chat_id', chatId)
          .eq('kind', 'text')
          .order('id', ascending: false)
          .limit(400));
      final ok = [
        for (final r in rows)
          if (r['body'] is String && (r['body'] as String).trim().length >= 12 && (r['body'] as String).length <= 90 && !(r['body'] as String).startsWith('http'))
            {'t': (r['body'] as String).trim(), 'by': r['sender_id']},
      ]..shuffle();
      if (ok.length < 6) {
        if (context.mounted) _toast(context, 'ما في رسائل كافية لهاللعبة بعد.');
        return;
      }
      if (!context.mounted) return;
      await _g4New(context, chatId, 'whosaid', {
        'items': ok.take(8).toList(),
        'consent': <String, dynamic>{_meId: true},
        'guesses': <String, dynamic>{},
        'status': 'consent',
      });
    } catch (e) {
      if (context.mounted) _toast(context, _friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) => _GameFrame(
        title: 'من قال؟',
        chatId: chatId,
        kind: 'whosaid',
        intro: 'نختار عبارات من رسائلكم، وكل واحد يخمّن مين كتبها.\nتحتاج موافقة الطرفين، لأن العبارات تظهر بالنتيجة.',
        start: () => unawaited(_start(context)),
        body: (row, st) {
          final id = row['id'] as Object;
          final consent = Map<String, dynamic>.from((st['consent'] as Map?) ?? {});
          if (consent.length < 2) {
            final iAgreed = consent[_meId] == true;
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(iAgreed ? 'ننتظر موافقة الطرف الثاني...' : 'الطرف الثاني يبي يلعب «من قال؟» بعبارات من رسائلكم. توافق؟',
                      textAlign: TextAlign.center, style: const TextStyle(fontSize: _Fs.title)),
                  const SizedBox(height: _Sp.lg),
                  if (!iAgreed)
                    _Btn(
                        label: 'أوافق',
                        onTap: () => unawaited(_g4Step(context, id, (s) {
                              final c = Map<String, dynamic>.from((s['consent'] as Map?) ?? {});
                              c[_meId] = true;
                              s['consent'] = c;
                              if (c.length >= 2) s['status'] = 'playing';
                              return s;
                            }))),
                ]),
              ),
            );
          }
          final items = [for (final e in (st['items'] as List)) Map<String, dynamic>.from(e as Map)];
          final guesses = Map<String, dynamic>.from((st['guesses'] as Map?) ?? {});
          final mine = [for (final e in ((guesses[_meId] as List?) ?? const [])) '$e'];
          final done = mine.length >= items.length;
          if (!done) {
            final i = mine.length;
            return Padding(
              padding: const EdgeInsets.all(20),
              child: Column(children: [
                Text('${i + 1} من ${items.length}', style: const TextStyle(color: Color(0xCCFFFFFF))),
                const SizedBox(height: _Sp.lg),
                Glass(
                    radius: 24,
                    child: Text('«${items[i]['t']}»',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: _Fs.titleL, height: 1.6))),
                const Spacer(),
                Row(children: [
                  _bigChoice('🙋 أنا قلتها', () => unawaited(_pick(context, id, _meId)), color: const Color(0xFF0A84FF)),
                  const SizedBox(width: _Sp.md),
                  _bigChoice('👉 هو قالها', () => unawaited(_pick(context, id, 'other')), color: const Color(0xFFFF5FA2)),
                ]),
                const SizedBox(height: _Sp.xl),
              ]),
            );
          }
          int score(String uid) {
            final g = [for (final e in ((guesses[uid] as List?) ?? const [])) '$e'];
            var n = 0;
            for (var i = 0; i < items.length && i < g.length; i++) {
              final by = '${items[i]['by']}';
              final said = g[i] == 'other' ? '' : g[i];
              final guessedMine = said == uid;
              if ((by == uid) == guessedMine) n++;
            }
            return n;
          }

          final others = consent.keys.where((k) => k != _meId).toList();
          final theirDone = others.isNotEmpty && ((guesses[others.first] as List?)?.length ?? 0) >= items.length;
          return ListView(padding: const EdgeInsets.all(20), children: [
            Center(child: Text('نتيجتك: ${score(_meId)} من ${items.length}', style: const TextStyle(fontSize: _Fs.heading, fontWeight: FontWeight.w700))),
            const SizedBox(height: _Sp.sm),
            Center(
                child: Text(theirDone ? 'نتيجته: ${score(others.first)} من ${items.length}' : 'ننتظر الطرف الثاني يخلص...',
                    style: const TextStyle(fontSize: _Fs.title))),
            const SizedBox(height: _Sp.lg),
            for (final it in items)
              Padding(
                padding: const EdgeInsets.only(bottom: _Sp.sm),
                child: Glass(
                    radius: 18,
                    shadow: false,
                    child: Text('«${it['t']}» — ${it['by'] == _meId ? 'أنا' : 'هو'}')),
              ),
          ]);
        },
      );

  Future<void> _pick(BuildContext context, Object id, String who) => _g4Step(context, id, (s) {
        final g = Map<String, dynamic>.from((s['guesses'] as Map?) ?? {});
        final m = [for (final e in ((g[_meId] as List?) ?? const [])) '$e'];
        if (m.length >= (s['items'] as List).length) return null;
        g[_meId] = [...m, who];
        s['guesses'] = g;
        return s;
      });
}

// ======================= صراحة وجرأة =======================

const _truths = {
  'cute': [
    'شنو أحلى شي صار بينا؟', 'شنو أول شي لاحظته فيني؟', 'شنو الأغنية اللي تذكّرك فيني؟',
    'شنو أكثر شي يضحّكك فيني؟', 'لو نسافر الحين، وين تبي؟', 'شنو عادتي اللي تعجبك؟',
  ],
  'bold': [
    'شنو أكثر شي غرتَ منه؟', 'شنو أكبر كذبة قلتها لي؟', 'شنو الشي اللي ما تقدر تقوله وجهاً لوجه؟',
    'مين كان آخر شخص فكّرت فيه قبلي؟', 'شنو أحرج موقف صار لك قدامي؟', 'شنو اللي تتمنى أغيّره فيني؟',
  ],
  'deep': [
    'شنو أكبر خوف عندك بالعلاقة؟', 'شنو الشي اللي يخليك تحس بالأمان معي؟', 'كيف تتخيل حياتنا بعد خمس سنين؟',
    'شنو اللي تعلمته مني؟', 'متى حسّيت إنك تحبني فعلاً؟', 'شنو حلمك اللي ما قلته لأحد؟',
  ],
};

const _dares = {
  'cute': [
    'أرسل لي ثلاث صفات تحبها فيني.', 'سجّل لي رسالة صوتية تقول فيها صباح الخير بصوت مضحك.',
    'أرسل صورة لشي يذكّرك فيني.', 'اكتب لي بيت شعر قصير.', 'غنّي لي مقطع بصوتك.', 'ارسم قلب وأرسله.',
  ],
  'bold': [
    'أرسل سيلفي بأغرب تعبير وجه.', 'قلّد صوت شخصية كرتون وسجّله.', 'اتصل فيديو وارقص 10 ثواني.',
    'غيّر اسمك عندي لساعة لشي أختاره.', 'أرسل آخر صورة بمعرضك بدون اختيار.', 'قول «أحبك» بثلاث لغات.',
  ],
  'deep': [
    'اكتب فقرة قصيرة عن لحظة تتمنى تعيدها.', 'قل لي ثلاث أشياء أنت ممتن لها بنا.',
    'سجّل رسالة صوتية تعتذر فيها عن شي صغير.', 'اكتب لي رسالة تنفتح بعد سنة (كبسولة).',
    'أخبرني بشي كنت خايف تقوله.', 'اكتب وعد صغير تلتزم فيه هالأسبوع.',
  ],
};

class TruthDareScreen extends StatelessWidget {
  const TruthDareScreen({super.key, required this.chatId});
  final String chatId;

  static const _lv = {'cute': '🌸 لطيف', 'bold': '🌶️ جريء', 'deep': '🌊 عميق'};

  @override
  Widget build(BuildContext context) => _GameFrame(
        title: 'صراحة وجرأة',
        chatId: chatId,
        kind: 'truthdare',
        intro: 'بالدور: صراحة (سؤال) أو جرأة (تحدي)، ومستوى تختارونه.',
        start: () async {
          final lv = await showModalBottomSheet<String>(
            context: context,
            builder: (ctx) => SafeArea(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Padding(padding: EdgeInsets.all(12), child: Text('اختاروا المستوى')),
                for (final e in _lv.entries) ListTile(title: Text(e.value), onTap: () => Navigator.pop(ctx, e.key)),
              ]),
            ),
          );
          if (lv != null && context.mounted) {
            await _g4New(context, chatId, 'truthdare', {'level': lv, 'card': null, 'kind': null, 'status': 'playing'});
          }
        },
        body: (row, st) {
          final id = row['id'] as Object;
          final me = _myIdx(st);
          final myTurn = st['next'] == me;
          final lv = '${st['level']}';
          Future<void> draw(String kind) => _g4Step(context, id, (s) {
                final pool = (kind == 'truth' ? _truths : _dares)[lv]!;
                s['card'] = pool[math.Random().nextInt(pool.length)];
                s['kind'] = kind;
                return s;
              }).then((_) {});
          Future<void> done() => _g4Step(context, id, (s) {
                s['card'] = null;
                s['kind'] = null;
                s['next'] = 1 - (s['next'] as int);
                return s;
              }).then((_) {});
          final card = st['card'] as String?;
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Column(children: [
              Text(_lv[lv] ?? '', style: const TextStyle(color: Color(0xCCFFFFFF))),
              const SizedBox(height: _Sp.sm),
              Text(myTurn ? 'دورك' : 'دور الطرف الثاني', style: const TextStyle(fontSize: _Fs.heading, fontWeight: FontWeight.w700)),
              const Spacer(),
              if (card != null)
                Glass(
                    radius: 28,
                    padding: const EdgeInsets.all(24),
                    child: Column(children: [
                      Text(st['kind'] == 'truth' ? '🗣️ صراحة' : '🔥 جرأة', style: const TextStyle(fontSize: _Fs.titleL)),
                      const SizedBox(height: _Sp.md),
                      Text(card, textAlign: TextAlign.center, style: const TextStyle(fontSize: _Fs.heading, height: 1.6)),
                    ]))
              else
                const Text('اختر صراحة أو جرأة', style: TextStyle(fontSize: _Fs.title)),
              const Spacer(),
              if (myTurn && card == null)
                Row(children: [
                  _bigChoice('🗣️ صراحة', () => unawaited(draw('truth')), color: const Color(0xFF0A84FF)),
                  const SizedBox(width: _Sp.md),
                  _bigChoice('🔥 جرأة', () => unawaited(draw('dare')), color: const Color(0xFFFF5FA2)),
                ])
              else if (card != null)
                _Btn(label: 'تمّت، الدور عليه', onTap: () => unawaited(done())),
              const SizedBox(height: _Sp.xl),
            ]),
          );
        },
      );
}
