part of 'main.dart';

// ---------- ألعاب الجولة الثانية (2): سلسلة الكلمات، كمّل القصة، لوحة الرسم، بينغو، تحدي الأسبوع ----------

// ======================= سلسلة الكلمات =======================

String _chainEnd(String w) {
  var n = _wNorm(w.trim());
  n = n.replaceAll(RegExp(r'[ًٌٍَُِّْـ]'), '');
  return n.isEmpty ? '' : n[n.length - 1];
}

String _chainStart(String w) {
  var n = _wNorm(w.trim());
  n = n.replaceAll(RegExp(r'[ًٌٍَُِّْـ]'), '');
  return n.isEmpty ? '' : n[0];
}

class WordChainScreen extends StatefulWidget {
  const WordChainScreen({super.key, required this.chatId});
  final String chatId;

  @override
  State<WordChainScreen> createState() => _WordChainState();
}

class _WordChainState extends State<WordChainScreen> {
  final _c = TextEditingController();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _GameFrame(
        title: 'سلسلة الكلمات',
        chatId: widget.chatId,
        kind: 'wordchain',
        intro: 'كل واحد يكتب كلمة تبدأ بآخر حرف من كلمة الثاني. ما تنعاد كلمة.',
        start: () => unawaited(_g4New(context, widget.chatId, 'wordchain', {'words': <Map<String, dynamic>>[]})),
        body: (row, st) {
          final me = _myIdx(st);
          final myTurn = st['next'] == me;
          final words = [for (final e in (st['words'] as List)) Map<String, dynamic>.from(e as Map)];
          final last = words.isEmpty ? null : '${words.last['w']}';
          Future<void> send() async {
            final w = _c.text.trim();
            if (w.length < 2) return;
            if (last != null && _chainStart(w) != _chainEnd(last)) {
              _toast(context, 'لازم تبدأ بحرف «${_chainEnd(last)}».');
              return;
            }
            if (words.any((x) => _wNorm('${x['w']}') == _wNorm(w))) {
              _toast(context, 'هذي الكلمة انقالت.');
              return;
            }
            _c.clear();
            await _g4Step(context, row['id'] as Object, (s) {
              if (s['next'] != me) return null;
              final ws = [for (final e in (s['words'] as List)) Map<String, dynamic>.from(e as Map)];
              ws.add({'w': w, 'by': me});
              s['words'] = ws;
              s['next'] = 1 - me;
              return s;
            });
          }

          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              Text(myTurn ? 'دورك' : 'دور الطرف الثاني', style: const TextStyle(fontSize: _Fs.heading, fontWeight: FontWeight.w700)),
              if (last != null)
                Padding(
                  padding: const EdgeInsets.only(top: _Sp.sm),
                  child: Text('ابدأ بحرف «${_chainEnd(last)}»', style: const TextStyle(fontSize: _Fs.title, color: Color(0xFFFFD60A))),
                ),
              const SizedBox(height: _Sp.md),
              Expanded(
                child: ListView(reverse: true, children: [
                  for (final w in words.reversed)
                    Align(
                      alignment: w['by'] == me ? AlignmentDirectional.centerStart : AlignmentDirectional.centerEnd,
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 3),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                            color: w['by'] == me ? const Color(0x660A84FF) : const Color(0x66FF5FA2),
                            borderRadius: BorderRadius.circular(16)),
                        child: Text('${w['w']}', style: const TextStyle(fontSize: _Fs.titleL)),
                      ),
                    ),
                ]),
              ),
              Text('${words.length} كلمة بالسلسلة', style: const TextStyle(color: Color(0xB3FFFFFF), fontSize: _Fs.small)),
              Row(children: [
                Expanded(
                    child: TextField(
                        controller: _c,
                        enabled: myTurn,
                        maxLength: 20,
                        onSubmitted: (_) => unawaited(send()),
                        decoration: InputDecoration(hintText: myTurn ? 'اكتب كلمة' : 'انتظر دورك'))),
                IconButton(onPressed: myTurn ? () => unawaited(send()) : null, icon: const Icon(Icons.send_rounded)),
              ]),
            ]),
          );
        },
      );
}

// ======================= كمّل القصة =======================

class StoryGameScreen extends StatefulWidget {
  const StoryGameScreen({super.key, required this.chatId});
  final String chatId;

  @override
  State<StoryGameScreen> createState() => _StoryGameState();
}

class _StoryGameState extends State<StoryGameScreen> {
  final _c = TextEditingController();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  static const _starters = [
    'في ليلة ممطرة، سمعنا طرق على الباب...',
    'كان يا ما كان، بقرية صغيرة على البحر...',
    'فتحت الصندوق القديم ولقيت...',
    'آخر قطار بالمحطة وصل متأخر، ونزل منه...',
    'صحيت الصبح وإذا الدنيا كلها صارت...',
  ];

  @override
  Widget build(BuildContext context) => _GameFrame(
        title: 'كمّل القصة',
        chatId: widget.chatId,
        kind: 'story',
        intro: 'جملة لكل واحد بالدور لين تخلص القصة، وتنحفظ بذكرياتكم.',
        start: () => unawaited(_g4New(context, widget.chatId, 'story', {
          'lines': [
            {'t': _starters[math.Random().nextInt(_starters.length)], 'by': -1}
          ],
        })),
        body: (row, st) {
          final me = _myIdx(st);
          final myTurn = st['status'] == 'playing' && st['next'] == me;
          final lines = [for (final e in (st['lines'] as List)) Map<String, dynamic>.from(e as Map)];
          Future<void> add() async {
            final t = _c.text.trim();
            if (t.isEmpty) return;
            _c.clear();
            await _g4Step(context, row['id'] as Object, (s) {
              if (s['next'] != me) return null;
              final ls = [for (final e in (s['lines'] as List)) Map<String, dynamic>.from(e as Map)];
              ls.add({'t': t, 'by': me});
              s['lines'] = ls;
              s['next'] = 1 - me;
              return s;
            });
          }

          Future<void> finish() async {
            final ok = await _g4Step(context, row['id'] as Object, (s) {
              s['status'] = 'done';
              return s;
            });
            if (!ok) return;
            try {
              await _net(_db.from('plans').insert({
                'chat_id': widget.chatId,
                'kind': 'story',
                'title': '${lines.first['t']}'.substring(0, math.min(60, '${lines.first['t']}'.length)),
                'data': {'lines': lines},
              }));
              if (context.mounted) _toast(context, 'انحفظت القصة بالذكريات.');
            } catch (_) {}
          }

          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              Expanded(
                child: ListView(children: [
                  for (final l in lines)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text('${l['t']}',
                          style: TextStyle(
                              fontSize: _Fs.titleL,
                              height: 1.7,
                              color: l['by'] == -1
                                  ? const Color(0xFFFFD60A)
                                  : (l['by'] == me ? const Color(0xFF7FB8FF) : const Color(0xFFFF9FC8)))),
                    ),
                ]),
              ),
              if (st['status'] == 'done')
                const Text('انتهت القصة ✨', style: TextStyle(fontSize: _Fs.title))
              else ...[
                Text(myTurn ? 'دورك تكمّل' : 'دور الطرف الثاني', style: const TextStyle(fontWeight: FontWeight.w700)),
                if (myTurn)
                  Row(children: [
                    Expanded(child: TextField(controller: _c, maxLength: 140, decoration: const InputDecoration(hintText: 'كمّل بجملة...'))),
                    IconButton(onPressed: () => unawaited(add()), icon: const Icon(Icons.send_rounded)),
                  ]),
                if (lines.length >= 6) TextButton(onPressed: () => unawaited(finish()), child: const Text('أنهِ القصة واحفظها')),
              ],
            ]),
          );
        },
      );
}

// ======================= لوحة الرسم المشتركة =======================

class _CanvasPainter extends CustomPainter {
  _CanvasPainter(this.strokes, this.live);
  final List<Map<String, dynamic>> strokes;
  final Map<String, dynamic>? live;

  @override
  void paint(Canvas canvas, Size size) {
    void draw(Map<String, dynamic> s) {
      final pts = [for (final e in (s['p'] as List)) (e as num).toDouble()];
      if (pts.length < 2) return;
      final paint = Paint()
        ..color = Color((s['c'] as num).toInt())
        ..strokeWidth = (s['w'] as num).toDouble()
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;
      if (pts.length == 2) {
        paint.style = PaintingStyle.fill;
        canvas.drawCircle(Offset(pts[0] * size.width, pts[1] * size.height), paint.strokeWidth / 2, paint);
        return;
      }
      final path = Path()..moveTo(pts[0] * size.width, pts[1] * size.height);
      for (var i = 2; i + 1 < pts.length; i += 2) {
        path.lineTo(pts[i] * size.width, pts[i + 1] * size.height);
      }
      canvas.drawPath(path, paint);
    }

    for (final s in strokes) {
      draw(s);
    }
    if (live != null) draw(live!);
  }

  @override
  bool shouldRepaint(covariant _CanvasPainter old) => true;
}

class SharedCanvasScreen extends StatefulWidget {
  const SharedCanvasScreen({super.key, required this.chatId});
  final String chatId;

  @override
  State<SharedCanvasScreen> createState() => _SharedCanvasState();
}

class _SharedCanvasState extends State<SharedCanvasScreen> {
  int _color = 0xFFFFFFFF;
  double _width = 5;
  final List<double> _cur = [];
  Size _size = Size.zero;
  int _tick = 0;

  static const _palette = [0xFFFFFFFF, 0xFFFF5F57, 0xFFFFD60A, 0xFF34C759, 0xFF0A84FF, 0xFFBF5AF2, 0xFFFF9FC8];

  @override
  Widget build(BuildContext context) => _GameFrame(
        title: 'لوحة الرسم',
        chatId: widget.chatId,
        kind: 'canvas',
        intro: 'لوحة بيضاء ترسمون عليها سوا بنفس اللحظة.',
        start: () => unawaited(_g4New(context, widget.chatId, 'canvas', {'strokes': <Map<String, dynamic>>[], 'status': 'open'})),
        body: (row, st) {
          final strokes = [for (final e in (st['strokes'] as List)) Map<String, dynamic>.from(e as Map)];
          Future<void> commit() async {
            if (_cur.length < 2) return;
            final pts = List<double>.from(_cur);
            _cur.clear();
            // نخفف النقاط: نقطة من كل 2
            final slim = <double>[];
            for (var i = 0; i + 1 < pts.length; i += 4) {
              slim
                ..add(double.parse(pts[i].toStringAsFixed(3)))
                ..add(double.parse(pts[i + 1].toStringAsFixed(3)));
            }
            if (pts.length >= 4) {
              final lx = double.parse(pts[pts.length - 2].toStringAsFixed(3));
              final ly = double.parse(pts[pts.length - 1].toStringAsFixed(3));
              if (slim.length < 2 || slim[slim.length - 2] != lx || slim[slim.length - 1] != ly) slim.addAll([lx, ly]);
            }
            if (pts.length >= 2 && slim.length < 2) {
              slim
                ..clear()
                ..addAll([pts[0], pts[1]]);
            }
            final stroke = {'c': _color, 'w': _width, 'p': slim};
            await _g4Step(context, row['id'] as Object, (s) {
              final ls = [for (final e in (s['strokes'] as List)) Map<String, dynamic>.from(e as Map)];
              ls.add(stroke);
              if (ls.length > 250) ls.removeRange(0, ls.length - 250);
              s['strokes'] = ls;
              return s;
            });
            if (mounted) setState(() => _tick++);
          }

          return Padding(
            padding: const EdgeInsets.all(12),
            child: Column(children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(color: const Color(0xFF1B1B26), borderRadius: BorderRadius.circular(18)),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: LayoutBuilder(builder: (ctx, box) {
                      _size = Size(box.maxWidth, box.maxHeight);
                      return GestureDetector(
                        onPanStart: (d) => setState(() {
                          _cur
                            ..clear()
                            ..addAll([d.localPosition.dx / _size.width, d.localPosition.dy / _size.height]);
                        }),
                        onPanUpdate: (d) => setState(() {
                          _cur.addAll([
                            (d.localPosition.dx / _size.width).clamp(0, 1).toDouble(),
                            (d.localPosition.dy / _size.height).clamp(0, 1).toDouble(),
                          ]);
                        }),
                        onPanEnd: (_) => unawaited(commit()),
                        onTapUp: (d) {
                          _cur
                            ..clear()
                            ..addAll([d.localPosition.dx / _size.width, d.localPosition.dy / _size.height]);
                          unawaited(commit());
                        },
                        child: CustomPaint(
                          painter: _CanvasPainter(strokes, _cur.length >= 2 ? {'c': _color, 'w': _width, 'p': List<double>.from(_cur)} : null),
                          size: Size.infinite,
                          key: ValueKey(_tick),
                        ),
                      );
                    }),
                  ),
                ),
              ),
              const SizedBox(height: _Sp.sm),
              Row(children: [
                for (final c in _palette)
                  GestureDetector(
                    onTap: () => setState(() => _color = c),
                    child: Container(
                      width: 28,
                      height: 28,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                          color: Color(c),
                          shape: BoxShape.circle,
                          border: Border.all(color: _color == c ? Colors.white : Colors.transparent, width: 2.5)),
                    ),
                  ),
                Expanded(child: Slider(min: 2, max: 16, value: _width, onChanged: (v) => setState(() => _width = v))),
                IconButton(
                    tooltip: 'امسح اللوحة',
                    onPressed: () => unawaited(_g4Step(context, row['id'] as Object, (s) {
                          s['strokes'] = <Map<String, dynamic>>[];
                          return s;
                        })),
                    icon: const Icon(Icons.delete_sweep_rounded)),
              ]),
            ]),
          );
        },
      );
}

// ======================= بينغو الثنائي =======================

const _bingoIdeas = [
  'شاهدنا فيلم سوا', 'طبخنا أكلة جديدة', 'مشينا بالمطر', 'أرسلنا رسالة صوتية طويلة', 'لعبنا لعبة كاملة',
  'تكلمنا مكالمة أكثر من ساعة', 'شفنا غروب الشمس', 'ضحكنا لين دمعت عيوننا', 'جربنا مطعم جديد', 'كتبنا لبعض رسالة حب',
  'سمعنا نفس الأغنية', 'تصورنا سيلفي', 'خططنا لسفرة', 'قلنا «اشتقت لك» بدون سبب', 'سهرنا للفجر',
  'شربنا قهوة سوا (حتى عن بُعد)', 'ضحّكنا بعض بنكتة', 'حلينا لغز سوا', 'تذكّرنا أول يوم تعارفنا', 'أرسلنا هدية صغيرة',
  'تكلمنا عن حلم', 'اعتذرنا عن شي', 'سوّينا تحدي', 'قرأنا شي سوا', 'غنّينا لبعض',
  'ودّينا بعض صباح الخير بدري', 'مدحنا بعض', 'سألنا أسئلة تعارف', 'رتبنا صور الذكريات', 'ضفنا موعد بالتقويم',
  'تمشّينا (كل واحد بمكانه) ونحنا بالمكالمة', 'جربنا شي أول مرة', 'شفنا النجوم', 'ساعدنا بعض بشي', 'نمنا والمكالمة مفتوحة',
];

class BingoScreen extends StatelessWidget {
  const BingoScreen({super.key, required this.chatId});
  final String chatId;

  int _lines(List<bool> d) {
    var n = 0;
    for (var i = 0; i < 5; i++) {
      if (List.generate(5, (j) => d[i * 5 + j]).every((x) => x)) n++;
      if (List.generate(5, (j) => d[j * 5 + i]).every((x) => x)) n++;
    }
    if (List.generate(5, (j) => d[j * 6]).every((x) => x)) n++;
    if (List.generate(5, (j) => d[(j + 1) * 4]).every((x) => x)) n++;
    return n;
  }

  @override
  Widget build(BuildContext context) => _GameFrame(
        title: 'بينغو الثنائي',
        chatId: chatId,
        kind: 'bingo',
        intro: 'شبكة 25 نشاط لطيف. علّموا اللي سويتوه، وحاولوا تكملون خط كامل.',
        start: () {
          final pool = [..._bingoIdeas]..shuffle();
          unawaited(_g4New(context, chatId, 'bingo', {'cells': pool.take(25).toList(), 'done': List<bool>.filled(25, false)}));
        },
        body: (row, st) {
          final cells = [for (final e in (st['cells'] as List)) '$e'];
          final done = [for (final e in (st['done'] as List)) e == true];
          final n = _lines(done);
          return Padding(
            padding: const EdgeInsets.all(12),
            child: Column(children: [
              Text(n == 0 ? 'ما اكتمل خط بعد' : 'اكتمل ${_Fmt.digits('$n')} خط 🎉', style: const TextStyle(fontSize: _Fs.title, fontWeight: FontWeight.w700)),
              const SizedBox(height: _Sp.sm),
              Expanded(
                child: GridView.count(
                  crossAxisCount: 5,
                  mainAxisSpacing: 4,
                  crossAxisSpacing: 4,
                  children: [
                    for (var i = 0; i < 25; i++)
                      GestureDetector(
                        onTap: () => unawaited(_g4Step(context, row['id'] as Object, (s) {
                          final d = [for (final e in (s['done'] as List)) e == true];
                          d[i] = !d[i];
                          s['done'] = d;
                          return s;
                        })),
                        child: Container(
                          padding: const EdgeInsets.all(3),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                              color: done[i] ? const Color(0xAA34C759) : const Color(0x26FFFFFF),
                              borderRadius: BorderRadius.circular(8)),
                          child: Text(cells[i],
                              textAlign: TextAlign.center,
                              maxLines: 4,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 9.5, height: 1.2)),
                        ),
                      ),
                  ],
                ),
              ),
            ]),
          );
        },
      );
}

// ======================= تحدي الأسبوع =======================

const _weeklyIdeas = [
  'اكتبوا لبعض رسالة حب بدون ما تستخدمون كلمة «أحبك»',
  'العبوا 3 ألعاب مختلفة وسجّلوا النتائج',
  'خذوا صورة كل يوم لشي أعجبكم وأرسلوها',
  'اسمعوا أغنية كل يوم يختارها واحد منكم',
  'اتصلوا فيديو مرتين وسوّوا شي سوا (طبخ، رسم، مشي)',
  'اكتبوا كل يوم شي ممتنين له بالطرف الثاني',
  'سوّوا مسابقة معلومات عامة بينكم',
  'خططوا لموعدكم الجاي بالتفصيل',
  'تبادلوا ثلاث ذكريات حلوة كل واحد',
  'جربوا وصفة جديدة كل واحد بمكانه وقارنوا',
];

class WeeklyChallengeScreen extends StatelessWidget {
  const WeeklyChallengeScreen({super.key, required this.chatId});
  final String chatId;

  @override
  Widget build(BuildContext context) {
    final week = _weekId();
    final idea = _weeklyIdeas[(DateTime.now().difference(DateTime(2026, 1, 1)).inDays ~/ 7) % _weeklyIdeas.length];
    return _GameFrame(
      title: 'تحدي الأسبوع',
      chatId: chatId,
      kind: 'weekly',
      intro: 'تحدي جديد كل أسبوع، وتسجلون النتيجة.',
      start: () => unawaited(_g4New(context, chatId, 'weekly', {'week': week, 'idea': idea, 'done': <String, dynamic>{}, 'notes': <String, dynamic>{}})),
      body: (row, st) {
        final id = row['id'] as Object;
        final done = Map<String, dynamic>.from((st['done'] as Map?) ?? {});
        final notes = Map<String, dynamic>.from((st['notes'] as Map?) ?? {});
        final mineDone = done[_meId] == true;
        return ListView(padding: const EdgeInsets.all(20), children: [
          Glass(
            radius: 28,
            padding: const EdgeInsets.all(22),
            child: Column(children: [
              const Text('🏁 تحدي هالأسبوع', style: TextStyle(fontSize: _Fs.titleL, fontWeight: FontWeight.w700)),
              const SizedBox(height: _Sp.md),
              Text('${st['idea']}', textAlign: TextAlign.center, style: const TextStyle(fontSize: _Fs.heading, height: 1.6)),
            ]),
          ),
          const SizedBox(height: _Sp.lg),
          Text('أنجزه: ${_Fmt.digits('${done.values.where((v) => v == true).length}')} من ${_Fmt.digits('2')}',
              textAlign: TextAlign.center, style: const TextStyle(fontSize: _Fs.title)),
          const SizedBox(height: _Sp.md),
          if (!mineDone)
            _Btn(
                label: 'أنجزته ✅',
                onTap: () async {
                  final c = TextEditingController();
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('شلون كان؟'),
                      content: TextField(controller: c, maxLength: 120, decoration: const InputDecoration(hintText: 'ملاحظة (اختياري)')),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
                        TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('تم')),
                      ],
                    ),
                  );
                  final t = c.text.trim();
                  c.dispose();
                  if (ok != true || !context.mounted) return;
                  await _g4Step(context, id, (s) {
                    final d = Map<String, dynamic>.from((s['done'] as Map?) ?? {});
                    final n = Map<String, dynamic>.from((s['notes'] as Map?) ?? {});
                    d[_meId] = true;
                    if (t.isNotEmpty) n[_meId] = t;
                    s['done'] = d;
                    s['notes'] = n;
                    return s;
                  });
                })
          else
            const Text('سجّلت إنجازك 👏', textAlign: TextAlign.center),
          const SizedBox(height: _Sp.lg),
          for (final e in notes.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: _Sp.sm),
              child: Glass(radius: 18, shadow: false, child: Text('${e.key == _meId ? 'أنا' : 'هو'}: ${e.value}')),
            ),
        ]);
      },
    );
  }
}

List<_MenuItem> _r2GameItems(BuildContext context, String chatId) {
  void push(Widget w) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => w));
  return [
    (Icons.grid_on_rounded, 'أربعة بالصف', 'اجمع أربع قطع بالصف', () => push(Connect4Screen(chatId: chatId))),
    (Icons.directions_boat_rounded, 'حرب السفن', 'لوحتين مخفيتين', () => push(BattleshipScreen(chatId: chatId))),
    (Icons.spellcheck_rounded, 'كلمة اليوم', 'خمّنوا نفس الكلمة بست محاولات', () => push(WordleScreen(chatId: chatId))),
    (Icons.record_voice_over_rounded, 'من قال؟', 'عبارات من رسائلكم (بموافقتكم)', () => push(WhoSaidScreen(chatId: chatId))),
    (Icons.local_fire_department_rounded, 'صراحة وجرأة', 'ثلاث مستويات', () => push(TruthDareScreen(chatId: chatId))),
    (Icons.link_rounded, 'سلسلة الكلمات', 'آخر حرف هو أول حرف', () => push(WordChainScreen(chatId: chatId))),
    (Icons.menu_book_rounded, 'كمّل القصة', 'جملة لكل واحد', () => push(StoryGameScreen(chatId: chatId))),
    (Icons.brush_rounded, 'لوحة الرسم المشتركة', 'ارسموا سوا بنفس اللحظة', () => push(SharedCanvasScreen(chatId: chatId))),
    (Icons.apps_rounded, 'بينغو الثنائي', '25 نشاط لطيف', () => push(BingoScreen(chatId: chatId))),
    (Icons.emoji_events_rounded, 'تحدي الأسبوع', 'تحدي جديد كل أسبوع', () => push(WeeklyChallengeScreen(chatId: chatId))),
  ];
}
