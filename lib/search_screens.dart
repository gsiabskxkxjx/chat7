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
          title: Text(body, maxLines: 2, overflow: TextOverflow.ellipsis),
          subtitle: Text(
              '${mine ? 'أنت' : 'الطرف الثاني'} · ${_fmt(m['created_at'] as String?)}',
              style: const TextStyle(fontSize: 12, color: Color(0x99FFFFFF))),
          onTap: () => showDialog<void>(
            context: context,
            builder: (ctx) => AlertDialog(
              content: SelectableText(body),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('إغلاق')),
              ],
            ),
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
                      icon: const Icon(Icons.arrow_back)),
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
