part of 'main.dart';

// ---------- داما وشطرنج بين الطرفين (بالدور، كل واحد من جواله) ----------

// ======================= داما =======================
// r = اللي بدأ (تحت عنده، يطلع لفوق)، b = الثاني. الكبيرة = ملك.

bool _ckDark(int i) => ((i ~/ 8) + (i % 8)) % 2 == 1;
bool _ckMine(String p, String side) => p.toLowerCase() == side;

List<(int, int)> _ckDirs(String p) {
  if (p == 'R' || p == 'B') return const [(-1, -1), (-1, 1), (1, -1), (1, 1)];
  return p == 'r' ? const [(-1, -1), (-1, 1)] : const [(1, -1), (1, 1)];
}

/// القفزات الممكنة لقطعة: (الهدف، القطعة المأكولة)
List<(int, int)> _ckJumps(List<String> b, int i) {
  final p = b[i];
  if (p.isEmpty) return const [];
  final side = p.toLowerCase();
  final out = <(int, int)>[];
  final r = i ~/ 8, c = i % 8;
  for (final (dr, dc) in _ckDirs(p)) {
    final mr = r + dr, mc = c + dc, tr = r + 2 * dr, tc = c + 2 * dc;
    if (tr < 0 || tr > 7 || tc < 0 || tc > 7) continue;
    final mid = b[mr * 8 + mc];
    if (mid.isNotEmpty && !_ckMine(mid, side) && b[tr * 8 + tc].isEmpty) {
      out.add((tr * 8 + tc, mr * 8 + mc));
    }
  }
  return out;
}

List<int> _ckSteps(List<String> b, int i) {
  final p = b[i];
  final out = <int>[];
  final r = i ~/ 8, c = i % 8;
  for (final (dr, dc) in _ckDirs(p)) {
    final tr = r + dr, tc = c + dc;
    if (tr < 0 || tr > 7 || tc < 0 || tc > 7) continue;
    if (b[tr * 8 + tc].isEmpty) out.add(tr * 8 + tc);
  }
  return out;
}

bool _ckAnyJump(List<String> b, String side) {
  for (var i = 0; i < 64; i++) {
    if (b[i].isNotEmpty && _ckMine(b[i], side) && _ckJumps(b, i).isNotEmpty) return true;
  }
  return false;
}

bool _ckAnyMove(List<String> b, String side) {
  for (var i = 0; i < 64; i++) {
    if (b[i].isNotEmpty &&
        _ckMine(b[i], side) &&
        (_ckJumps(b, i).isNotEmpty || _ckSteps(b, i).isNotEmpty)) {
      return true;
    }
  }
  return false;
}

/// الأماكن اللي تقدر تروح لها القطعة (مع إجبار الأكل)
List<int> _ckTargets(List<String> b, int i, String side, int must) {
  if (b[i].isEmpty || !_ckMine(b[i], side)) return const [];
  if (must >= 0 && i != must) return const [];
  final jumps = _ckJumps(b, i).map((j) => j.$1).toList();
  if (must >= 0) return jumps;
  if (_ckAnyJump(b, side)) return jumps;
  return _ckSteps(b, i);
}

class CheckersScreen extends StatefulWidget {
  const CheckersScreen({super.key, required this.chatId});
  final String chatId;

  @override
  State<CheckersScreen> createState() => _CheckersState();
}

class _CheckersState extends State<CheckersScreen> {
  int? _sel;

  void _start() {
    final b = List<String>.filled(64, '');
    for (var i = 0; i < 64; i++) {
      if (!_ckDark(i)) continue;
      if (i ~/ 8 <= 2) b[i] = 'b';
      if (i ~/ 8 >= 5) b[i] = 'r';
    }
    setState(() => _sel = null);
    unawaited(_gameNew(context, widget.chatId, 'checkers',
        {'board': b, 'red': _meId, 'turn': 'r', 'must': -1, 'status': 'playing'}));
  }

  Future<void> _move(Map<String, dynamic> row, int from, int to) async {
    setState(() => _sel = null);
    await _gameMutate(context, row['id'] as Object, (s) {
      if (s['status'] != 'playing') return null;
      final side = s['red'] == _meId ? 'r' : 'b';
      if (s['turn'] != side) return null;
      final b = List<String>.from(s['board'] as List);
      final must = (s['must'] as num?)?.toInt() ?? -1;
      if (!_ckTargets(b, from, side, must).contains(to)) return null;
      final jump = _ckJumps(b, from).where((j) => j.$1 == to).toList();
      var p = b[from];
      b[from] = '';
      if (jump.isNotEmpty) b[jump.first.$2] = '';
      final row8 = to ~/ 8;
      var promoted = false;
      if ((p == 'r' && row8 == 0) || (p == 'b' && row8 == 7)) {
        p = p.toUpperCase();
        promoted = true;
      }
      b[to] = p;
      final other = side == 'r' ? 'b' : 'r';
      // أكل مرة ثانية بنفس القطعة؟ نكمّل الدور
      if (jump.isNotEmpty && !promoted && _ckJumps(b, to).isNotEmpty) {
        return {...s, 'board': b, 'must': to};
      }
      final lost = !b.any((x) => x.isNotEmpty && _ckMine(x, other)) || !_ckAnyMove(b, other);
      return {
        ...s,
        'board': b,
        'must': -1,
        'turn': lost ? side : other,
        'status': lost ? 'won' : 'playing',
        'by': lost ? side : null,
      };
    }, winner: (s) => s['status'] == 'won' ? _meId : null);
  }

  @override
  Widget build(BuildContext context) => _GameFrame(
        title: 'داما',
        chatId: widget.chatId,
        kind: 'checkers',
        intro: 'كل واحد يحرك قطعة بالدور على المربعات الغامقة. الأكل إجباري، واللي يوصل للطرف الثاني يصير ملك 👑.',
        start: _start,
        body: (row, st) {
          final b = List<String>.from(st['board'] as List);
          final side = st['red'] == _meId ? 'r' : 'b';
          final must = (st['must'] as num?)?.toInt() ?? -1;
          final myTurn = st['status'] == 'playing' && st['turn'] == side;
          final sel = _sel;
          final targets = sel == null || !myTurn ? const <int>[] : _ckTargets(b, sel, side, must);
          final flip = side == 'b'; // كل واحد يشوف قطعه تحت
          final mine = b.where((x) => x.isNotEmpty && _ckMine(x, side)).length;
          final theirs = b.where((x) => x.isNotEmpty && !_ckMine(x, side)).length;
          final String msg;
          if (st['status'] == 'won') {
            msg = st['by'] == side ? 'فزت! 🎉' : 'فاز هو';
          } else {
            msg = myTurn ? (must >= 0 ? 'كمّل الأكل!' : 'دورك') : 'دوره';
          }
          return Padding(
            padding: const EdgeInsets.all(14),
            child: Column(children: [
              Text('$msg · قطعك $mine · قطعه $theirs',
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              AspectRatio(
                aspectRatio: 1,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0x66FFFFFF), width: 2),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: GridView.count(
                    crossAxisCount: 8,
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      for (var v = 0; v < 64; v++)
                        Builder(builder: (_) {
                          final i = flip ? 63 - v : v;
                          final p = b[i];
                          final dark = _ckDark(i);
                          final isTarget = targets.contains(i);
                          return GestureDetector(
                            onTap: !myTurn
                                ? null
                                : () {
                                    if (isTarget && sel != null) {
                                      unawaited(_move(row, sel, i));
                                    } else if (p.isNotEmpty && _ckMine(p, side)) {
                                      setState(() => _sel = i);
                                    }
                                  },
                            child: Container(
                              color: sel == i
                                  ? const Color(0xFF3D6E5A)
                                  : dark
                                      ? const Color(0xFF6B4A33)
                                      : const Color(0xFFE8D5B5),
                              alignment: Alignment.center,
                              child: p.isNotEmpty
                                  ? FractionallySizedBox(
                                      widthFactor: 0.78,
                                      heightFactor: 0.78,
                                      child: Container(
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          gradient: RadialGradient(
                                            center: const Alignment(-0.3, -0.3),
                                            colors: p.toLowerCase() == 'r'
                                                ? const [Color(0xFFFF8A80), Color(0xFFC62828)]
                                                : const [Color(0xFF5A5A5A), Color(0xFF111111)],
                                          ),
                                          border: Border.all(color: const Color(0x99FFFFFF)),
                                          boxShadow: const [
                                            BoxShadow(color: Color(0x66000000), blurRadius: 3, offset: Offset(0, 2)),
                                          ],
                                        ),
                                        alignment: Alignment.center,
                                        child: p == 'R' || p == 'B'
                                            ? const Text('👑', style: TextStyle(fontSize: 14))
                                            : null,
                                      ),
                                    )
                                  : isTarget
                                      ? Container(
                                          width: 12,
                                          height: 12,
                                          decoration: const BoxDecoration(
                                              shape: BoxShape.circle, color: Color(0xAA7CFFB2)),
                                        )
                                      : null,
                            ),
                          );
                        }),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(side == 'r' ? 'أنت الأحمر' : 'أنت الأسود',
                  style: const TextStyle(color: Color(0xB3FFFFFF))),
              if (st['status'] == 'won') ...[
                const SizedBox(height: 10),
                _Btn(label: 'جولة جديدة', onTap: _start),
              ],
            ]),
          );
        },
      );
}

// ======================= شطرنج =======================
// اللوحة 64 حرف: كبير = أبيض، صغير = أسود. الصف 0 فوق (الأسود)، 7 تحت (الأبيض).

const _chStart = 'rnbqkbnrpppppppp................................PPPPPPPPRNBQKBNR';

bool _chWhite(String p) => p != '.' && p == p.toUpperCase();
bool _chOwn(String p, String side) => p != '.' && (side == 'w' ? _chWhite(p) : !_chWhite(p));

/// هل المربع i مهدد من الطرف by؟
bool _chAttacked(String b, int i, String by) {
  final r = i ~/ 8, c = i % 8;
  bool at(int rr, int cc, String pieces) {
    if (rr < 0 || rr > 7 || cc < 0 || cc > 7) return false;
    final p = b[rr * 8 + cc];
    return p != '.' && _chOwn(p, by) && pieces.contains(p.toLowerCase());
  }

  // بيدق
  final pr = by == 'w' ? r + 1 : r - 1;
  if (at(pr, c - 1, 'p') || at(pr, c + 1, 'p')) return true;
  // حصان
  for (final (dr, dc) in const [(1, 2), (2, 1), (-1, 2), (-2, 1), (1, -2), (2, -1), (-1, -2), (-2, -1)]) {
    if (at(r + dr, c + dc, 'n')) return true;
  }
  // ملك
  for (var dr = -1; dr <= 1; dr++) {
    for (var dc = -1; dc <= 1; dc++) {
      if ((dr != 0 || dc != 0) && at(r + dr, c + dc, 'k')) return true;
    }
  }
  // خطوط
  for (final (dr, dc, pieces) in const [
    (1, 0, 'rq'), (-1, 0, 'rq'), (0, 1, 'rq'), (0, -1, 'rq'),
    (1, 1, 'bq'), (1, -1, 'bq'), (-1, 1, 'bq'), (-1, -1, 'bq'),
  ]) {
    var rr = r + dr, cc = c + dc;
    while (rr >= 0 && rr <= 7 && cc >= 0 && cc <= 7) {
      final p = b[rr * 8 + cc];
      if (p != '.') {
        if (_chOwn(p, by) && pieces.contains(p.toLowerCase())) return true;
        break;
      }
      rr += dr;
      cc += dc;
    }
  }
  return false;
}

String _chSet(String b, int i, String p) => b.substring(0, i) + p + b.substring(i + 1);

/// يطبّق حركة (بدون تحقق): يرجع اللوحة الجديدة
String _chApply(String b, int from, int to, int ep) {
  var p = b[from];
  var nb = _chSet(b, from, '.');
  // أخذ بالمرور
  if (p.toLowerCase() == 'p' && to == ep && b[to] == '.') {
    final capR = from ~/ 8;
    nb = _chSet(nb, capR * 8 + to % 8, '.');
  }
  // ترقية (وزير تلقائي)
  if (p == 'P' && to ~/ 8 == 0) p = 'Q';
  if (p == 'p' && to ~/ 8 == 7) p = 'q';
  nb = _chSet(nb, to, p);
  // تبييت: نحرك القلعة
  if (p.toLowerCase() == 'k' && (to - from).abs() == 2) {
    final r = from ~/ 8;
    if (to > from) {
      nb = _chSet(_chSet(nb, r * 8 + 7, '.'), r * 8 + 5, p == 'K' ? 'R' : 'r');
    } else {
      nb = _chSet(_chSet(nb, r * 8, '.'), r * 8 + 3, p == 'K' ? 'R' : 'r');
    }
  }
  return nb;
}

List<int> _chPseudo(String b, int i, String castle, int ep) {
  final p = b[i];
  if (p == '.') return const [];
  final side = _chWhite(p) ? 'w' : 'b';
  final r = i ~/ 8, c = i % 8;
  final out = <int>[];
  void ray(int dr, int dc, {bool once = false}) {
    var rr = r + dr, cc = c + dc;
    while (rr >= 0 && rr <= 7 && cc >= 0 && cc <= 7) {
      final t = b[rr * 8 + cc];
      if (t == '.') {
        out.add(rr * 8 + cc);
      } else {
        if (!_chOwn(t, side)) out.add(rr * 8 + cc);
        break;
      }
      if (once) break;
      rr += dr;
      cc += dc;
    }
  }

  switch (p.toLowerCase()) {
    case 'p':
      final dir = side == 'w' ? -1 : 1;
      final f1 = (r + dir) * 8 + c;
      if (r + dir >= 0 && r + dir <= 7 && b[f1] == '.') {
        out.add(f1);
        final startRow = side == 'w' ? 6 : 1;
        final f2 = (r + 2 * dir) * 8 + c;
        if (r == startRow && b[f2] == '.') out.add(f2);
      }
      for (final dc in const [-1, 1]) {
        final cc = c + dc, rr = r + dir;
        if (cc < 0 || cc > 7 || rr < 0 || rr > 7) continue;
        final t = rr * 8 + cc;
        if ((b[t] != '.' && !_chOwn(b[t], side)) || t == ep) out.add(t);
      }
    case 'n':
      for (final (dr, dc) in const [(1, 2), (2, 1), (-1, 2), (-2, 1), (1, -2), (2, -1), (-1, -2), (-2, -1)]) {
        ray(dr, dc, once: true);
      }
    case 'b':
      for (final (dr, dc) in const [(1, 1), (1, -1), (-1, 1), (-1, -1)]) {
        ray(dr, dc);
      }
    case 'r':
      for (final (dr, dc) in const [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
        ray(dr, dc);
      }
    case 'q':
      for (final (dr, dc) in const [(1, 1), (1, -1), (-1, 1), (-1, -1), (1, 0), (-1, 0), (0, 1), (0, -1)]) {
        ray(dr, dc);
      }
    case 'k':
      for (var dr = -1; dr <= 1; dr++) {
        for (var dc = -1; dc <= 1; dc++) {
          if (dr != 0 || dc != 0) ray(dr, dc, once: true);
        }
      }
      // تبييت
      final opp = side == 'w' ? 'b' : 'w';
      final home = side == 'w' ? 60 : 4;
      if (i == home && !_chAttacked(b, i, opp)) {
        final k = side == 'w' ? 'K' : 'k', q = side == 'w' ? 'Q' : 'q';
        if (castle.contains(k) && b[i + 1] == '.' && b[i + 2] == '.' &&
            !_chAttacked(b, i + 1, opp) && !_chAttacked(b, i + 2, opp)) {
          out.add(i + 2);
        }
        if (castle.contains(q) && b[i - 1] == '.' && b[i - 2] == '.' && b[i - 3] == '.' &&
            !_chAttacked(b, i - 1, opp) && !_chAttacked(b, i - 2, opp)) {
          out.add(i - 2);
        }
      }
  }
  return out;
}

bool _chInCheck(String b, String side) {
  final k = b.indexOf(side == 'w' ? 'K' : 'k');
  return k >= 0 && _chAttacked(b, k, side == 'w' ? 'b' : 'w');
}

List<int> _chLegal(String b, int i, String castle, int ep) {
  final p = b[i];
  if (p == '.') return const [];
  final side = _chWhite(p) ? 'w' : 'b';
  return [
    for (final t in _chPseudo(b, i, castle, ep))
      if (!_chInCheck(_chApply(b, i, t, ep), side)) t,
  ];
}

bool _chHasMoves(String b, String side, String castle, int ep) {
  for (var i = 0; i < 64; i++) {
    if (_chOwn(b[i], side) && _chLegal(b, i, castle, ep).isNotEmpty) return true;
  }
  return false;
}

const _chGlyph = {
  'k': '♚', 'q': '♛', 'r': '♜', 'b': '♝', 'n': '♞', 'p': '♟',
};

class ChessScreen extends StatefulWidget {
  const ChessScreen({super.key, required this.chatId});
  final String chatId;

  @override
  State<ChessScreen> createState() => _ChessState();
}

class _ChessState extends State<ChessScreen> {
  int? _sel;

  void _start() {
    setState(() => _sel = null);
    unawaited(_gameNew(context, widget.chatId, 'chess', {
      'board': _chStart,
      'white': _meId,
      'turn': 'w',
      'castle': 'KQkq',
      'ep': -1,
      'last': <int>[],
      'status': 'playing',
    }));
  }

  Future<void> _move(Map<String, dynamic> row, int from, int to) async {
    setState(() => _sel = null);
    await _gameMutate(context, row['id'] as Object, (s) {
      if (s['status'] != 'playing') return null;
      final side = s['white'] == _meId ? 'w' : 'b';
      if (s['turn'] != side) return null;
      final b = '${s['board']}';
      final castle = '${s['castle'] ?? ''}';
      final ep = (s['ep'] as num?)?.toInt() ?? -1;
      if (!_chOwn(b[from], side) || !_chLegal(b, from, castle, ep).contains(to)) return null;
      final p = b[from];
      final nb = _chApply(b, from, to, ep);
      // حقوق التبييت
      var nc = castle;
      if (p == 'K') nc = nc.replaceAll('K', '').replaceAll('Q', '');
      if (p == 'k') nc = nc.replaceAll('k', '').replaceAll('q', '');
      for (final (sq, ch) in const [(63, 'K'), (56, 'Q'), (7, 'k'), (0, 'q')]) {
        if (from == sq || to == sq) nc = nc.replaceAll(ch, '');
      }
      final nep = p.toLowerCase() == 'p' && (to - from).abs() == 16 ? (from + to) ~/ 2 : -1;
      final other = side == 'w' ? 'b' : 'w';
      final hasMoves = _chHasMoves(nb, other, nc, nep);
      final check = _chInCheck(nb, other);
      final status = hasMoves ? 'playing' : (check ? 'mate' : 'stalemate');
      return {
        ...s,
        'board': nb,
        'turn': other,
        'castle': nc,
        'ep': nep,
        'last': [from, to],
        'check': check,
        'status': status,
        'by': status == 'mate' ? side : null,
      };
    }, winner: (s) => s['status'] == 'mate' ? _meId : null);
  }

  Future<void> _resign(Map<String, dynamic> row) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تستسلم؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('لا')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('أستسلم')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _gameMutate(context, row['id'] as Object, (s) {
      if (s['status'] != 'playing') return null;
      final side = s['white'] == _meId ? 'w' : 'b';
      return {...s, 'status': 'resigned', 'by': side == 'w' ? 'b' : 'w'};
    });
  }

  @override
  Widget build(BuildContext context) => _GameFrame(
        title: 'شطرنج',
        chatId: widget.chatId,
        kind: 'chess',
        intro: 'شطرنج كامل بالدور: تبييت، أخذ بالمرور، ترقية لوزير تلقائياً، وكش مات.',
        start: _start,
        body: (row, st) {
          final b = '${st['board']}';
          final side = st['white'] == _meId ? 'w' : 'b';
          final status = '${st['status']}';
          final myTurn = status == 'playing' && st['turn'] == side;
          final castle = '${st['castle'] ?? ''}';
          final ep = (st['ep'] as num?)?.toInt() ?? -1;
          final last = List<int>.from((st['last'] ?? const []) as List);
          final sel = _sel;
          final targets = sel == null || !myTurn ? const <int>[] : _chLegal(b, sel, castle, ep);
          final flip = side == 'b';
          final String msg = switch (status) {
            'mate' => st['by'] == side ? 'كش مات! فزت 🎉' : 'كش مات، فاز هو',
            'stalemate' => 'تعادل (ما في حركات)',
            'resigned' => st['by'] == side ? 'استسلم، فزت 🎉' : 'استسلمت',
            _ => '${myTurn ? 'دورك' : 'دوره'}${st['check'] == true ? ' · كش!' : ''}',
          };
          return Padding(
            padding: const EdgeInsets.all(12),
            child: Column(children: [
              Text(msg, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              AspectRatio(
                aspectRatio: 1,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0x66FFFFFF), width: 2),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: GridView.count(
                    crossAxisCount: 8,
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      for (var v = 0; v < 64; v++)
                        Builder(builder: (_) {
                          final i = flip ? 63 - v : v;
                          final p = b[i];
                          final light = ((i ~/ 8) + (i % 8)) % 2 == 0;
                          final isT = targets.contains(i);
                          final inCheck = st['check'] == true &&
                              p.toLowerCase() == 'k' &&
                              _chOwn(p, '${st['turn']}');
                          return GestureDetector(
                            onTap: !myTurn
                                ? null
                                : () {
                                    if (isT && sel != null) {
                                      unawaited(_move(row, sel, i));
                                    } else if (_chOwn(p, side)) {
                                      setState(() => _sel = i);
                                    } else {
                                      setState(() => _sel = null);
                                    }
                                  },
                            child: Container(
                              color: sel == i
                                  ? const Color(0xFF7FA650)
                                  : inCheck
                                      ? const Color(0xFFE05050)
                                      : last.contains(i)
                                          ? (light ? const Color(0xFFF5E58A) : const Color(0xFFC9B24A))
                                          : (light ? const Color(0xFFEEDCC0) : const Color(0xFF9C6B4B)),
                              alignment: Alignment.center,
                              child: p != '.'
                                  ? FittedBox(
                                      child: Padding(
                                        padding: const EdgeInsets.all(2),
                                        child: Text('${_chGlyph[p.toLowerCase()]}︎',
                                            style: TextStyle(
                                              fontSize: 34,
                                              height: 1.1,
                                              color: _chWhite(p) ? Colors.white : const Color(0xFF1A1A1A),
                                              shadows: [
                                                Shadow(
                                                    color: _chWhite(p) ? Colors.black : Colors.white54,
                                                    blurRadius: 2),
                                              ],
                                            )),
                                      ),
                                    )
                                  : isT
                                      ? Container(
                                          width: 12,
                                          height: 12,
                                          decoration: const BoxDecoration(
                                              shape: BoxShape.circle, color: Color(0x8833AA55)),
                                        )
                                      : null,
                            ),
                          );
                        }),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(side == 'w' ? 'أنت الأبيض' : 'أنت الأسود',
                  style: const TextStyle(color: Color(0xB3FFFFFF))),
              const SizedBox(height: 8),
              if (status == 'playing')
                TextButton(onPressed: () => _resign(row), child: const Text('استسلام'))
              else
                _Btn(label: 'جولة جديدة', onTap: _start),
            ]),
          );
        },
      );
}
