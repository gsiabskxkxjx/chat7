part of 'main.dart';

// ---------- الوسائط: روابط موقّعة + صور ----------

class _Signed {
  const _Signed(this.url, this.at);
  final String url;
  final DateTime at;
}

class MediaUrls {
  static final _cache = <String, _Signed>{};

  /// يرجع رابط مؤقت (ساعة) لملف خاص بالـ Storage، ويحتفظ به 50 دقيقة.
  static Future<String?> get(String bucket, String path) async {
    final key = '$bucket/$path';
    final c = _cache[key];
    if (c != null &&
        DateTime.now().difference(c.at) < const Duration(minutes: 50)) {
      return c.url;
    }
    try {
      final url = await _db.storage.from(bucket).createSignedUrl(path, 3600);
      _cache[key] = _Signed(url, DateTime.now());
      return url;
    } catch (_) {
      return null;
    }
  }
}

String _extFor(String path) {
  final p = path.toLowerCase();
  if (p.endsWith('.png')) return 'png';
  if (p.endsWith('.webp')) return 'webp';
  return 'jpg';
}

String _mimeFor(String path) {
  switch (_extFor(path)) {
    case 'png':
      return 'image/png';
    case 'webp':
      return 'image/webp';
    default:
      return 'image/jpeg';
  }
}

String _hhmm(DateTime? t) =>
    t == null ? '' : '${_two(t.hour)}:${_two(t.minute)}';

/// يسأل: من المعرض أو بالكاميرا؟ (ومعه خيار الحذف إذا طُلب)
Future<String?> _photoSheet(BuildContext context, {bool canRemove = false}) =>
    showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('من المعرض'),
            onTap: () => Navigator.pop(ctx, 'gallery'),
          ),
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('تصوير بالكاميرا'),
            onTap: () => Navigator.pop(ctx, 'camera'),
          ),
          if (canRemove)
            ListTile(
              leading:
                  const Icon(Icons.delete_outline, color: Color(0xFFFF6B60)),
              title: const Text('حذف الصورة'),
              onTap: () => Navigator.pop(ctx, 'remove'),
            ),
        ]),
      ),
    );

// ---------- صورة شخصية ----------

class _Avatar extends StatefulWidget {
  const _Avatar({super.key, this.path, this.radius = 22});
  final String? path;
  final double radius;

  @override
  State<_Avatar> createState() => _AvatarState();
}

class _AvatarState extends State<_Avatar> {
  Future<String?>? _f;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_Avatar old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path) _load();
  }

  void _load() {
    final p = widget.path;
    _f = p == null ? null : MediaUrls.get('avatars', p);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<String?>(
        future: _f,
        builder: (_, s) {
          final url = s.data;
          return CircleAvatar(
            radius: widget.radius,
            backgroundColor: _blue,
            backgroundImage: url != null ? NetworkImage(url) : null,
            child: url == null
                ? Icon(Icons.person, color: Colors.white, size: widget.radius)
                : null,
          );
        },
      );
}

// ---------- صورة داخل المحادثة ----------

class _NetImage extends StatefulWidget {
  const _NetImage({super.key, required this.path, this.full = false});
  final String path;
  final bool full;

  @override
  State<_NetImage> createState() => _NetImageState();
}

class _NetImageState extends State<_NetImage> {
  late Future<String?> _f = MediaUrls.get('chat-media', widget.path);

  @override
  void didUpdateWidget(_NetImage old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path) {
      _f = MediaUrls.get('chat-media', widget.path);
    }
  }

  Widget _box(Widget child) => widget.full
      ? Center(child: child)
      : SizedBox(width: 220, height: 220, child: Center(child: child));

  @override
  Widget build(BuildContext context) => FutureBuilder<String?>(
        future: _f,
        builder: (_, s) {
          if (s.connectionState != ConnectionState.done) {
            return _box(const CircularProgressIndicator(strokeWidth: 2));
          }
          final url = s.data;
          if (url == null) {
            return _box(const Icon(Icons.broken_image_outlined, size: 36));
          }
          return ClipRRect(
            borderRadius: BorderRadius.circular(widget.full ? 0 : 16),
            child: Image.network(
              url,
              width: widget.full ? null : 220,
              height: widget.full ? null : 220,
              fit: widget.full ? BoxFit.contain : BoxFit.cover,
              loadingBuilder: (_, child, p) => p == null
                  ? child
                  : _box(const CircularProgressIndicator(strokeWidth: 2)),
              errorBuilder: (_, __, ___) =>
                  _box(const Icon(Icons.broken_image_outlined, size: 36)),
            ),
          );
        },
      );
}

class ImageViewerScreen extends StatelessWidget {
  const ImageViewerScreen({super.key, required this.path});
  final String path;

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(backgroundColor: Colors.black, elevation: 0),
        body: Center(
          child: InteractiveViewer(
            maxScale: 5,
            child: _NetImage(path: path, full: true),
          ),
        ),
      );
}
