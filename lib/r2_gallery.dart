part of 'main.dart';

// ---------- الجولة الثانية: معرض المحادثة التلقائي (308) ----------

class GalleryScreen extends StatefulWidget {
  const GalleryScreen({super.key, required this.chatId});
  final String chatId;

  @override
  State<GalleryScreen> createState() => _GalleryState();
}

class _GalleryState extends State<GalleryScreen> {
  List<Map<String, dynamic>>? _rows;
  String? _err;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final media = await _net(
          _db
              .from('messages')
              .select('id,kind,body,media_path,duration_ms,created_at')
              .eq('chat_id', widget.chatId)
              .inFilter('kind', const ['image', 'video', 'file'])
              .order('id', ascending: false)
              .limit(600),
          t: const Duration(seconds: 25));
      // الروابط: النص مشفّر بالسيرفر، فنفلتره بالجهاز
      final texts = await _net(
          _db
              .from('messages')
              .select('id,kind,body,media_path,duration_ms,created_at')
              .eq('chat_id', widget.chatId)
              .eq('kind', 'text')
              .order('id', ascending: false)
              .limit(1500),
          t: const Duration(seconds: 25));
      final r = <Map<String, dynamic>>[
        for (final e in media) Map<String, dynamic>.from(e),
        for (final e in texts)
          if ('${e['body']}'.contains('http')) Map<String, dynamic>.from(e),
      ]..sort((a, b) => (b['id'] as int).compareTo(a['id'] as int));
      if (mounted) setState(() => _rows = [for (final e in r) Map<String, dynamic>.from(e)]);
    } catch (e) {
      if (mounted) setState(() => _err = _friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    List<Map<String, dynamic>> of(String k) => [for (final r in rows ?? const []) if (r['kind'] == k) r];
    final images = of('image'), videos = of('video'), files = of('file');
    final links = [for (final r in rows ?? const []) if (r['kind'] == 'text' && _firstUrl('${r['body']}') != null) r];
    Widget grid(List<Map<String, dynamic>> l, bool video) => l.isEmpty
        ? const Center(child: Text('ما في شي هنا بعد.'))
        : GridView.builder(
            padding: const EdgeInsets.all(8),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, mainAxisSpacing: 4, crossAxisSpacing: 4),
            itemCount: l.length,
            itemBuilder: (_, i) {
              final path = l[i]['media_path'] as String?;
              if (path == null) return const SizedBox.shrink();
              return GestureDetector(
                onTap: () => _r2Push(context, video ? VideoScreen(path: path) : ImageViewerScreen(path: path)),
                child: video ? const ColoredBox(color: Color(0x33FFFFFF), child: Center(child: Icon(Icons.play_circle_fill_rounded, size: 40))) : _GalleryThumb(path: path),
              );
            },
          );
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          title: const Text('معرض المحادثة'),
          backgroundColor: Colors.transparent,
          bottom: TabBar(tabs: [
            Tab(text: 'صور ${_Fmt.digits('${images.length}')}'),
            Tab(text: 'فيديو ${_Fmt.digits('${videos.length}')}'),
            Tab(text: 'ملفات ${_Fmt.digits('${files.length}')}'),
            Tab(text: 'روابط ${_Fmt.digits('${links.length}')}'),
          ]),
        ),
        body: Backdrop(
          child: SafeArea(
            child: _err != null
                ? Center(child: Text(_err!))
                : rows == null
                    ? const _SkeletonGrid()
                    : Padding(
                        padding: const EdgeInsets.only(top: 48),
                        child: TabBarView(children: [
                          grid(images, false),
                          grid(videos, true),
                          files.isEmpty
                              ? const Center(child: Text('ما في ملفات.'))
                              : ListView(children: [
                                  for (final f in files)
                                    ListTile(
                                      leading: const Icon(Icons.insert_drive_file_rounded),
                                      title: Text('${f['body'] ?? 'ملف'}'),
                                      subtitle: Text(_Fmt.date(DateTime.tryParse('${f['created_at']}')?.toLocal() ?? DateTime.now())),
                                      onTap: () => _toast(context, 'افتح الملف من المحادثة.'),
                                    ),
                                ]),
                          links.isEmpty
                              ? const Center(child: Text('ما في روابط.'))
                              : ListView(children: [
                                  for (final l in links)
                                    ListTile(
                                      leading: const Icon(Icons.link_rounded),
                                      title: Text(_firstUrl('${l['body']}') ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
                                      subtitle: Text(_Fmt.date(DateTime.tryParse('${l['created_at']}')?.toLocal() ?? DateTime.now())),
                                      onTap: () async {
                                        final u = _firstUrl('${l['body']}');
                                        if (u != null) {
                                          try {
                                            await launchUrl(Uri.parse(u), mode: LaunchMode.externalApplication);
                                          } catch (_) {}
                                        }
                                      },
                                    ),
                                ]),
                        ]),
                      ),
          ),
        ),
      ),
    );
  }
}

class _GalleryThumb extends StatefulWidget {
  const _GalleryThumb({required this.path});
  final String path;

  @override
  State<_GalleryThumb> createState() => _GalleryThumbState();
}

class _GalleryThumbState extends State<_GalleryThumb> {
  late final Future<File?> _f = _MediaFiles.get(widget.path);

  @override
  Widget build(BuildContext context) => FutureBuilder<File?>(
        future: _f,
        builder: (_, s) {
          final f = s.data;
          if (f == null) {
            return ColoredBox(
                color: const Color(0x22FFFFFF),
                child: Center(child: s.connectionState == ConnectionState.done ? const Icon(Icons.broken_image_rounded) : const CircularProgressIndicator(strokeWidth: 2)));
          }
          return Image.file(f, fit: BoxFit.cover, cacheWidth: 300);
        },
      );
}
