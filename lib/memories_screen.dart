part of 'main.dart';

// ---------- معرض الذكريات: كل الصور والفيديو بالمحادثة ----------

class MemoriesScreen extends StatefulWidget {
  const MemoriesScreen({super.key, required this.chatId});
  final String chatId;

  @override
  State<MemoriesScreen> createState() => _MemoriesState();
}

class _MemoriesState extends State<MemoriesScreen> {
  late final Future<List<Map<String, dynamic>>> _future = _load();

  Future<List<Map<String, dynamic>>> _load() async {
    final rows = await _db
        .from('messages')
        .select('id,kind,media_path,created_at')
        .eq('chat_id', widget.chatId)
        .or('kind.eq.image,kind.eq.video')
        .order('id', ascending: false)
        .limit(300);
    return List<Map<String, dynamic>>.from(rows);
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
                  const Text('معرض الذكريات',
                      style:
                          TextStyle(fontSize: _Fs.display, fontWeight: FontWeight.w700)),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => AlbumsScreen(chatId: widget.chatId))),
                    icon: const Icon(Icons.photo_album_rounded),
                    label: const Text('الألبومات'),
                  ),
                ]),
              ),
              Expanded(
                child: FutureBuilder<List<Map<String, dynamic>>>(
                  future: _future,
                  builder: (context, snap) {
                    if (snap.connectionState != ConnectionState.done) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snap.hasError) {
                      return const Center(child: Text('تعذر تحميل المعرض.'));
                    }
                    final items = (snap.data ?? const <Map<String, dynamic>>[])
                        .where((r) => r['media_path'] != null)
                        .toList();
                    if (items.isEmpty) {
                      return const Center(
                        child: Text('ما في صور ولا فيديو بعد.',
                            style: TextStyle(color: Color(0xAAFFFFFF))),
                      );
                    }
                    return GridView.builder(
                      padding: const EdgeInsets.all(_Sp.sm),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        mainAxisSpacing: 6,
                        crossAxisSpacing: 6,
                      ),
                      itemCount: items.length,
                      itemBuilder: (_, i) => GestureDetector(
                        // ضغطة مطوّلة: أضفها لألبوم
                        onLongPress: () => _addToAlbum(context, widget.chatId,
                            (items[i]['id'] as num).toInt()),
                        child: _MemoryTile(
                          kind: items[i]['kind'] as String,
                          path: items[i]['media_path'] as String,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ]),
          ),
        ),
      );
}

class _MemoryTile extends StatelessWidget {
  const _MemoryTile({required this.kind, required this.path});
  final String kind;
  final String path;

  @override
  Widget build(BuildContext context) {
    final isVideo = kind == 'video';
    return GestureDetector(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => isVideo
              ? VideoScreen(path: path)
              : ImageViewerScreen(path: path))),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Container(
          color: const Color(0x33000000),
          child: isVideo
              ? const Center(
                  child: Icon(Icons.play_circle_fill_rounded,
                      size: 40, color: Colors.white))
              : _ThumbImage(path: path),
        ),
      ),
    );
  }
}

class _ThumbImage extends StatelessWidget {
  const _ThumbImage({required this.path});
  final String path;

  @override
  Widget build(BuildContext context) => FutureBuilder<File?>(
        future: _MediaFiles.get(path),
        builder: (_, s) {
          final f = s.data;
          if (s.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator(strokeWidth: 2));
          }
          if (f == null) {
            return const Center(child: Icon(Icons.broken_image_rounded));
          }
          return Image.file(
            f,
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
            cacheWidth: 480,
            errorBuilder: (_, __, ___) =>
                const Center(child: Icon(Icons.broken_image_rounded)),
          );
        },
      );
}
