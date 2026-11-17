part of 'main.dart';

// ---------- ألبومات الذكريات، الميزانية المشتركة، اليوميات المشتركة ----------

const _needUpdate5 = 'تحتاج تحديث السيرفر (update_5).';

// ===== الألبومات =====

Future<int?> _newAlbum(BuildContext context, String chatId) async {
  final c = TextEditingController();
  final name = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('ألبوم جديد'),
      content: TextField(
        controller: c,
        autofocus: true,
        maxLength: 40,
        decoration: const InputDecoration(hintText: 'مثل: رحلتنا، العيد، أول لقاء'),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
        TextButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('إنشاء')),
      ],
    ),
  );
  c.dispose();
  if (name == null || name.isEmpty) return null;
  try {
    final r = await _db
        .from('albums')
        .insert({'chat_id': chatId, 'title': name})
        .select('id')
        .single();
    return (r['id'] as num).toInt();
  } catch (_) {
    if (context.mounted) _toast(context, 'الألبومات $_needUpdate5');
    return null;
  }
}

/// يضيف صورة/فيديو لألبوم (يختاره أو ينشئ واحد)
Future<void> _addToAlbum(BuildContext context, String chatId, int messageId) async {
  List<Map<String, dynamic>> albums;
  try {
    albums = List<Map<String, dynamic>>.from(await _db
        .from('albums')
        .select('id,title')
        .eq('chat_id', chatId)
        .order('id', ascending: false));
  } catch (_) {
    if (context.mounted) _toast(context, 'الألبومات $_needUpdate5');
    return;
  }
  if (!context.mounted) return;
  final pick = await showModalBottomSheet<int>(
    context: context,
    builder: (ctx) => SafeArea(
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: Text('أضف لألبوم', style: TextStyle(fontSize: _Fs.titleL, fontWeight: FontWeight.w600)),
          ),
          for (final a in albums)
            ListTile(
              leading: const Icon(Icons.photo_album_rounded),
              title: Text('${a['title']}'),
              onTap: () => Navigator.pop(ctx, (a['id'] as num).toInt()),
            ),
          ListTile(
            leading: const Icon(Icons.add_rounded),
            title: const Text('ألبوم جديد'),
            onTap: () => Navigator.pop(ctx, -1),
          ),
        ]),
      ),
    ),
  );
  if (pick == null || !context.mounted) return;
  final id = pick == -1 ? await _newAlbum(context, chatId) : pick;
  if (id == null) return;
  try {
    await _db.from('album_items').upsert({'album_id': id, 'message_id': messageId});
    if (context.mounted) _toast(context, 'انضافت للألبوم');
  } catch (_) {
    if (context.mounted) _toast(context, 'تعذر الإضافة.');
  }
}

class AlbumsScreen extends StatefulWidget {
  const AlbumsScreen({super.key, required this.chatId});
  final String chatId;

  @override
  State<AlbumsScreen> createState() => _AlbumsState();
}

class _AlbumsState extends State<AlbumsScreen> {
  late Future<List<Map<String, dynamic>>> _f = _load();

  Future<List<Map<String, dynamic>>> _load() async => List<Map<String, dynamic>>.from(await _db
      .from('albums')
      .select('id,title,album_items(message_id, messages(media_path,kind))')
      .eq('chat_id', widget.chatId)
      .order('id', ascending: false));

  Future<void> _create() async {
    final id = await _newAlbum(context, widget.chatId);
    if (id != null && mounted) setState(() => _f = _load());
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('الألبومات'), backgroundColor: Colors.transparent),
        extendBodyBehindAppBar: true,
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _create,
          icon: const Icon(Icons.add_rounded),
          label: const Text('ألبوم'),
        ),
        body: Backdrop(
          child: SafeArea(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _f,
              builder: (_, snap) {
                if (snap.hasError) {
                  return const Center(child: Text('الألبومات $_needUpdate5'));
                }
                final rows = snap.data;
                if (rows == null) return const Center(child: CircularProgressIndicator());
                if (rows.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Text('ما في ألبومات. سوّ ألبوم، وضيف له صور من المعرض بالضغط المطوّل.',
                          textAlign: TextAlign.center),
                    ),
                  );
                }
                return GridView.builder(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 90),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2, mainAxisSpacing: 14, crossAxisSpacing: 14, childAspectRatio: 0.85),
                  itemCount: rows.length,
                  itemBuilder: (_, i) {
                    final a = rows[i];
                    final items = List<Map>.from((a['album_items'] ?? const []) as List);
                    String? cover;
                    for (final it in items) {
                      final m = it['messages'];
                      if (m is Map && m['kind'] == 'image' && m['media_path'] != null) {
                        cover = '${m['media_path']}';
                        break;
                      }
                    }
                    return _Press(
                      onTap: () async {
                        await Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => AlbumScreen(
                                albumId: (a['id'] as num).toInt(), title: '${a['title']}')));
                        if (mounted) setState(() => _f = _load());
                      },
                      child: Glass(
                        radius: 22,
                        shadow: false,
                        padding: const EdgeInsets.all(_Sp.sm),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: cover == null
                                  ? const ColoredBox(
                                      color: Color(0x22FFFFFF),
                                      child: Center(child: Icon(Icons.photo_album_rounded, size: 40)))
                                  : FittedBox(
                                      fit: BoxFit.cover,
                                      clipBehavior: Clip.hardEdge,
                                      child: _NetImage(path: cover)),
                            ),
                          ),
                          const SizedBox(height: _Sp.sm),
                          Text('${a['title']}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w700)),
                          Text('${items.length} عنصر',
                              style: const TextStyle(fontSize: _Fs.small, color: Color(0xB3FFFFFF))),
                        ]),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ),
      );
}

class AlbumScreen extends StatefulWidget {
  const AlbumScreen({super.key, required this.albumId, required this.title});
  final int albumId;
  final String title;

  @override
  State<AlbumScreen> createState() => _AlbumState();
}

class _AlbumState extends State<AlbumScreen> {
  late Future<List<Map<String, dynamic>>> _f = _load();

  Future<List<Map<String, dynamic>>> _load() async => List<Map<String, dynamic>>.from(await _db
      .from('album_items')
      .select('message_id, messages(id,kind,media_path)')
      .eq('album_id', widget.albumId)
      .order('created_at', ascending: false));

  Future<void> _remove(int messageId) async {
    try {
      await _db
          .from('album_items')
          .delete()
          .eq('album_id', widget.albumId)
          .eq('message_id', messageId);
      if (mounted) setState(() => _f = _load());
    } catch (_) {}
  }

  Future<void> _deleteAlbum() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('تحذف ألبوم «${widget.title}»؟'),
        content: const Text('الصور تبقى بالمحادثة، الألبوم بس ينحذف.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('لا')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('احذف')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _db.from('albums').delete().eq('id', widget.albumId);
      if (mounted) Navigator.pop(context);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(widget.title),
          backgroundColor: Colors.transparent,
          actions: [
            IconButton(
                tooltip: 'حذف الألبوم',
                onPressed: _deleteAlbum,
                icon: const Icon(Icons.delete_outline_rounded)),
          ],
        ),
        extendBodyBehindAppBar: true,
        body: Backdrop(
          child: SafeArea(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _f,
              builder: (_, snap) {
                final rows = snap.data;
                if (snap.hasError) return const Center(child: Text('تعذر التحميل.'));
                if (rows == null) return const Center(child: CircularProgressIndicator());
                final items = [
                  for (final r in rows)
                    if (r['messages'] is Map && (r['messages'] as Map)['media_path'] != null)
                      Map<String, dynamic>.from(r['messages'] as Map),
                ];
                if (items.isEmpty) {
                  return const Center(child: Text('الألبوم فاضي. ضيف صور من معرض الذكريات.'));
                }
                return GridView.builder(
                  padding: const EdgeInsets.all(_Sp.sm),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3, mainAxisSpacing: 6, crossAxisSpacing: 6),
                  itemCount: items.length,
                  itemBuilder: (_, i) => GestureDetector(
                    onLongPress: () => _remove((items[i]['id'] as num).toInt()),
                    child: _MemoryTile(
                        kind: '${items[i]['kind']}', path: '${items[i]['media_path']}'),
                  ),
                );
              },
            ),
          ),
        ),
      );
}

// ===== الميزانية المشتركة =====

class BudgetScreen extends StatefulWidget {
  const BudgetScreen({super.key, required this.chatId});
  final String chatId;

  @override
  State<BudgetScreen> createState() => _BudgetState();
}

class _BudgetState extends State<BudgetScreen> {
  late final Stream<List<Map<String, dynamic>>> _s = _db
      .from('budget_items')
      .stream(primaryKey: ['id'])
      .eq('chat_id', widget.chatId)
      .order('id', ascending: false)
      .limit(500);

  String _fmt(num v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);

  Future<void> _add() async {
    final t = TextEditingController();
    final a = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('مصروف جديد'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: t,
            autofocus: true,
            maxLength: 60,
            decoration: const InputDecoration(labelText: 'على شنو؟', hintText: 'مثل: عشاء، هدية، تذاكر'),
          ),
          TextField(
            controller: a,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'المبلغ'),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('أضف')),
        ],
      ),
    );
    final title = t.text.trim();
    // نقبل الأرقام العربية بعد
    final raw = a.text.trim().replaceAllMapped(
        RegExp('[٠-٩]'), (m) => '${m.group(0)!.codeUnitAt(0) - 0x0660}').replaceAll('٫', '.').replaceAll(',', '.');
    t.dispose();
    a.dispose();
    final amount = double.tryParse(raw);
    if (ok != true) return;
    if (title.isEmpty || amount == null || amount <= 0) {
      if (mounted) _toast(context, 'اكتب الوصف والمبلغ.');
      return;
    }
    try {
      await _db.from('budget_items').insert({'chat_id': widget.chatId, 'title': title, 'amount': amount});
    } catch (_) {
      if (mounted) _toast(context, 'الميزانية $_needUpdate5');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('ميزانيتنا'), backgroundColor: Colors.transparent),
        extendBodyBehindAppBar: true,
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _add,
          icon: const Icon(Icons.add_rounded),
          label: const Text('مصروف'),
        ),
        body: Backdrop(
          child: SafeArea(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: _s,
              builder: (_, snap) {
                if (snap.hasError) return const Center(child: Text('الميزانية $_needUpdate5'));
                final rows = snap.data;
                if (rows == null) return const Center(child: CircularProgressIndicator());
                num mine = 0, theirs = 0;
                for (final r in rows) {
                  final v = (r['amount'] as num?) ?? num.tryParse('${r['amount']}') ?? 0;
                  if (r['paid_by'] == _meId) {
                    mine += v;
                  } else {
                    theirs += v;
                  }
                }
                final total = mine + theirs;
                final diff = (mine - theirs) / 2;
                return ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 90), children: [
                  Glass(
                    radius: 24,
                    padding: const EdgeInsets.all(_Sp.lg),
                    child: Column(children: [
                      const Text('المجموع', style: TextStyle(color: Color(0xB3FFFFFF))),
                      Text(_fmt(total), style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800)),
                      const SizedBox(height: _Sp.sm),
                      Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                        Text('دفعت ${_fmt(mine)}'),
                        Text('دفع ${_fmt(theirs)}'),
                      ]),
                      if (total > 0) ...[
                        const SizedBox(height: _Sp.sm),
                        Text(
                            diff.abs() < 0.01
                                ? 'متعادلين 👌'
                                : diff > 0
                                    ? 'لو تقسمونها نص نص: هو عليه لك ${_fmt(diff)}'
                                    : 'لو تقسمونها نص نص: أنت عليك له ${_fmt(-diff)}',
                            style: const TextStyle(fontSize: _Fs.meta, color: Color(0xDDFFFFFF))),
                      ],
                    ]),
                  ),
                  const SizedBox(height: _Sp.md),
                  if (rows.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(_Sp.xl),
                      child: Text('سجّلوا مصاريفكم المشتركة هنا.', textAlign: TextAlign.center),
                    ),
                  for (final r in rows)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: GestureDetector(
                        onLongPress: r['paid_by'] != _meId
                            ? null
                            : () async {
                                final ok = await showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    title: Text('تحذف «${r['title']}»؟'),
                                    actions: [
                                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('لا')),
                                      TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('احذف')),
                                    ],
                                  ),
                                );
                                if (ok == true) {
                                  try {
                                    await _db.from('budget_items').delete().eq('id', r['id']);
                                  } catch (_) {}
                                }
                              },
                        child: Glass(
                          radius: 18,
                          shadow: false,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          child: Row(children: [
                            Text(r['paid_by'] == _meId ? '🙋' : '💌', style: const TextStyle(fontSize: _Fs.display)),
                            const SizedBox(width: 10),
                            Expanded(child: Text('${r['title']}')),
                            Text(_fmt((r['amount'] as num?) ?? num.tryParse('${r['amount']}') ?? 0),
                                style: const TextStyle(fontWeight: FontWeight.w800)),
                          ]),
                        ),
                      ),
                    ),
                ]);
              },
            ),
          ),
        ),
      );
}

// ===== اليوميات المشتركة =====

const _moods = ['🙂', '😍', '😂', '😴', '😔', '😤'];

class DiaryScreen extends StatefulWidget {
  const DiaryScreen({super.key, required this.chatId});
  final String chatId;

  @override
  State<DiaryScreen> createState() => _DiaryState();
}

class _DiaryState extends State<DiaryScreen> {
  late final Stream<List<Map<String, dynamic>>> _s = _db
      .from('diary_entries')
      .stream(primaryKey: ['id'])
      .eq('chat_id', widget.chatId)
      .order('id', ascending: false)
      .limit(300);

  Future<void> _write([Map<String, dynamic>? edit]) async {
    final c = TextEditingController(text: edit?['body'] as String?);
    var mood = (edit?['mood'] as num?)?.toInt() ?? 0;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(edit == null ? 'يومية اليوم' : 'تعديل'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Wrap(spacing: 6, children: [
                for (var i = 0; i < _moods.length; i++)
                  GestureDetector(
                    onTap: () => set(() => mood = i),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: mood == i ? const Color(0x55FFFFFF) : Colors.transparent,
                      ),
                      child: Text(_moods[i], style: const TextStyle(fontSize: 26)),
                    ),
                  ),
              ]),
              TextField(
                controller: c,
                autofocus: true,
                maxLength: 2000,
                minLines: 4,
                maxLines: 10,
                decoration: const InputDecoration(hintText: 'شنو صار اليوم؟ شنو حسيت؟'),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حفظ')),
          ],
        ),
      ),
    );
    final t = c.text.trim();
    c.dispose();
    if (ok != true || t.isEmpty) return;
    try {
      if (edit == null) {
        await _db.from('diary_entries').insert(
            {'chat_id': widget.chatId, 'body': t, 'mood': mood, 'day': _dayStr(_today())});
      } else {
        await _db.from('diary_entries').update({'body': t, 'mood': mood}).eq('id', edit['id']);
      }
    } catch (_) {
      if (mounted) _toast(context, 'اليوميات $_needUpdate5');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('يومياتنا'), backgroundColor: Colors.transparent),
        extendBodyBehindAppBar: true,
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _write,
          icon: const Icon(Icons.edit_rounded),
          label: const Text('اكتب'),
        ),
        body: Backdrop(
          child: SafeArea(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: _s,
              builder: (_, snap) {
                if (snap.hasError) return const Center(child: Text('اليوميات $_needUpdate5'));
                final rows = snap.data;
                if (rows == null) return const Center(child: CircularProgressIndicator());
                if (rows.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Text('دفتر يوميات لكم الاثنين. كل واحد يكتب يومه، والثاني يقراه.',
                          textAlign: TextAlign.center),
                    ),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
                  itemCount: rows.length,
                  itemBuilder: (_, i) {
                    final r = rows[i];
                    final mine = r['author'] == _meId;
                    final d = DateTime.tryParse('${r['day']}');
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: GestureDetector(
                        onLongPress: mine ? () => _write(r) : null,
                        child: Glass(
                          radius: 20,
                          shadow: false,
                          tint: mine ? const Color(0xFF0A84FF) : const Color(0xFFFF5FA2),
                          padding: const EdgeInsets.all(14),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              Text(_moods[((r['mood'] as num?)?.toInt() ?? 0) % _moods.length],
                                  style: const TextStyle(fontSize: 22)),
                              const SizedBox(width: _Sp.sm),
                              Text(mine ? 'أنت' : 'هو', style: const TextStyle(fontWeight: FontWeight.w700)),
                              const Spacer(),
                              Text(d == null ? '' : _dayLabel(d),
                                  style: const TextStyle(fontSize: _Fs.small, color: Color(0xB3FFFFFF))),
                            ]),
                            const SizedBox(height: _Sp.sm),
                            Text('${r['body']}', style: const TextStyle(height: 1.6)),
                          ]),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ),
      );
}
