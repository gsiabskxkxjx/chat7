part of 'main.dart';

// ---------- الجولة الثانية: الألبومات ----------
// 331 صور هذا الشهر · 332 ترتيب وغلاف · 333 تعليق · 334 عرض شرائح · 335 كولاج
// 337 صورة اليوم · 338 وسوم وفلترة · 339 خط زمني · 340 إضافة عدة صور

const _tagSuggestions = ['سفر', 'أكل', 'عيد', 'ضحك', 'ذكرى', 'طبيعة'];

class _AItem {
  _AItem({
    required this.mid,
    required this.kind,
    required this.path,
    this.caption,
    List<String>? tags,
    this.at,
  }) : tags = tags ?? <String>[];
  final int mid;
  final String kind;
  final String path;
  String? caption;
  List<String> tags;
  final DateTime? at;
}

Future<List<_AItem>> _loadAlbumItems(int albumId) async {
  final rows = await _db
      .from('album_items')
      .select('message_id,caption,sort_order,tags,created_at,messages(id,kind,media_path,created_at)')
      .eq('album_id', albumId)
      .order('sort_order', ascending: true)
      .order('created_at', ascending: false);
  final out = <_AItem>[];
  for (final r in rows) {
    final m = r['messages'];
    if (m is! Map || m['media_path'] == null) continue;
    out.add(_AItem(
      mid: (m['id'] as num).toInt(),
      kind: '${m['kind']}',
      path: '${m['media_path']}',
      caption: r['caption'] as String?,
      tags: [for (final t in (r['tags'] as List? ?? const [])) '$t'],
      at: DateTime.tryParse('${m['created_at']}')?.toLocal(),
    ));
  }
  return out;
}

// ===== قائمة الألبومات =====

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
      .select('id,title,cover_message_id,album_items(message_id,sort_order,messages(media_path,kind))')
      .eq('chat_id', widget.chatId)
      .order('id', ascending: false));

  Future<void> _create() async {
    final id = await _newAlbum(context, widget.chatId);
    if (id != null && mounted) setState(() => _f = _load());
  }

  String? _coverOf(Map<String, dynamic> a) {
    final items = List<Map>.from((a['album_items'] ?? const []) as List)
      ..sort((x, y) => ((x['sort_order'] as num?) ?? 0).compareTo((y['sort_order'] as num?) ?? 0));
    final cid = (a['cover_message_id'] as num?)?.toInt();
    String? first;
    for (final it in items) {
      final m = it['messages'];
      if (m is Map && m['kind'] == 'image' && m['media_path'] != null) {
        first ??= '${m['media_path']}';
        if (cid != null && (it['message_id'] as num?)?.toInt() == cid) return '${m['media_path']}';
      }
    }
    return first;
  }

  Widget _tile({required Widget cover, required String title, required String sub, required VoidCallback onTap}) =>
      _Press(
        onTap: onTap,
        child: Glass(
          radius: 22,
          shadow: false,
          padding: const EdgeInsets.all(_Sp.sm),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(16), child: cover)),
            const SizedBox(height: _Sp.sm),
            Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
            Text(sub, style: const TextStyle(fontSize: _Fs.small, color: Color(0xB3FFFFFF))),
          ]),
        ),
      );

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
                if (rows == null) return const _SkeletonGrid();
                return GridView.builder(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 90),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2, mainAxisSpacing: 14, crossAxisSpacing: 14, childAspectRatio: 0.85),
                  itemCount: rows.length + 1,
                  itemBuilder: (_, i) {
                    if (i == 0) {
                      return _tile(
                        cover: const ColoredBox(
                            color: Color(0x22FFFFFF), child: Center(child: Text('📅', style: TextStyle(fontSize: 44)))),
                        title: 'صور هذا الشهر',
                        sub: 'تلقائي',
                        onTap: () => Navigator.of(context)
                            .push(MaterialPageRoute(builder: (_) => MonthAlbumScreen(chatId: widget.chatId)))
                            .then((_) {
                          if (mounted) setState(() => _f = _load());
                        }),
                      );
                    }
                    final a = rows[i - 1];
                    final n = List<Map>.from((a['album_items'] ?? const []) as List).length;
                    final cover = _coverOf(a);
                    return _tile(
                      cover: cover == null
                          ? const ColoredBox(
                              color: Color(0x22FFFFFF), child: Center(child: Icon(Icons.photo_album_rounded, size: 40)))
                          : FittedBox(fit: BoxFit.cover, clipBehavior: Clip.hardEdge, child: _NetImage(path: cover)),
                      title: '${a['title']}',
                      sub: '${_Fmt.digits('$n')} عنصر',
                      onTap: () async {
                        await Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => AlbumScreen(albumId: (a['id'] as num).toInt(), title: '${a['title']}')));
                        if (mounted) setState(() => _f = _load());
                      },
                    );
                  },
                );
              },
            ),
          ),
        ),
      );
}

// ===== ألبوم تلقائي: صور هذا الشهر =====

class MonthAlbumScreen extends StatefulWidget {
  const MonthAlbumScreen({super.key, required this.chatId});
  final String chatId;

  @override
  State<MonthAlbumScreen> createState() => _MonthAlbumState();
}

class _MonthAlbumState extends State<MonthAlbumScreen> {
  late final Future<List<_AItem>> _f = _load();

  Future<List<_AItem>> _load() async {
    final now = DateTime.now();
    final from = DateTime(now.year, now.month, 1).toUtc().toIso8601String();
    final rows = await _db
        .from('messages')
        .select('id,kind,media_path,created_at')
        .eq('chat_id', widget.chatId)
        .inFilter('kind', ['image', 'video'])
        .gte('created_at', from)
        .order('created_at', ascending: false)
        .limit(400);
    return [
      for (final m in rows)
        if (m['media_path'] != null)
          _AItem(
              mid: (m['id'] as num).toInt(),
              kind: '${m['kind']}',
              path: '${m['media_path']}',
              at: DateTime.tryParse('${m['created_at']}')?.toLocal()),
    ];
  }

  Future<void> _save(List<_AItem> items) async {
    final now = DateTime.now();
    try {
      final r = await _db
          .from('albums')
          .insert({'chat_id': widget.chatId, 'title': 'صور ${_months[now.month - 1]} ${_Fmt.digits('${now.year}')}'})
          .select('id')
          .single();
      final id = (r['id'] as num).toInt();
      await _db.from('album_items').upsert([
        for (var i = 0; i < items.length; i++) {'album_id': id, 'message_id': items[i].mid, 'sort_order': i + 1}
      ]);
      if (!mounted) return;
      _toast(context, 'انحفظ كألبوم.');
      Navigator.pop(context);
    } catch (e) {
      if (mounted) _toast(context, _friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<_AItem>>(
        future: _f,
        builder: (_, snap) {
          final items = snap.data;
          return Scaffold(
            appBar: AppBar(
              title: Text('صور ${_months[DateTime.now().month - 1]}'),
              backgroundColor: Colors.transparent,
              actions: [
                if (items != null && items.isNotEmpty)
                  TextButton(onPressed: () => unawaited(_save(items)), child: const Text('احفظ كألبوم')),
              ],
            ),
            extendBodyBehindAppBar: true,
            body: Backdrop(
              child: SafeArea(
                child: snap.hasError
                    ? const Center(child: Text('تعذر التحميل.'))
                    : items == null
                        ? const _SkeletonGrid()
                        : items.isEmpty
                            ? const Center(child: Text('ما في صور هذا الشهر بعد.'))
                            : GridView.builder(
                                padding: const EdgeInsets.all(_Sp.sm),
                                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 3, mainAxisSpacing: 6, crossAxisSpacing: 6),
                                itemCount: items.length,
                                itemBuilder: (_, i) => _MemoryTile(kind: items[i].kind, path: items[i].path),
                              ),
              ),
            ),
          );
        },
      );
}

// ===== شاشة الألبوم =====

class AlbumScreen extends StatefulWidget {
  const AlbumScreen({super.key, required this.albumId, required this.title});
  final int albumId;
  final String title;

  @override
  State<AlbumScreen> createState() => _AlbumState();
}

class _AlbumState extends State<AlbumScreen> {
  List<_AItem>? _items;
  Object? _err;
  int? _cover;
  String? _chatId;
  String? _tag;
  bool _timeline = false;
  bool _reorder = false;
  bool _select = false;
  final Set<int> _sel = {};

  @override
  void initState() {
    super.initState();
    unawaited(_reload());
  }

  Future<void> _reload() async {
    try {
      final a = await _db.from('albums').select('chat_id,cover_message_id').eq('id', widget.albumId).maybeSingle();
      final items = await _loadAlbumItems(widget.albumId);
      if (!mounted) return;
      setState(() {
        _cover = (a?['cover_message_id'] as num?)?.toInt();
        _chatId = a?['chat_id'] as String?;
        _items = items;
        _err = null;
      });
    } catch (e) {
      if (mounted) setState(() => _err = e);
    }
  }

  List<_AItem> get _shown {
    final all = _items ?? const <_AItem>[];
    final t = _tag;
    return t == null ? all : [for (final i in all) if (i.tags.contains(t)) i];
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

  Future<void> _editInfo(_AItem it) async {
    final c = TextEditingController(text: it.caption ?? '');
    final tg = TextEditingController(text: it.tags.join('، '));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تعليق ووسوم'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (it.at != null)
              Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text('التقطت ${_Fmt.date(it.at!)}', style: const TextStyle(fontSize: _Fs.small))),
            TextField(controller: c, maxLength: 200, maxLines: 3, minLines: 1, decoration: const InputDecoration(labelText: 'تعليق')),
            TextField(
                controller: tg,
                decoration: const InputDecoration(labelText: 'وسوم (حتى ٥، افصل بفاصلة)')),
            const SizedBox(height: 8),
            Wrap(spacing: 6, children: [
              for (final s in _tagSuggestions)
                ActionChip(
                  label: Text(s),
                  onPressed: () {
                    final cur = _splitTags(tg.text);
                    if (!cur.contains(s) && cur.length < 5) {
                      cur.add(s);
                      tg.text = cur.join('، ');
                    }
                  },
                ),
            ]),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حفظ')),
        ],
      ),
    );
    final cap = c.text.trim();
    final tags = _splitTags(tg.text);
    c.dispose();
    tg.dispose();
    if (ok != true) return;
    try {
      await _db
          .from('album_items')
          .update({'caption': cap.isEmpty ? null : cap, 'tags': tags})
          .eq('album_id', widget.albumId)
          .eq('message_id', it.mid);
      it.caption = cap.isEmpty ? null : cap;
      it.tags = tags;
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) _toast(context, _friendlyError(e));
    }
  }

  List<String> _splitTags(String s) {
    return pure.splitTags(s);
  }

  Future<void> _setCover(_AItem it) async {
    try {
      await _db.from('albums').update({'cover_message_id': it.mid}).eq('id', widget.albumId);
      if (mounted) {
        setState(() => _cover = it.mid);
        _toast(context, 'صارت غلاف الألبوم.');
      }
    } catch (e) {
      if (mounted) _toast(context, _friendlyError(e));
    }
  }

  Future<void> _setPod(_AItem it) async {
    final cid = _chatId;
    if (cid == null) return;
    await _R2Store.set('pod_$cid', {'path': it.path, 'day': _dayStr(DateTime.now())});
    if (mounted) _toast(context, 'صارت «صورة اليوم» وتظهر بالمحادثة.');
  }

  Future<void> _remove(_AItem it) async {
    try {
      await _db.from('album_items').delete().eq('album_id', widget.albumId).eq('message_id', it.mid);
      _items?.remove(it);
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<void> _act(String act, _AItem it) async {
    switch (act) {
      case 'edit':
        await _editInfo(it);
      case 'cover':
        await _setCover(it);
      case 'pod':
        await _setPod(it);
      case 'remove':
        await _remove(it);
    }
  }

  Future<void> _itemMenu(_AItem it) async {
    final act = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.edit_note_rounded), title: const Text('تعليق ووسوم'), onTap: () => Navigator.pop(ctx, 'edit')),
          if (it.kind == 'image') ...[
            ListTile(leading: const Icon(Icons.star_rounded), title: const Text('اجعلها غلاف الألبوم'), onTap: () => Navigator.pop(ctx, 'cover')),
            ListTile(leading: const Icon(Icons.wb_sunny_rounded), title: const Text('اجعلها صورة اليوم'), onTap: () => Navigator.pop(ctx, 'pod')),
          ],
          ListTile(leading: const Icon(Icons.remove_circle_outline_rounded), title: const Text('إزالة من الألبوم'), onTap: () => Navigator.pop(ctx, 'remove')),
        ]),
      ),
    );
    if (act != null) await _act(act, it);
  }

  void _open(List<_AItem> list, int i) {
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => _AlbumPager(items: list, index: i, onAction: _act, coverOf: () => _cover)));
  }

  Future<void> _addMore() async {
    final cid = _chatId;
    if (cid == null) return;
    final n = await Navigator.of(context).push<int>(MaterialPageRoute(
        builder: (_) => _AlbumPicker(
            chatId: cid, albumId: widget.albumId, existing: {for (final i in _items ?? const <_AItem>[]) i.mid})));
    if (n != null && n > 0) {
      unawaited(_reload());
      if (mounted) _toast(context, 'انضافت ${_Fmt.digits('$n')} للألبوم.');
    }
  }

  Future<void> _saveOrder() async {
    final items = _items;
    if (items == null) return;
    try {
      await Future.wait([
        for (var i = 0; i < items.length; i++)
          _db
              .from('album_items')
              .update({'sort_order': i + 1})
              .eq('album_id', widget.albumId)
              .eq('message_id', items[i].mid)
      ]);
    } catch (e) {
      if (mounted) _toast(context, _friendlyError(e));
    }
  }

  void _slideshow() {
    final imgs = [for (final i in _shown) if (i.kind == 'image') i];
    if (imgs.isEmpty) {
      _toast(context, 'ما في صور لعرضها.');
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => _Slideshow(items: imgs)));
  }

  void _collage() {
    final cid = _chatId;
    if (cid == null) return;
    final picked = [for (final i in _shown) if (_sel.contains(i.mid) && i.kind == 'image') i.path];
    if (picked.length < 2 || picked.length > 4) {
      _toast(context, 'اختر من ٢ إلى ٤ صور.');
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => _CollageScreen(chatId: cid, paths: picked)));
    setState(() {
      _select = false;
      _sel.clear();
    });
  }

  Widget _tile(List<_AItem> list, int i) {
    final it = list[i];
    final picked = _sel.contains(it.mid);
    return GestureDetector(
      onTap: () {
        if (_select) {
          setState(() => picked ? _sel.remove(it.mid) : _sel.add(it.mid));
        } else {
          _open(list, i);
        }
      },
      onLongPress: _select ? null : () => unawaited(_itemMenu(it)),
      child: Stack(fit: StackFit.expand, children: [
        _MemoryTileStatic(kind: it.kind, path: it.path),
        if (_cover == it.mid)
          const Positioned(top: 4, right: 4, child: Icon(Icons.star_rounded, color: Color(0xFFFFD60A), size: 18)),
        if ((it.caption ?? '').isNotEmpty)
          const Positioned(bottom: 4, left: 4, child: Icon(Icons.chat_bubble_rounded, color: Colors.white70, size: 14)),
        if (_select)
          Positioned(
              top: 4,
              left: 4,
              child: Icon(picked ? Icons.check_circle_rounded : Icons.circle_outlined,
                  color: picked ? const Color(0xFF34C759) : Colors.white, size: 22)),
      ]),
    );
  }

  Widget _grid(List<_AItem> list) => GridView.builder(
        padding: const EdgeInsets.all(_Sp.sm),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3, mainAxisSpacing: 6, crossAxisSpacing: 6),
        itemCount: list.length,
        itemBuilder: (_, i) => _tile(list, i),
      );

  Widget _timelineView(List<_AItem> list) {
    final groups = <String, List<_AItem>>{};
    final order = <String>[];
    for (final i in list) {
      final d = i.at;
      final k = d == null ? '—' : '${_months[d.month - 1]} ${_Fmt.digits('${d.year}')}';
      if (!groups.containsKey(k)) order.add(k);
      groups.putIfAbsent(k, () => []).add(i);
    }
    return CustomScrollView(slivers: [
      for (final k in order) ...[
        SliverToBoxAdapter(
            child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
                child: Text(k, style: const TextStyle(fontSize: _Fs.titleL, fontWeight: FontWeight.w700)))),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: _Sp.sm),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3, mainAxisSpacing: 6, crossAxisSpacing: 6),
            delegate: SliverChildBuilderDelegate((_, i) => _tile(list, list.indexOf(groups[k]![i])),
                childCount: groups[k]!.length),
          ),
        ),
      ],
      const SliverToBoxAdapter(child: SizedBox(height: 40)),
    ]);
  }

  Widget _reorderView(List<_AItem> list) => ReorderableListView.builder(
        padding: const EdgeInsets.all(_Sp.sm),
        itemCount: list.length,
        onReorder: (a, b) {
          if (b > a) b--;
          setState(() => list.insert(b, list.removeAt(a)));
        },
        itemBuilder: (_, i) => ListTile(
          key: ValueKey('ro-${list[i].mid}'),
          leading: SizedBox(width: 56, height: 56, child: _MemoryTileStatic(kind: list[i].kind, path: list[i].path)),
          title: Text(list[i].caption ?? (list[i].kind == 'video' ? 'فيديو' : 'صورة'), maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: const Icon(Icons.drag_handle_rounded),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final all = _items;
    final tags = <String>{for (final i in all ?? const <_AItem>[]) ...i.tags}.toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(_select ? 'اختر ${_Fmt.digits('${_sel.length}')} من ٤' : widget.title),
        backgroundColor: Colors.transparent,
        actions: [
          if (_reorder)
            TextButton(
                onPressed: () async {
                  await _saveOrder();
                  if (mounted) setState(() => _reorder = false);
                },
                child: const Text('تم'))
          else if (_select) ...[
            TextButton(onPressed: _collage, child: const Text('اصنع كولاج')),
            IconButton(
                onPressed: () => setState(() {
                      _select = false;
                      _sel.clear();
                    }),
                icon: const Icon(Icons.close_rounded)),
          ] else ...[
            IconButton(tooltip: 'عرض شرائح', onPressed: _slideshow, icon: const Icon(Icons.slideshow_rounded)),
            PopupMenuButton<String>(
              onSelected: (v) {
                switch (v) {
                  case 'add':
                    unawaited(_addMore());
                  case 'timeline':
                    setState(() => _timeline = !_timeline);
                  case 'reorder':
                    setState(() {
                      _tag = null;
                      _timeline = false;
                      _reorder = true;
                    });
                  case 'collage':
                    setState(() {
                      _select = true;
                      _sel.clear();
                    });
                  case 'delete':
                    unawaited(_deleteAlbum());
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'add', child: Text('إضافة صور من المحادثة')),
                PopupMenuItem(value: 'timeline', child: Text(_timeline ? 'عرض شبكة' : 'خط زمني')),
                const PopupMenuItem(value: 'reorder', child: Text('ترتيب بالسحب')),
                const PopupMenuItem(value: 'collage', child: Text('كولاج')),
                const PopupMenuItem(value: 'delete', child: Text('حذف الألبوم')),
              ],
            ),
          ],
        ],
      ),
      extendBodyBehindAppBar: true,
      body: Backdrop(
        child: SafeArea(
          child: _err != null
              ? const Center(child: Text('تعذر التحميل.'))
              : all == null
                  ? const _SkeletonGrid()
                  : all.isEmpty
                      ? Center(
                          child: Column(mainAxisSize: MainAxisSize.min, children: [
                          const Text('الألبوم فاضي.'),
                          const SizedBox(height: 10),
                          FilledButton.icon(
                              onPressed: _addMore,
                              icon: const Icon(Icons.add_photo_alternate_rounded),
                              label: const Text('أضف صور من المحادثة')),
                        ]))
                      : Column(children: [
                          if (tags.isNotEmpty && !_reorder)
                            SizedBox(
                              height: 46,
                              child: ListView(
                                scrollDirection: Axis.horizontal,
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                children: [
                                  Padding(
                                      padding: const EdgeInsets.only(left: 6),
                                      child: ChoiceChip(
                                          label: const Text('الكل'), selected: _tag == null, onSelected: (_) => setState(() => _tag = null))),
                                  for (final t in tags)
                                    Padding(
                                        padding: const EdgeInsets.only(left: 6),
                                        child: ChoiceChip(
                                            label: Text('#$t'), selected: _tag == t, onSelected: (_) => setState(() => _tag = t))),
                                ],
                              ),
                            ),
                          Expanded(
                              child: _reorder
                                  ? _reorderView(all)
                                  : (_timeline ? _timelineView(_shown) : _grid(_shown))),
                        ]),
        ),
      ),
    );
  }
}

/// مصغّرة بدون فتح تلقائي (الضغط تتحكم فيه الشبكة)
class _MemoryTileStatic extends StatelessWidget {
  const _MemoryTileStatic({required this.kind, required this.path});
  final String kind;
  final String path;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Container(
          color: const Color(0x33000000),
          child: kind == 'video'
              ? const Center(child: Icon(Icons.play_circle_fill_rounded, size: 36, color: Colors.white))
              : _ThumbImage(path: path),
        ),
      );
}

// ===== عارض الألبوم (سحب بين الصور + تعليق + إجراءات) =====

class _AlbumPager extends StatefulWidget {
  const _AlbumPager({required this.items, required this.index, required this.onAction, required this.coverOf});
  final List<_AItem> items;
  final int index;
  final Future<void> Function(String act, _AItem it) onAction;
  final int? Function() coverOf;

  @override
  State<_AlbumPager> createState() => _AlbumPagerState();
}

class _AlbumPagerState extends State<_AlbumPager> {
  late final PageController _pc = PageController(initialPage: widget.index);
  late int _i = widget.index;

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  Future<void> _do(String act) async {
    if (_i >= widget.items.length) return;
    final target = widget.items[_i];
    await widget.onAction(act, target);
    if (act == 'remove') widget.items.remove(target);
    if (!mounted) return;
    if (widget.items.isEmpty) {
      Navigator.pop(context);
      return;
    }
    setState(() {
      if (_i >= widget.items.length) _i = widget.items.length - 1;
    });
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.items.length;
    final it = _i < n ? widget.items[_i] : null;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        title: Text('${_Fmt.digits('${_i + 1}')} / ${_Fmt.digits('$n')}', style: const TextStyle(fontSize: _Fs.body)),
        actions: [
          IconButton(tooltip: 'تعليق ووسوم', onPressed: () => unawaited(_do('edit')), icon: const Icon(Icons.edit_note_rounded)),
          if (it?.kind == 'image')
            IconButton(
                tooltip: 'غلاف الألبوم',
                onPressed: () => unawaited(_do('cover')),
                icon: Icon(widget.coverOf() == it?.mid ? Icons.star_rounded : Icons.star_border_rounded)),
          IconButton(tooltip: 'إزالة', onPressed: () => unawaited(_do('remove')), icon: const Icon(Icons.remove_circle_outline_rounded)),
        ],
      ),
      body: Column(children: [
        Expanded(
          child: PageView.builder(
            controller: _pc,
            itemCount: n,
            onPageChanged: (v) => setState(() => _i = v),
            itemBuilder: (_, i) {
              final x = widget.items[i];
              if (x.kind == 'video') {
                return Center(
                  child: IconButton(
                    iconSize: 72,
                    color: Colors.white,
                    icon: const Icon(Icons.play_circle_fill_rounded),
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => VideoScreen(path: x.path))),
                  ),
                );
              }
              return InteractiveViewer(maxScale: 5, child: Center(child: _NetImage(path: x.path, full: true)));
            },
          ),
        ),
        if (it != null && ((it.caption ?? '').isNotEmpty || it.tags.isNotEmpty || it.at != null))
          Container(
            width: double.infinity,
            color: const Color(0xCC000000),
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
            child: SafeArea(
              top: false,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                if ((it.caption ?? '').isNotEmpty)
                  Text(it.caption!, style: const TextStyle(color: Colors.white, fontSize: _Fs.bodyL)),
                if (it.tags.isNotEmpty)
                  Text(it.tags.map((t) => '#$t').join('  '), style: const TextStyle(color: Color(0xFF64D2FF), fontSize: _Fs.meta)),
                if (it.at != null)
                  Text('${_Fmt.date(it.at!)} ${_Fmt.time(it.at!)}', style: const TextStyle(color: Colors.white54, fontSize: _Fs.small)),
              ]),
            ),
          ),
      ]),
    );
  }
}

// ===== عرض شرائح =====

class _Slideshow extends StatefulWidget {
  const _Slideshow({required this.items});
  final List<_AItem> items;

  @override
  State<_Slideshow> createState() => _SlideshowState();
}

class _SlideshowState extends State<_Slideshow> {
  int _i = 0;
  bool _paused = false;
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!_paused && mounted) setState(() => _i = (_i + 1) % widget.items.length);
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final it = widget.items[_i];
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _paused = !_paused),
        child: Stack(fit: StackFit.expand, children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 900),
            child: Center(key: ValueKey('ss-${it.mid}'), child: _NetImage(path: it.path, full: true)),
          ),
          if ((it.caption ?? '').isNotEmpty)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                color: const Color(0x99000000),
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                child: Text(it.caption!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: _Fs.titleL)),
              ),
            ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Row(children: [
                IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded, color: Colors.white)),
                const Spacer(),
                Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(_paused ? '⏸ متوقف' : '${_Fmt.digits('${_i + 1}')} / ${_Fmt.digits('${widget.items.length}')}',
                        style: const TextStyle(color: Colors.white70))),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

// ===== اختيار صور من المحادثة لإضافتها (متعدد) =====

class _AlbumPicker extends StatefulWidget {
  const _AlbumPicker({required this.chatId, required this.albumId, required this.existing});
  final String chatId;
  final int albumId;
  final Set<int> existing;

  @override
  State<_AlbumPicker> createState() => _AlbumPickerState();
}

class _AlbumPickerState extends State<_AlbumPicker> {
  late final Future<List<_AItem>> _f = _load();
  final Set<int> _sel = {};
  bool _busy = false;

  Future<List<_AItem>> _load() async {
    final rows = await _db
        .from('messages')
        .select('id,kind,media_path,created_at')
        .eq('chat_id', widget.chatId)
        .inFilter('kind', ['image', 'video'])
        .order('created_at', ascending: false)
        .limit(300);
    return [
      for (final m in rows)
        if (m['media_path'] != null && !widget.existing.contains((m['id'] as num).toInt()))
          _AItem(mid: (m['id'] as num).toInt(), kind: '${m['kind']}', path: '${m['media_path']}'),
    ];
  }

  Future<void> _add() async {
    if (_sel.isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      final base = widget.existing.length;
      final ids = _sel.toList();
      await _db.from('album_items').upsert([
        for (var i = 0; i < ids.length; i++) {'album_id': widget.albumId, 'message_id': ids[i], 'sort_order': base + i + 1}
      ]);
      if (mounted) Navigator.pop(context, ids.length);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        _toast(context, _friendlyError(e));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(_sel.isEmpty ? 'اختر صور' : 'اخترت ${_Fmt.digits('${_sel.length}')}'),
          backgroundColor: Colors.transparent,
          actions: [TextButton(onPressed: _sel.isEmpty || _busy ? null : _add, child: const Text('أضف'))],
        ),
        extendBodyBehindAppBar: true,
        body: Backdrop(
          child: SafeArea(
            child: FutureBuilder<List<_AItem>>(
              future: _f,
              builder: (_, snap) {
                final items = snap.data;
                if (snap.hasError) return const Center(child: Text('تعذر التحميل.'));
                if (items == null) return const _SkeletonGrid();
                if (items.isEmpty) return const Center(child: Text('كل صور المحادثة موجودة بالألبوم.'));
                return GridView.builder(
                  padding: const EdgeInsets.all(_Sp.sm),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3, mainAxisSpacing: 6, crossAxisSpacing: 6),
                  itemCount: items.length,
                  itemBuilder: (_, i) {
                    final it = items[i];
                    final on = _sel.contains(it.mid);
                    return GestureDetector(
                      onTap: () => setState(() => on ? _sel.remove(it.mid) : _sel.add(it.mid)),
                      child: Stack(fit: StackFit.expand, children: [
                        _MemoryTileStatic(kind: it.kind, path: it.path),
                        Positioned(
                            top: 4,
                            left: 4,
                            child: Icon(on ? Icons.check_circle_rounded : Icons.circle_outlined,
                                color: on ? const Color(0xFF34C759) : Colors.white, size: 22)),
                      ]),
                    );
                  },
                );
              },
            ),
          ),
        ),
      );
}

// ===== كولاج =====

List<Rect> _collageRects(int n, int template, double s, double g) {
  final h = (s - g) / 2;
  switch (n) {
    case 2:
      return template == 0
          ? [Rect.fromLTWH(0, 0, h, s), Rect.fromLTWH(h + g, 0, h, s)]
          : [Rect.fromLTWH(0, 0, s, h), Rect.fromLTWH(0, h + g, s, h)];
    case 3:
      return template == 0
          ? [Rect.fromLTWH(0, 0, h, s), Rect.fromLTWH(h + g, 0, h, h), Rect.fromLTWH(h + g, h + g, h, h)]
          : [Rect.fromLTWH(0, 0, s, h), Rect.fromLTWH(0, h + g, h, h), Rect.fromLTWH(h + g, h + g, h, h)];
    default:
      return template == 0
          ? [
              Rect.fromLTWH(0, 0, h, h),
              Rect.fromLTWH(h + g, 0, h, h),
              Rect.fromLTWH(0, h + g, h, h),
              Rect.fromLTWH(h + g, h + g, h, h),
            ]
          : [
              Rect.fromLTWH(0, 0, s, h),
              Rect.fromLTWH(0, h + g, (s - 2 * g) / 3, h),
              Rect.fromLTWH((s - 2 * g) / 3 + g, h + g, (s - 2 * g) / 3, h),
              Rect.fromLTWH(2 * ((s - 2 * g) / 3 + g), h + g, (s - 2 * g) / 3, h),
            ];
  }
}

Future<Uint8List?> _makeCollage(List<String> paths, int template) async {
  const s = 1080.0;
  const g = 10.0;
  final rec = PictureRecorder();
  final cv = Canvas(rec, const Rect.fromLTWH(0, 0, s, s));
  cv.drawRect(const Rect.fromLTWH(0, 0, s, s), Paint()..color = const Color(0xFFFFFFFF));
  final rects = _collageRects(paths.length, template, s, g);
  for (var i = 0; i < paths.length && i < rects.length; i++) {
    final f = await _MediaFiles.get(paths[i]);
    if (f == null) continue;
    final codec = await instantiateImageCodec(await f.readAsBytes(), targetWidth: 1080);
    final fr = await codec.getNextFrame();
    final img = fr.image;
    final r = rects[i];
    final sa = img.width / img.height;
    final ra = r.width / r.height;
    final Rect src;
    if (sa > ra) {
      final w = img.height * ra;
      src = Rect.fromLTWH((img.width - w) / 2, 0, w, img.height.toDouble());
    } else {
      final hh = img.width / ra;
      src = Rect.fromLTWH(0, (img.height - hh) / 2, img.width.toDouble(), hh);
    }
    cv.drawImageRect(img, src, r, Paint()..filterQuality = FilterQuality.high);
    img.dispose();
  }
  final pic = rec.endRecording();
  final out = await pic.toImage(s.toInt(), s.toInt());
  final bd = await out.toByteData(format: ImageByteFormat.png);
  out.dispose();
  return bd?.buffer.asUint8List();
}

class _CollageScreen extends StatefulWidget {
  const _CollageScreen({required this.chatId, required this.paths});
  final String chatId;
  final List<String> paths;

  @override
  State<_CollageScreen> createState() => _CollageState();
}

class _CollageState extends State<_CollageScreen> {
  int _tpl = 0;
  Uint8List? _png;
  bool _busy = true;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    unawaited(_gen());
  }

  Future<void> _gen() async {
    setState(() => _busy = true);
    Uint8List? b;
    try {
      b = await _makeCollage(widget.paths, _tpl);
    } catch (_) {}
    if (mounted) {
      setState(() {
        _png = b;
        _busy = false;
      });
    }
  }

  Future<void> _send() async {
    final b = _png;
    if (b == null || _sending) return;
    setState(() => _sending = true);
    try {
      final dir = await getTemporaryDirectory();
      final f = File('${dir.path}/collage_${DateTime.now().millisecondsSinceEpoch}.png');
      await f.writeAsBytes(b);
      await _sendMedia(chatId: widget.chatId, file: f, kind: 'image', ext: 'png', mime: 'image/png');
      if (!mounted) return;
      _toast(context, 'انرسل الكولاج.');
      Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _sending = false);
        _toast(context, _friendlyError(e));
      }
    }
  }

  Future<void> _save() async {
    final b = _png;
    if (b == null) return;
    try {
      final dir = await getTemporaryDirectory();
      final f = File('${dir.path}/collage_${DateTime.now().millisecondsSinceEpoch}.png');
      await f.writeAsBytes(b);
      await Gal.putImage(f.path, album: appName);
      if (mounted) _toast(context, 'انحفظ بالمعرض.');
    } catch (_) {
      if (mounted) _toast(context, 'تعذر الحفظ.');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('كولاج'), backgroundColor: Colors.transparent),
        body: SafeArea(
          child: Column(children: [
            Expanded(
              child: Center(
                child: _busy
                    ? const CircularProgressIndicator()
                    : _png == null
                        ? const Text('تعذر صنع الكولاج.')
                        : Padding(padding: const EdgeInsets.all(14), child: Image.memory(_png!, fit: BoxFit.contain)),
              ),
            ),
            Wrap(spacing: 8, children: [
              ChoiceChip(label: const Text('قالب ١'), selected: _tpl == 0, onSelected: (_) {
                _tpl = 0;
                unawaited(_gen());
              }),
              ChoiceChip(label: const Text('قالب ٢'), selected: _tpl == 1, onSelected: (_) {
                _tpl = 1;
                unawaited(_gen());
              }),
            ]),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Row(children: [
                Expanded(
                    child: OutlinedButton.icon(
                        onPressed: _png == null ? null : _save,
                        icon: const Icon(Icons.download_rounded),
                        label: const Text('احفظ'))),
                const SizedBox(width: 10),
                Expanded(
                    child: FilledButton.icon(
                        onPressed: _png == null || _sending ? null : _send,
                        icon: const Icon(Icons.send_rounded),
                        label: const Text('أرسل بالمحادثة'))),
              ]),
            ),
          ]),
        ),
      );
}
