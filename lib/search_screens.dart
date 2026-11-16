part of 'main.dart';

// ---------- بحث داخل المحادثة (يبحث بكل الرسائل النصية، مو بس المحمّلة) ----------

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key, required this.chatId});
  final String chatId;

  @override
  State<SearchScreen> createState() => _SearchState();
}

class _SearchState extends State<SearchScreen> {
  final _c = TextEditingController();
  Timer? _timer;
  List<Map<String, dynamic>> _results = [];
  bool _busy = false;
  bool _failed = false;
  String _last = '';

  String get _me => _db.auth.currentUser?.id ?? '';

  @override
  void dispose() {
    _timer?.cancel();
    _c.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 400), () => _search(v));
  }

  Future<void> _search(String q) async {
    final term = q.trim();
    _last = term;
    if (term.isEmpty) {
      setState(() {
        _results = [];
        _busy = false;
        _failed = false;
      });
      return;
    }
    setState(() {
      _busy = true;
      _failed = false;
    });
    // نهرب من الرموز اللي لها معنى خاص بالبحث
    final esc = term
        .replaceAll('\\', '\\\\')
        .replaceAll('%', '\\%')
        .replaceAll('_', '\\_');
    try {
      final r = await _db
          .from('messages')
          .select('id,body,sender_id,created_at')
          .eq('chat_id', widget.chatId)
          .eq('kind', 'text')
          .ilike('body', '%$esc%')
          .order('id', ascending: false)
          .limit(50);
      if (!mounted || _last != term) return;
      setState(() {
        _results = List<Map<String, dynamic>>.from(r);
        _busy = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _failed = true;
      });
    }
  }

  String _fmt(String? iso) {
    final d = DateTime.tryParse(iso ?? '')?.toLocal();
    if (d == null) return '';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)} ${two(d.hour)}:${two(d.minute)}';
  }

  Widget _body() {
    if (_failed) {
      return const Center(child: Text('تعذر البحث، جرّب مرة ثانية.'));
    }
    if (_busy) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_last.isEmpty) {
      return const Center(
        child: Text('اكتب كلمة للبحث',
            style: TextStyle(color: Color(0xAAFFFFFF))),
      );
    }
    if (_results.isEmpty) {
      return const Center(child: Text('ما لقينا شي'));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _results.length,
      itemBuilder: (_, i) {
        final m = _results[i];
        final mine = m['sender_id'] == _me;
        final body = (m['body'] ?? '') as String;
        return ListTile(
          title: Text.rich(_highlight(body, _last),
              maxLines: 2, overflow: TextOverflow.ellipsis),
          subtitle: Text(
              '${mine ? 'أنت' : 'الطرف الثاني'} · ${_fmt(m['created_at'] as String?)}',
              style: const TextStyle(fontSize: 12, color: Color(0x99FFFFFF))),
          onTap: () => showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            builder: (_) => _SearchContext(
                chatId: widget.chatId,
                id: (m['id'] as num).toInt(),
                term: _last),
          ),
        );
      },
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
                      icon: const Icon(Icons.arrow_back_rounded)),
                  Expanded(
                    child: Glass(
                      radius: 24,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: TextField(
                        controller: _c,
                        autofocus: true,
                        textInputAction: TextInputAction.search,
                        onChanged: _onChanged,
                        onSubmitted: (v) => _search(v),
                        decoration: const InputDecoration(
                          hintText: 'ابحث في الرسائل',
                          border: InputBorder.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ]),
              ),
              Expanded(child: _body()),
            ]),
          ),
        ),
      );
}

/// يظلّل الكلمة اللي تبحث عنها داخل النص
TextSpan _highlight(String text, String term) {
  final t = term.trim();
  if (t.isEmpty) return TextSpan(text: text);
  final low = text.toLowerCase(), q = t.toLowerCase();
  final spans = <TextSpan>[];
  var i = 0;
  while (true) {
    final j = low.indexOf(q, i);
    if (j < 0) {
      spans.add(TextSpan(text: text.substring(i)));
      break;
    }
    if (j > i) spans.add(TextSpan(text: text.substring(i, j)));
    spans.add(TextSpan(
      text: text.substring(j, j + q.length),
      style: const TextStyle(
          backgroundColor: Color(0x88FFD60A),
          fontWeight: FontWeight.w700,
          color: Colors.white),
    ));
    i = j + q.length;
  }
  return TextSpan(children: spans);
}

/// الرسالة مع اللي قبلها واللي بعدها، حتى تفهم سياقها
class _SearchContext extends StatefulWidget {
  const _SearchContext(
      {required this.chatId, required this.id, required this.term});
  final String chatId;
  final int id;
  final String term;

  @override
  State<_SearchContext> createState() => _SearchContextState();
}

class _SearchContextState extends State<_SearchContext> {
  List<Map<String, dynamic>>? _rows;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    const cols = 'id,body,kind,sender_id,created_at';
    try {
      final before = await _db
          .from('messages')
          .select(cols)
          .eq('chat_id', widget.chatId)
          .lte('id', widget.id)
          .order('id', ascending: false)
          .limit(5);
      final after = await _db
          .from('messages')
          .select(cols)
          .eq('chat_id', widget.chatId)
          .gt('id', widget.id)
          .order('id', ascending: true)
          .limit(4);
      if (!mounted) return;
      setState(() => _rows = [
            ...List<Map<String, dynamic>>.from(before).reversed,
            ...List<Map<String, dynamic>>.from(after),
          ]);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  String _label(Map<String, dynamic> r) {
    switch (r['kind']) {
      case 'image':
        return '📷 صورة';
      case 'video':
        return '🎬 فيديو';
      case 'audio':
        return '🎤 رسالة صوتية';
      case 'call':
        return '📞 ${r['body'] ?? 'مكالمة'}';
      default:
        return (r['body'] as String?) ?? '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = _db.auth.currentUser?.id;
    final rows = _rows;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.75),
        child: _failed
            ? const Padding(
                padding: EdgeInsets.all(32),
                child: Text('تعذر تحميل السياق.', textAlign: TextAlign.center))
            : rows == null
                ? const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: CircularProgressIndicator()))
                : ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                    children: [
                      for (final r in rows)
                        Align(
                          alignment: r['sender_id'] == me
                              ? AlignmentDirectional.centerStart
                              : AlignmentDirectional.centerEnd,
                          child: Container(
                            margin: const EdgeInsets.symmetric(vertical: 3),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            constraints: BoxConstraints(
                                maxWidth:
                                    MediaQuery.sizeOf(context).width * 0.75),
                            decoration: BoxDecoration(
                              color: (r['id'] as num).toInt() == widget.id
                                  ? const Color(0x66FFD60A)
                                  : r['sender_id'] == me
                                      ? const Color(0x550A84FF)
                                      : const Color(0x22FFFFFF),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: const Color(0x33FFFFFF)),
                            ),
                            child: (r['id'] as num).toInt() == widget.id
                                ? SelectableText.rich(
                                    _highlight(_label(r), widget.term))
                                : Text(_label(r)),
                          ),
                        ),
                    ],
                  ),
      ),
    );
  }
}
