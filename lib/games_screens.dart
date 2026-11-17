part of 'main.dart';

// ---------- لعبة إكس أو بين الطرفين ----------
// الحالة كلها بجدول chat_games: اللوحة، من بدأ (x)، دور مين (next)، والحالة (playing/won/draw)

const _ticLines = [
  [0, 1, 2], [3, 4, 5], [6, 7, 8],
  [0, 3, 6], [1, 4, 7], [2, 5, 8],
  [0, 4, 8], [2, 4, 6],
];

String? _ticWinner(List<String> b) {
  for (final l in _ticLines) {
    if (b[l[0]].isNotEmpty && b[l[0]] == b[l[1]] && b[l[1]] == b[l[2]]) {
      return b[l[0]];
    }
  }
  return null;
}

class TicTacToeScreen extends StatefulWidget {
  const TicTacToeScreen({super.key, required this.chatId});
  final String chatId;

  @override
  State<TicTacToeScreen> createState() => _TicState();
}

class _TicState extends State<TicTacToeScreen> {
  late final Stream<List<Map<String, dynamic>>> _stream = _db
      .from('chat_games')
      .stream(primaryKey: ['id'])
      .eq('chat_id', widget.chatId)
      .order('id', ascending: false)
      .limit(10);

  String get _me => _db.auth.currentUser?.id ?? '';

  Future<void> _newGame() async {
    try {
      await _db.from('chat_games').insert({
        'chat_id': widget.chatId,
        'kind': 'tictactoe',
        'turn': _me,
        'state': {
          'board': List<String>.filled(9, ''),
          'x': _me,
          'next': 'x',
          'status': 'playing',
        },
      });
    } catch (_) {
      if (mounted) _toast(context, 'تعذر بدء اللعبة، جرّب مرة ثانية.');
    }
  }

  Future<void> _move(Map<String, dynamic> cur, Map<String, dynamic> st,
      List<String> board, String mySym, int i) async {
    if (st['status'] != 'playing' || st['next'] != mySym || board[i] != '') {
      return;
    }
    board[i] = mySym;
    final win = _ticWinner(board);
    final status = win != null
        ? 'won'
        : (board.contains('') ? 'playing' : 'draw');
    try {
      await _db.from('chat_games').update({
        'state': {
          'board': board,
          'x': st['x'],
          'next': mySym == 'x' ? 'o' : 'x',
          'status': status,
          'by': win != null ? mySym : null,
        },
        'winner': status == 'won' ? _me : null,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', cur['id']);
    } catch (_) {
      if (mounted) _toast(context, 'تعذر تسجيل الحركة، جرّب مرة ثانية.');
    }
  }

  Widget _cell(String v, bool canTap, VoidCallback onTap) => GestureDetector(
        onTap: canTap ? onTap : null,
        child: Container(
          margin: const EdgeInsets.all(_Sp.xs),
          decoration: BoxDecoration(
            color: const Color(0x22FFFFFF),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(
            child: Text(
              v == 'x' ? '✕' : (v == 'o' ? '◯' : ''),
              style: TextStyle(
                fontSize: 44,
                fontWeight: FontWeight.w700,
                color: v == 'x'
                    ? const Color(0xFF64B5F6)
                    : const Color(0xFFFFB74D),
              ),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Backdrop(
          child: SafeArea(
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                child: Row(children: [
                  IconButton(
                      tooltip: 'رجوع',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.arrow_back_rounded)),
                  const Text('إكس أو',
                      style:
                          TextStyle(fontSize: _Fs.display, fontWeight: FontWeight.w700)),
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
                      if (r['kind'] == 'tictactoe') {
                        cur = r;
                        break;
                      }
                    }
                    if (cur == null) {
                      return Center(
                        child: _Btn(
                            label: 'ابدأ لعبة جديدة',
                            onTap: _newGame,
                            busy: false),
                      );
                    }
                    final st = Map<String, dynamic>.from(cur['state'] as Map);
                    final board = List<String>.from(st['board'] as List);
                    final mySym = st['x'] == _me ? 'x' : 'o';
                    final status = (st['status'] ?? 'playing') as String;
                    final myTurn = status == 'playing' && st['next'] == mySym;

                    final String msg;
                    if (status == 'won') {
                      msg = st['by'] == mySym ? 'فزت! 🎉' : 'الطرف الثاني فاز';
                    } else if (status == 'draw') {
                      msg = 'تعادل';
                    } else {
                      msg = myTurn ? 'دورك' : 'دور الطرف الثاني';
                    }

                    return Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(children: [
                        Text(msg,
                            style: const TextStyle(
                                fontSize: _Fs.heading, fontWeight: FontWeight.w600)),
                        const SizedBox(height: _Sp.lg),
                        AspectRatio(
                          aspectRatio: 1,
                          child: GridView.count(
                            crossAxisCount: 3,
                            physics: const NeverScrollableScrollPhysics(),
                            children: [
                              for (var i = 0; i < 9; i++)
                                _cell(board[i], myTurn && board[i] == '',
                                    () => _move(cur!, st, board, mySym, i)),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        if (status != 'playing')
                          _Btn(
                              label: 'لعبة جديدة',
                              onTap: _newGame,
                              busy: false),
                      ]),
                    );
                  },
                ),
              ),
            ]),
          ),
        ),
      );
}

// ---------- قائمة الألعاب ----------

/// عنصر بقائمة "المزيد"
typedef _MenuItem = (IconData icon, String title, String sub, void Function() run);

void showGamesMenu(BuildContext context, String chatId) {
  void push(Widget Function() page) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => page()));

  final tabs = <(String, List<_MenuItem>)>[
    ('🎮 العبوا', [
      (Icons.people_alt_rounded, 'مين فينا؟', 'أنا ولا هو؟ وشوفوا كم اتفقتوا', () => push(() => WhoOfUsScreen(chatId: chatId))),
      (Icons.quiz_rounded, 'كم تعرفني؟', 'أسئلة جديدة كل أسبوع', () => push(() => QuizScreen(chatId: chatId))),
      (Icons.fact_check_rounded, 'صح أو غلط عني', '3 جمل عنك، وهو يخمّن', () => push(() => TrueFalseScreen(chatId: chatId))),
      (Icons.emoji_emotions_rounded, 'خمّن من الإيموجي', 'أفلام وأماكن وأمثال', () => push(() => EmojiGuessScreen(chatId: chatId))),
      (Icons.psychology_alt_rounded, '20 سؤال', 'فكّر بشي وهو يخمّن', () => push(() => TwentyQScreen(chatId: chatId))),
      (Icons.draw_rounded, 'ارسم وخمّن', 'ترسم كلمة سرية وهو يخمّن بالمحادثة', () => unawaited(_drawAndGuess(context, chatId))),
      (Icons.grid_view_rounded, 'لعبة الذاكرة', 'اقلبوا البطاقات بالدور', () => push(() => MemoryGameScreen(chatId: chatId))),
      (Icons.tag_rounded, 'إكس أو', 'كلاسيكية سريعة', () => push(() => TicTacToeScreen(chatId: chatId))),
      (Icons.pan_tool_rounded, 'حجر ورقة مقص', 'كل واحد يختار سراً', () => push(() => RpsScreen(chatId: chatId))),
      (Icons.blur_circular_rounded, 'داما', 'الأكل إجباري، والملك يمشي بكل الاتجاهات', () => push(() => CheckersScreen(chatId: chatId))),
      (Icons.castle_rounded, 'شطرنج', 'شطرنج كامل بالدور', () => push(() => ChessScreen(chatId: chatId))),
      (Icons.leaderboard_rounded, 'نتائجنا وشاراتنا', 'النقاط والإنجازات', () => push(() => ScoresScreen(chatId: chatId))),
    ]),
    ('💞 سوا', [
      (Icons.push_pin_rounded, 'جدار الحب', 'ملاحظات قصيرة تبقى لبعض', () => push(() => LoveNotesScreen(chatId: chatId))),
      (Icons.photo_camera_front_rounded, 'تحدي الصورة اليومي', 'الصورتين تنكشف لما الاثنين يصوّرون', () => push(() => PhotoChallengeScreen(chatId: chatId))),
      (Icons.flag_rounded, 'تحدي 30 يوم', 'مهمة صغيرة كل يوم لكم الاثنين', () => unawaited(_start30Day(context, chatId))),
      (Icons.spa_rounded, 'تذكير لطيف', 'اشرب ماي، نام بدري، لا تنسى تاكل...', () => unawaited(_sendGentle(context, chatId))),
      (Icons.calendar_month_rounded, 'تقويمنا', 'المواعيد المهمة لكم الاثنين', () => push(() => CalendarScreen(chatId: chatId))),
      (Icons.hourglass_top_rounded, 'عدّ تنازلي لموعد', 'يظهر بأعلى المحادثة', () => unawaited(_setCountdown(context, chatId))),
      (Icons.checklist_rounded, 'قوايم مشتركة', 'أمنيات، أماكن، أفلام، أهداف', () => push(() => SharedListsScreen(chatId: chatId))),
      (Icons.menu_book_rounded, 'يومياتنا', 'كل واحد يكتب يومه والثاني يقراه', () => push(() => DiaryScreen(chatId: chatId))),
      (Icons.account_balance_wallet_rounded, 'ميزانيتنا', 'مصاريف مشتركة ومين دفع', () => push(() => BudgetScreen(chatId: chatId))),
      (Icons.casino_rounded, 'عجلة القرار', 'وين نطلع؟ شنو ناكل؟', () => push(() => DecisionWheelScreen(chatId: chatId))),
    ]),
    ('📸 ذكرياتنا', [
      (Icons.timeline_rounded, 'قصتنا', 'أول رسالة، أول صورة، أول مكالمة...', () => push(() => StoryScreen(chatId: chatId))),
      (Icons.photo_library_rounded, 'معرض الذكريات والألبومات', 'كل صوركم وفيديوهاتكم', () => push(() => MemoriesScreen(chatId: chatId))),
      (Icons.auto_graph_rounded, 'ملخصنا', 'بطاقة الشهر أو السنة، تنحفظ كصورة', () => push(() => SummaryScreen(chatId: chatId))),
      (Icons.star_rounded, 'الرسائل المفضلة', 'نصوص وصور وصوتيات', () => push(() => StarredScreen(chatId: chatId))),
      (Icons.insights_rounded, 'إحصائياتنا', 'كم رسالة وصورة ومكالمة', () => push(() => StatsScreen(chatId: chatId))),
      (Icons.favorite_rounded, 'تاريخ بدايتنا', 'لعدّاد الأيام والاحتفالات', () => unawaited(_setStartDate(context, chatId))),
    ]),
    ('🗓️ خطط', [
      ..._r2PlanItems(context, chatId),
      (Icons.event_repeat_rounded, '365 سؤال', 'سؤال لكل يوم، وأجوبتكم تنحفظ', () => push(() => YearQaScreen(chatId: chatId))),
      (Icons.favorite_border_rounded, 'أسباب حبي لك', 'جمل تنحفظ وتطلع عشوائياً', () => push(() => PlansScreen(chatId: chatId, kind: 'reason'))),
      (Icons.volunteer_activism_rounded, 'أشياء نحبها ببعض', 'تضيفون بالتناوب', () => push(() => PlansScreen(chatId: chatId, kind: 'wish'))),
    ]),
    ('💬 سوالف', [
      (Icons.mail_rounded, 'بطاقات جاهزة', 'صباح الخير، تصبح على خير، تهاني', () => unawaited(showCardsSheet(context, chatId))),
      (Icons.forum_rounded, 'سؤال تعارف', 'أسئلة عميقة على مراحل', () => unawaited(showTalkCards(context, chatId, 'deep'))),
      (Icons.alt_route_rounded, 'لو خيّروك', 'أسئلة جاهزة', () => unawaited(showTalkCards(context, chatId, 'wyr'))),
      (Icons.lightbulb_rounded, 'أفكار للطلعات', 'شي جديد تسوونه سوا', () => unawaited(showTalkCards(context, chatId, 'date'))),
      (Icons.flash_on_rounded, 'ردود سريعة', 'جملك المحفوظة', () => showQuickReplies(context, chatId)),
      (Icons.search_rounded, 'بحث في المحادثة', 'لاقي أي رسالة', () => push(() => SearchScreen(chatId: chatId))),
    ]),
  ];

  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(ctx).height * 0.72,
        child: DefaultTabController(
          length: tabs.length,
          child: Column(children: [
            TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.center,
              dividerColor: Colors.transparent,
              tabs: [for (final t in tabs) Tab(text: t.$1)],
            ),
            Expanded(
              child: TabBarView(children: [
                for (final t in tabs)
                  ListView(padding: const EdgeInsets.symmetric(vertical: 6), children: [
                    for (final it in t.$2)
                      ListTile(
                        leading: Icon(it.$1),
                        title: Text(it.$2),
                        subtitle: Text(it.$3, maxLines: 1, overflow: TextOverflow.ellipsis),
                        onTap: () {
                          Navigator.pop(ctx);
                          it.$4();
                        },
                      ),
                  ]),
              ]),
            ),
          ]),
        ),
      ),
    ),
  );
}

// ---------- حجر ورقة مقص ----------
// كل جولة: كل طرف يختار سراً، والنتيجة تنحسب لما يختار الاثنين.

bool _rpsBeats(String a, String b) =>
    (a == 'rock' && b == 'scissors') ||
    (a == 'scissors' && b == 'paper') ||
    (a == 'paper' && b == 'rock');

String _rpsEmoji(String? c) => switch (c) {
      'rock' => '✊',
      'paper' => '🖐',
      'scissors' => '✌',
      _ => '؟',
    };

class RpsScreen extends StatefulWidget {
  const RpsScreen({super.key, required this.chatId});
  final String chatId;

  @override
  State<RpsScreen> createState() => _RpsState();
}

class _RpsState extends State<RpsScreen> {
  late final Stream<List<Map<String, dynamic>>> _stream = _db
      .from('chat_games')
      .stream(primaryKey: ['id'])
      .eq('chat_id', widget.chatId)
      .order('id', ascending: false)
      .limit(10);

  String get _me => _db.auth.currentUser?.id ?? '';

  Future<void> _newRound() async {
    try {
      await _db.from('chat_games').insert({
        'chat_id': widget.chatId,
        'kind': 'rps',
        'turn': _me,
        'state': {'picks': <String, String>{}, 'status': 'choosing'},
      });
    } catch (_) {
      if (mounted) _toast(context, 'تعذر بدء الجولة، جرّب مرة ثانية.');
    }
  }

  Future<void> _pick(Map<String, dynamic> cur, String choice) async {
    try {
      // نقرأ الحالة الحالية أول، عشان ما نمسح اختيار الطرف الثاني
      final fresh = await _db
          .from('chat_games')
          .select('state')
          .eq('id', cur['id'])
          .single();
      final st = Map<String, dynamic>.from(fresh['state'] as Map);
      final picks = Map<String, dynamic>.from((st['picks'] ?? {}) as Map);
      if (picks.containsKey(_me)) return;
      picks[_me] = choice;

      final done = picks.length >= 2;
      String? result;
      if (done) {
        final ids = picks.keys.toList();
        final a = picks[ids[0]] as String;
        final b = picks[ids[1]] as String;
        result = a == b ? 'draw' : (_rpsBeats(a, b) ? ids[0] : ids[1]);
      }
      await _db.from('chat_games').update({
        'state': {
          'picks': picks,
          'status': done ? 'done' : 'choosing',
          'result': result,
        },
        'winner': (done && result != 'draw') ? result : null,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', cur['id']);
    } catch (_) {
      if (mounted) _toast(context, 'تعذر تسجيل اختيارك، جرّب مرة ثانية.');
    }
  }

  Widget _choiceBtn(String label, String key, VoidCallback onTap) =>
      InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: 96,
          padding: const EdgeInsets.symmetric(vertical: _Sp.lg),
          decoration: BoxDecoration(
            color: const Color(0x22FFFFFF),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(_rpsEmoji(key), style: const TextStyle(fontSize: 34)),
            const SizedBox(height: 6),
            Text(label, style: const TextStyle(fontSize: _Fs.meta)),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Backdrop(
          child: SafeArea(
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                child: Row(children: [
                  IconButton(
                      tooltip: 'رجوع',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.arrow_back_rounded)),
                  const Text('حجر ورقة مقص',
                      style:
                          TextStyle(fontSize: _Fs.display, fontWeight: FontWeight.w700)),
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
                      if (r['kind'] == 'rps') {
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
                    final picks =
                        Map<String, dynamic>.from((st['picks'] ?? {}) as Map);
                    final status = (st['status'] ?? 'choosing') as String;
                    final myPick = picks[_me] as String?;

                    if (status == 'done') {
                      final result = st['result'] as String?;
                      final other = picks.keys.firstWhere((k) => k != _me,
                          orElse: () => '');
                      final String msg = result == 'draw'
                          ? 'تعادل'
                          : (result == _me ? 'فزت! 🎉' : 'الطرف الثاني فاز');
                      return Center(
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          Text(msg,
                              style: const TextStyle(
                                  fontSize: _Fs.display, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 20),
                          Row(mainAxisSize: MainAxisSize.min, children: [
                            Text(_rpsEmoji(myPick),
                                style: const TextStyle(fontSize: 48)),
                            const SizedBox(width: _Sp.xl),
                            const Text('VS', style: TextStyle(fontSize: _Fs.title)),
                            const SizedBox(width: _Sp.xl),
                            Text(_rpsEmoji(other.isEmpty ? null : picks[other] as String?),
                                style: const TextStyle(fontSize: 48)),
                          ]),
                          const SizedBox(height: 28),
                          _Btn(label: 'جولة جديدة', onTap: _newRound, busy: false),
                        ]),
                      );
                    }

                    if (myPick != null) {
                      return const Center(
                        child: Text('اخترت، ننتظر الطرف الثاني...',
                            style: TextStyle(fontSize: _Fs.title)),
                      );
                    }

                    return Center(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        const Text('اختر سراً، والنتيجة تطلع لما يختار الاثنين',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Color(0xAAFFFFFF))),
                        const SizedBox(height: _Sp.xl),
                        Row(mainAxisSize: MainAxisSize.min, children: [
                          _choiceBtn('حجر', 'rock', () => _pick(cur!, 'rock')),
                          const SizedBox(width: _Sp.md),
                          _choiceBtn('ورقة', 'paper', () => _pick(cur!, 'paper')),
                          const SizedBox(width: _Sp.md),
                          _choiceBtn('مقص', 'scissors',
                              () => _pick(cur!, 'scissors')),
                        ]),
                      ]),
                    );
                  },
                ),
              ),
            ]),
          ),
        ),
      );
}
