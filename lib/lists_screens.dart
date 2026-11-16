part of 'main.dart';

// ---------- قوايم مشتركة: كل عناصرها تطلع عند الطرفين ----------

const _suggestedLists = [
  'مشتريات',
  'أماكن نبي نزورها',
  'أفلام ومسلسلات',
  'أمنيات الهدايا',
  'أهدافنا',
  'أفكار للطلعات',
];

class SharedListsScreen extends StatefulWidget {
  const SharedListsScreen({super.key, required this.chatId, this.initialList});
  final String chatId;
  final String? initialList;

  @override
  State<SharedListsScreen> createState() => _ListsState();
}

class _ListsState extends State<SharedListsScreen> {
  late final Stream<List<Map<String, dynamic>>> _stream = _db
      .from('shared_items')
      .stream(primaryKey: ['id'])
      .eq('chat_id', widget.chatId)
      .order('id', ascending: true);

  final _input = TextEditingController();
  late String _list = widget.initialList ?? _suggestedLists.first;

  String get _me => _db.auth.currentUser?.id ?? '';

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final t = _input.text.trim();
    if (t.isEmpty) return;
    _input.clear();
    try {
      await _db.from('shared_items').insert({
        'chat_id': widget.chatId,
        'list_name': _list,
        'body': t,
      });
    } catch (_) {
      if (mounted) _toast(context, 'تعذر الإضافة، جرّب مرة ثانية.');
    }
  }

  Future<void> _toggle(Map<String, dynamic> it) async {
    final nowDone = !(it['done'] as bool);
    try {
      await _db.from('shared_items').update({
        'done': nowDone,
        'done_by': nowDone ? _me : null,
      }).eq('id', it['id']);
    } catch (_) {}
  }

  /// تاريخ للبند (يطلع تذكير بالمحادثة يوم الموعد)
  Future<void> _setDue(Map<String, dynamic> it) async {
    final now = DateTime.now();
    final cur = DateTime.tryParse('${it['due_on']}');
    final d = await showDatePicker(
      context: context,
      initialDate: cur ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
      helpText: 'متى؟ (نذكركم بالمحادثة)',
      cancelText: cur == null ? 'إلغاء' : 'بدون تاريخ',
    );
    if (!mounted) return;
    if (d == null && cur == null) return;
    try {
      await _db
          .from('shared_items')
          .update({'due_on': d == null ? null : _dayStr(d)}).eq('id', it['id']);
    } catch (_) {
      if (mounted) _toast(context, 'التواريخ تحتاج تحديث السيرفر (update_4).');
    }
  }

  Future<void> _delete(Map<String, dynamic> it) async {
    try {
      await _db.from('shared_items').delete().eq('id', it['id']);
    } catch (_) {}
  }

  Future<void> _newList() async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('قائمة جديدة'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLength: 30,
          decoration: const InputDecoration(hintText: 'مثل: كتب، هدايا'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('تراجع')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('إنشاء')),
        ],
      ),
    );
    ctrl.dispose();
    if (name != null && name.isNotEmpty) setState(() => _list = name);
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
                      tooltip: 'رجوع',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.arrow_back_rounded)),
                  const Text('قوايم مشتركة',
                      style:
                          TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                ]),
              ),
              Expanded(
                child: StreamBuilder<List<Map<String, dynamic>>>(
                  stream: _stream,
                  builder: (_, snap) {
                    final rows = snap.data ?? const <Map<String, dynamic>>[];
                    final names = <String>{..._suggestedLists, _list};
                    for (final r in rows) {
                      names.add(r['list_name'] as String);
                    }
                    final items =
                        rows.where((r) => r['list_name'] == _list).toList()
                          ..sort((a, b) {
                            // اللي ما خلص أول، وبعدين حسب التاريخ
                            final da = a['done'] == true ? 1 : 0;
                            final db = b['done'] == true ? 1 : 0;
                            if (da != db) return da - db;
                            final xa = '${a['due_on'] ?? '9999'}';
                            final xb = '${b['due_on'] ?? '9999'}';
                            final c = xa.compareTo(xb);
                            return c != 0
                                ? c
                                : (a['id'] as num).compareTo(b['id'] as num);
                          });
                    final doneN = items.where((r) => r['done'] == true).length;

                    return Column(children: [
                      SizedBox(
                        height: 48,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          children: [
                            for (final n in names)
                              Padding(
                                padding: const EdgeInsets.only(left: 8),
                                child: ChoiceChip(
                                  label: Text(n),
                                  selected: n == _list,
                                  onSelected: (_) => setState(() => _list = n),
                                ),
                              ),
                            Padding(
                              padding: const EdgeInsets.only(left: 8),
                              child: ActionChip(
                                label: const Text('+ قائمة'),
                                onPressed: _newList,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (items.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                          child: Row(children: [
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: LinearProgressIndicator(
                                  value: doneN / items.length,
                                  minHeight: 8,
                                  backgroundColor: const Color(0x26FFFFFF),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                                doneN == items.length
                                    ? 'خلّصتوها كلها 🎉'
                                    : '$doneN من ${items.length}',
                                style: const TextStyle(fontSize: 12)),
                          ]),
                        ),
                      Expanded(
                        child: items.isEmpty
                            ? Center(
                                child: Text('ما في عناصر بقائمة $_list بعد\nاضغط مطوّل على أي بند تحط له تاريخ',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                        color: Color(0xAAFFFFFF))))
                            : ListView.builder(
                                padding: const EdgeInsets.all(12),
                                itemCount: items.length,
                                itemBuilder: (_, i) {
                                  final it = items[i];
                                  final done = it['done'] as bool;
                                  final due = DateTime.tryParse('${it['due_on']}');
                                  final late = due != null &&
                                      !done &&
                                      due.isBefore(_today().add(const Duration(days: 1)));
                                  return ListTile(
                                    onTap: () => _toggle(it),
                                    onLongPress: () => _setDue(it),
                                    subtitle: due == null
                                        ? null
                                        : Text(
                                            '📅 ${due.day} ${_months[due.month - 1]}',
                                            style: TextStyle(
                                                fontSize: 12,
                                                color: late
                                                    ? const Color(0xFFFF9F0A)
                                                    : const Color(0xB3FFFFFF))),
                                    leading: Checkbox(
                                        value: done,
                                        onChanged: (_) => _toggle(it)),
                                    title: Text(it['body'] as String,
                                        style: TextStyle(
                                          decoration: done
                                              ? TextDecoration.lineThrough
                                              : null,
                                          color: done
                                              ? const Color(0x88FFFFFF)
                                              : null,
                                        )),
                                    trailing: IconButton(
                                      tooltip: 'حذف',
                                      icon: const Icon(Icons.delete_outline_rounded,
                                          size: 20),
                                      onPressed: () => _delete(it),
                                    ),
                                  );
                                },
                              ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                        child: Glass(
                          radius: 24,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          child: Row(children: [
                            Expanded(
                              child: TextField(
                                controller: _input,
                                textInputAction: TextInputAction.done,
                                onSubmitted: (_) => _add(),
                                decoration: InputDecoration(
                                  hintText: 'أضف عنصر لـ $_list',
                                  border: InputBorder.none,
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: 'إضافة',
                              onPressed: _add,
                              icon: const Icon(Icons.add_circle_outline_rounded),
                            ),
                          ]),
                        ),
                      ),
                    ]);
                  },
                ),
              ),
            ]),
          ),
        ),
      );
}
