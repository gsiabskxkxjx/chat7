part of 'main.dart';

// ---------- كم تعرفني؟ ----------
// كل جولة من 3 مراحل:
// 1) كل طرف يجاوب 5 أسئلة عن نفسه.
// 2) كل طرف يخمّن إجابات الطرف الثاني.
// 3) النقاط = عدد التخمينات الصح من 5.

const _quizQ = <List<String>>[
  ['وش أحب وقت بالأسبوع؟', 'الخميس', 'الجمعة', 'السبت'],
  ['وش أكثر شي تحبه تسويه بوقت فراغك؟', 'أسمع موسيقى', 'أتمشى', 'أنام'],
  ['وش أكثر أكلة تحبها؟', 'برجر', 'شاورما', 'سمك'],
  ['وش لونك المفضل؟', 'أزرق', 'أحمر', 'أخضر'],
  ['وش أكثر شي تضحك عليه؟', 'النكت', 'المواقف', 'الأفلام'],
];

class QuizScreen extends StatefulWidget {
  const QuizScreen({super.key, required this.chatId});
  final String chatId;

  @override
  State<QuizScreen> createState() => _QuizState();
}

class _QuizState extends State<QuizScreen> {
  late final Stream<List<Map<String, dynamic>>> _stream = _db
      .from('chat_games')
      .stream(primaryKey: ['id'])
      .eq('chat_id', widget.chatId)
      .order('id', ascending: false)
      .limit(10);

  // اختياراتي قبل ما أرسلها (تنمسح عند جولة جديدة)
  final List<int?> _sel = List<int?>.filled(_quizQ.length, null);
  final List<int?> _guess = List<int?>.filled(_quizQ.length, null);

  String get _me => _db.auth.currentUser?.id ?? '';

  Future<void> _newRound() async {
    _sel.fillRange(0, _sel.length, null);
    _guess.fillRange(0, _guess.length, null);
    try {
      await _db.from('chat_games').insert({
        'chat_id': widget.chatId,
        'kind': 'quiz',
        'turn': _me,
        'state': {
          'status': 'answering',
          'answers': <String, dynamic>{},
          'guesses': <String, dynamic>{},
        },
      });
    } catch (_) {
      if (mounted) _toast(context, 'تعذر بدء الجولة، جرّب مرة ثانية.');
    }
  }

  Future<Map<String, dynamic>> _fresh(dynamic id) async {
    final r = await _db.from('chat_games').select('state').eq('id', id).single();
    return Map<String, dynamic>.from(r['state'] as Map);
  }

  Future<void> _submitAnswers(Map<String, dynamic> cur) async {
    try {
      final st = await _fresh(cur['id']);
      final answers =
          Map<String, dynamic>.from((st['answers'] ?? {}) as Map);
      if (answers.containsKey(_me)) return;
      answers[_me] = _sel.map((e) => e ?? 0).toList();
      await _db.from('chat_games').update({
        'state': {
          'status': answers.length >= 2 ? 'guessing' : 'answering',
          'answers': answers,
          'guesses': st['guesses'] ?? <String, dynamic>{},
        },
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', cur['id']);
    } catch (_) {
      if (mounted) _toast(context, 'تعذر إرسال إجاباتك، جرّب مرة ثانية.');
    }
  }

  Future<void> _submitGuesses(Map<String, dynamic> cur) async {
    try {
      final st = await _fresh(cur['id']);
      final answers =
          Map<String, dynamic>.from((st['answers'] ?? {}) as Map);
      final guesses =
          Map<String, dynamic>.from((st['guesses'] ?? {}) as Map);
      if (guesses.containsKey(_me)) return;
      guesses[_me] = _guess.map((e) => e ?? 0).toList();

      final done = guesses.length >= 2;
      final score = <String, dynamic>{};
      if (done) {
        for (final uid in guesses.keys) {
          final other = answers.keys.firstWhere((k) => k != uid);
          final real = answers[other] as List;
          final g = guesses[uid] as List;
          var n = 0;
          for (var i = 0; i < _quizQ.length; i++) {
            if (g[i] == real[i]) n++;
          }
          score[uid] = n;
        }
      }
      await _db.from('chat_games').update({
        'state': {
          'status': done ? 'done' : 'guessing',
          'answers': answers,
          'guesses': guesses,
          'score': score,
        },
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', cur['id']);
    } catch (_) {
      if (mounted) _toast(context, 'تعذر إرسال تخمينك، جرّب مرة ثانية.');
    }
  }

  Widget _form(List<int?> pick, String headline, VoidCallback onSubmit) {
    final complete = pick.every((e) => e != null);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(headline,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        const SizedBox(height: 16),
        for (var q = 0; q < _quizQ.length; q++) ...[
          Text(_quizQ[q][0], style: const TextStyle(fontSize: 15)),
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (var o = 1; o < _quizQ[q].length; o++)
              ChoiceChip(
                label: Text(_quizQ[q][o]),
                selected: pick[q] == o - 1,
                onSelected: (_) => setState(() => pick[q] = o - 1),
              ),
          ]),
          const SizedBox(height: 14),
        ],
        const SizedBox(height: 8),
        Center(
          child: _Btn(
              label: 'أرسل',
              onTap: () async {
                if (complete) onSubmit();
              },
              busy: false),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Backdrop(
          child: SafeArea(
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                child: Row(children: [
                  IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.arrow_back)),
                  const Text('كم تعرفني؟',
                      style:
                          TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                ]),
              ),
              Expanded(
                child: StreamBuilder<List<Map<String, dynamic>>>(
                  stream: _stream,
                  builder: (_, snap) {
                    if (!snap.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    Map<String, dynamic>? cur;
                    for (final r in snap.data!) {
                      if (r['kind'] == 'quiz') {
                        cur = r;
                        break;
                      }
                    }
                    if (cur == null) {
                      return Center(
                          child: _Btn(
                              label: 'ابدأ جولة', onTap: _newRound, busy: false));
                    }
                    final st = Map<String, dynamic>.from(cur['state'] as Map);
                    final status = (st['status'] ?? 'answering') as String;
                    final answers =
                        Map<String, dynamic>.from((st['answers'] ?? {}) as Map);
                    final guesses =
                        Map<String, dynamic>.from((st['guesses'] ?? {}) as Map);

                    if (status == 'done') {
                      final score =
                          Map<String, dynamic>.from((st['score'] ?? {}) as Map);
                      final other = score.keys.firstWhere((k) => k != _me,
                          orElse: () => '');
                      return Center(
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          Text('نتيجتك: ${score[_me] ?? 0} من ${_quizQ.length}',
                              style: const TextStyle(
                                  fontSize: 20, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 8),
                          Text(
                              'نتيجة الطرف الثاني: ${other.isEmpty ? 0 : (score[other] ?? 0)} من ${_quizQ.length}',
                              style: const TextStyle(fontSize: 16)),
                          const SizedBox(height: 24),
                          _Btn(label: 'جولة جديدة', onTap: _newRound, busy: false),
                        ]),
                      );
                    }

                    if (status == 'answering') {
                      if (answers.containsKey(_me)) {
                        return const Center(
                          child: Text('أجبت، ننتظر الطرف الثاني يجاوب...',
                              style: TextStyle(fontSize: 16)),
                        );
                      }
                      return _form(_sel, 'جاوب على أسئلة عن نفسك',
                          () => _submitAnswers(cur!));
                    }

                    // guessing
                    if (guesses.containsKey(_me)) {
                      return const Center(
                        child: Text('خمّنت، ننتظر الطرف الثاني يخمّن...',
                            style: TextStyle(fontSize: 16)),
                      );
                    }
                    return _form(_guess, 'خمّن إجابات الطرف الثاني',
                        () => _submitGuesses(cur!));
                  },
                ),
              ),
            ]),
          ),
        ),
      );
}
