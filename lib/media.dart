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

/// نسخة محلية من الصور (تنزل مرة وحدة بس، توفّر الإنترنت وتفتح أسرع)
class _MediaFiles {
  static final _inflight = <String, Future<File?>>{};
  static bool _cleaned = false;

  static Future<Directory> _dir() async {
    final d = Directory('${(await getTemporaryDirectory()).path}/media_cache');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  static Future<File?> get(String path) =>
      _inflight[path] ??= _get(path).whenComplete(() => _inflight.remove(path));

  static Future<File?> _get(String path) async {
    try {
      final dir = await _dir();
      if (!_cleaned) {
        _cleaned = true;
        unawaited(_clean(dir).then((_) => _trimMediaCache()));
      }
      final f = File('${dir.path}/${path.replaceAll('/', '_')}');
      if (await f.exists() && await f.length() > 0) return f;
      final url = await MediaUrls.get('chat-media', path);
      if (url == null) return null;
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
      try {
        final req = await client.getUrl(Uri.parse(url));
        final res = await req.close();
        if (res.statusCode != 200) return null;
        final tmp = File('${f.path}.part');
        await res.pipe(tmp.openWrite());
        await tmp.rename(f.path);
        return f;
      } finally {
        client.close(force: true);
      }
    } catch (_) {
      return null;
    }
  }

  /// نحذف الصور اللي ما انفتحت من 30 يوم
  static Future<void> _clean(Directory dir) async {
    try {
      final old = DateTime.now().subtract(const Duration(days: 30));
      await for (final e in dir.list()) {
        if (e is File && (await e.lastModified()).isBefore(old)) await e.delete();
      }
    } catch (_) {}
  }

  static Future<void> clearAll() async {
    try {
      final d = await _dir();
      await d.delete(recursive: true);
    } catch (_) {}
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

String _hhmm(DateTime? t) => t == null ? '' : _Fmt.time(t);

/// يسأل: من المعرض أو بالكاميرا؟ (ومعه خيار الحذف إذا طُلب)
Future<String?> _photoSheet(BuildContext context, {bool canRemove = false}) =>
    showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.photo_library_rounded),
            title: const Text('من المعرض'),
            onTap: () => Navigator.pop(ctx, 'gallery'),
          ),
          ListTile(
            leading: const Icon(Icons.photo_camera_rounded),
            title: const Text('تصوير بالكاميرا'),
            onTap: () => Navigator.pop(ctx, 'camera'),
          ),
          if (canRemove)
            ListTile(
              leading:
                  const Icon(Icons.delete_outline_rounded, color: Color(0xFFFF6B60)),
              title: const Text('حذف الصورة'),
              onTap: () => Navigator.pop(ctx, 'remove'),
            ),
        ]),
      ),
    );

// ---------- صورة شخصية ----------

class _Avatar extends StatefulWidget {
  const _Avatar({super.key, this.path, this.radius = 22, this.gender});
  final String? path;
  final double radius;
  final String? gender; // male | female (يحدد لون الصورة الافتراضية)

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
            backgroundColor: _genderColor(widget.gender),
            backgroundImage: url != null ? NetworkImage(url) : null,
            child: url == null
                ? Icon(Icons.person_rounded, color: Colors.white, size: widget.radius)
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
  late Future<File?> _file = _MediaFiles.get(widget.path);
  late Future<String?> _f = MediaUrls.get('chat-media', widget.path);

  @override
  void didUpdateWidget(_NetImage old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path) {
      _file = _MediaFiles.get(widget.path);
      _f = MediaUrls.get('chat-media', widget.path);
    }
  }

  Widget _box(Widget child) => widget.full
      ? Center(child: child)
      : SizedBox(width: 220, height: 220, child: Center(child: child));

  @override
  Widget build(BuildContext context) => FutureBuilder<File?>(
        future: _file,
        builder: (_, fs) {
          if (fs.connectionState != ConnectionState.done) {
            return _box(const CircularProgressIndicator(strokeWidth: 2));
          }
          final file = fs.data;
          if (file != null) {
            return ClipRRect(
              borderRadius: BorderRadius.circular(widget.full ? 0 : 16),
              child: Image.file(
                file,
                width: widget.full ? null : 220,
                height: widget.full ? null : 220,
                cacheWidth: widget.full ? 1800 : 480,
                fit: widget.full ? BoxFit.contain : BoxFit.cover,
                errorBuilder: (_, __, ___) =>
                    _box(const Icon(Icons.broken_image_rounded, size: 36)),
              ),
            );
          }
          return _urlImage();
        },
      );

  // لو ما قدرنا ننزل نسخة محلية: نعرضها من الرابط مباشرة
  Widget _urlImage() => FutureBuilder<String?>(
        future: _f,
        builder: (_, s) {
          if (s.connectionState != ConnectionState.done) {
            return _box(const CircularProgressIndicator(strokeWidth: 2));
          }
          final url = s.data;
          if (url == null) {
            return _box(const Icon(Icons.broken_image_rounded, size: 36));
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
                  _box(const Icon(Icons.broken_image_rounded, size: 36)),
            ),
          );
        },
      );
}

class ImageViewerScreen extends StatefulWidget {
  const ImageViewerScreen({super.key, required this.path, this.paths});
  final String path;

  /// قائمة صور للتنقل بينها بالسحب (الافتراضي: صور المحادثة)
  final List<String>? paths;

  @override
  State<ImageViewerScreen> createState() => _ImageViewerState();
}

class _ImageViewerState extends State<ImageViewerScreen> {
  late final List<String> _list = () {
    final l = widget.paths ?? _ChatMedia.images;
    return l.contains(widget.path) ? l : [widget.path];
  }();
  late int _i = _list.indexOf(widget.path);
  late final PageController _pc = PageController(initialPage: _i);
  bool _zoomed = false;

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          elevation: 0,
          title: _list.length > 1
              ? Text('${_Fmt.digits('${_i + 1}')} / ${_Fmt.digits('${_list.length}')}', style: const TextStyle(fontSize: _Fs.body))
              : null,
          actions: [
            IconButton(
              tooltip: 'حفظ في المعرض',
              icon: const Icon(Icons.download_rounded),
              onPressed: () => _saveImage(context, _list[_i]),
            ),
          ],
        ),
        body: PageView.builder(
          controller: _pc,
          physics: _zoomed ? const NeverScrollableScrollPhysics() : null,
          itemCount: _list.length,
          onPageChanged: (v) => setState(() => _i = v),
          itemBuilder: (_, i) => _ZoomPage(
            key: ValueKey('zp-${_list[i]}'),
            path: _list[i],
            hero: _list[i] == widget.path,
            onZoom: (z) {
              if (z != _zoomed) setState(() => _zoomed = z);
            },
          ),
        ),
      );
}

/// صفحة صورة بتكبير بالقرص وبضغطتين
class _ZoomPage extends StatefulWidget {
  const _ZoomPage({super.key, required this.path, required this.hero, required this.onZoom});
  final String path;
  final bool hero;
  final void Function(bool zoomed) onZoom;

  @override
  State<_ZoomPage> createState() => _ZoomPageState();
}

class _ZoomPageState extends State<_ZoomPage> {
  final _tc = TransformationController();
  Offset _tap = Offset.zero;

  @override
  void dispose() {
    _tc.dispose();
    super.dispose();
  }

  bool get _isZoomed => _tc.value.getMaxScaleOnAxis() > 1.05;

  void _onDouble() {
    if (_isZoomed) {
      _tc.value = Matrix4.identity();
      widget.onZoom(false);
    } else {
      const k = 2.5;
      _tc.value = Matrix4(k, 0, 0, 0, 0, k, 0, 0, 0, 0, 1, 0, -_tap.dx * (k - 1), -_tap.dy * (k - 1), 0, 1);
      widget.onZoom(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final img = _NetImage(path: widget.path, full: true);
    return GestureDetector(
      onDoubleTapDown: (d) => _tap = d.localPosition,
      onDoubleTap: _onDouble,
      child: InteractiveViewer(
        transformationController: _tc,
        maxScale: 5,
        onInteractionEnd: (_) => widget.onZoom(_isZoomed),
        child: Center(child: widget.hero ? Hero(tag: 'img-${widget.path}', child: img) : img),
      ),
    );
  }
}

// ---------- حفظ الصورة في معرض الجوال ----------

Future<void> _saveImage(BuildContext context, String path) async {
  try {
    final cached = await _MediaFiles.get(path);
    if (cached == null) throw Exception('no file');
    // نسخة باسم فيه الامتداد الصحيح حتى يتعرف عليها المعرض
    final dir = await getTemporaryDirectory();
    final f = await cached.copy(
        '${dir.path}/save_${DateTime.now().millisecondsSinceEpoch}.${_extFor(path)}');
    await Gal.putImage(f.path, album: appName);
    if (context.mounted) _toast(context, 'تم حفظ الصورة في المعرض');
  } catch (_) {
    if (context.mounted) {
      _toast(context, 'تعذر حفظ الصورة. تأكد من إذن الصور بإعدادات الجوال.');
    }
  }
}
