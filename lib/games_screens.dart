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
          margin: const EdgeInsets.all(4),
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
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.arrow_back)),
                  const Text('إكس أو',
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
                                fontSize: 18, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 16),
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
