part of 'main.dart';

// ---------- الصوت والفيديو داخل الرسائل ----------

String _mmss(int ms) {
  final s = (ms / 1000).round();
  return '${_two(s ~/ 60)}:${_two(s % 60)}';
}

String _extOf(String path) {
  final i = path.lastIndexOf('.');
  return i < 0 ? 'mp4' : path.substring(i + 1).toLowerCase();
}

String _mimeForVideo(String path) {
  switch (_extOf(path)) {
    case 'mov':
      return 'video/quicktime';
    case '3gp':
      return 'video/3gpp';
    case 'webm':
      return 'video/webm';
    default:
      return 'video/mp4';
  }
}

/// يرفع ملف للتخزين وبعدها يضيف رسالة من نوعه (image / video / audio).
Future<void> _sendMedia({
  required String chatId,
  required File file,
  required String kind,
  required String ext,
  required String mime,
  int? durationMs,
}) async {
  final path = '$chatId/${DateTime.now().microsecondsSinceEpoch}.$ext';
  await _db.storage
      .from('chat-media')
      .upload(path, file, fileOptions: FileOptions(contentType: mime));
  await _db.from('messages').insert({
    'chat_id': chatId,
    'kind': kind,
    'media_path': path,
    'body': '',
    if (durationMs != null) 'duration_ms': durationMs,
  });
}

// ---------- تسجيل الصوت ----------

class RecordedClip {
  const RecordedClip(this.file, this.ms);
  final File file;
  final int ms;
}

class VoiceRecorder {
  final _rec = AudioRecorder();
  DateTime? _t0;

  /// false = المستخدم ما سمح بالمايك.
  Future<bool> start() async {
    if (!await _rec.hasPermission()) return false;
    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _rec.start(
      const RecordConfig(
          encoder: AudioEncoder.aacLc, bitRate: 64000, sampleRate: 44100),
      path: path,
    );
    _t0 = DateTime.now();
    return true;
  }

  Future<RecordedClip?> stop() async {
    final path = await _rec.stop();
    final t0 = _t0;
    _t0 = null;
    if (path == null || t0 == null) return null;
    return RecordedClip(
        File(path), DateTime.now().difference(t0).inMilliseconds);
  }

  Future<void> cancel() async {
    _t0 = null;
    try {
      await _rec.cancel();
    } catch (_) {}
  }

  Future<void> dispose() async {
    try {
      await _rec.dispose();
    } catch (_) {}
  }
}

// ---------- فقاعة الرسالة الصوتية ----------

class _VoiceBubble extends StatefulWidget {
  const _VoiceBubble({super.key, required this.path, required this.ms});
  final String path;
  final int ms;

  @override
  State<_VoiceBubble> createState() => _VoiceState();
}

class _VoiceState extends State<_VoiceBubble> {
  static VideoPlayerController? _active; // رسالة وحدة تشتغل بنفس الوقت
  VideoPlayerController? _c;
  bool _loading = false;
  bool _failed = false;
  double _speed = 1.0; // سرعة التشغيل: 1x أو 1.5x أو 2x

  void _cycleSpeed() {
    final next = _speed == 1.0 ? 1.5 : (_speed == 1.5 ? 2.0 : 1.0);
    setState(() => _speed = next);
    final c = _c;
    if (c != null) unawaited(c.setPlaybackSpeed(next));
  }

  @override
  void dispose() {
    final c = _c;
    if (c != null) {
      if (identical(_active, c)) _active = null;
      c.removeListener(_tick);
      c.dispose();
    }
    super.dispose();
  }

  void _tick() {
    if (mounted) setState(() {});
  }

  void _fail() {
    if (mounted) {
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  Future<void> _toggle() async {
    var c = _c;
    if (c == null) {
      setState(() => _loading = true);
      final url = await MediaUrls.get('chat-media', widget.path);
      if (url == null || !mounted) {
        _fail();
        return;
      }
      final nc = VideoPlayerController.networkUrl(Uri.parse(url));
      try {
        await nc.initialize();
      } catch (_) {
        await nc.dispose();
        _fail();
        return;
      }
      if (!mounted) {
        await nc.dispose();
        return;
      }
      nc.addListener(_tick);
      _c = nc;
      c = nc;
      unawaited(nc.setPlaybackSpeed(_speed));
      setState(() => _loading = false);
    }
    if (c.value.isPlaying) {
      await c.pause();
      return;
    }
    final d = c.value.duration;
    if (d > Duration.zero && c.value.position >= d) {
      await c.seekTo(Duration.zero);
    }
    final prev = _active;
    if (prev != null && !identical(prev, c)) {
      try {
        await prev.pause();
      } catch (_) {}
    }
    _active = c;
    await c.play();
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    final playing = c?.value.isPlaying ?? false;
    final total = (c != null && c.value.isInitialized)
        ? c.value.duration.inMilliseconds
        : widget.ms;
    final pos = c?.value.position.inMilliseconds ?? 0;
    final frac = total > 0 ? (pos / total).clamp(0.0, 1.0).toDouble() : 0.0;
    final shown = (playing || pos > 0) ? pos : total;
    return SizedBox(
      width: 210,
      child: Row(children: [
        _loading
            ? const SizedBox(
                width: 40,
                height: 40,
                child: Padding(
                    padding: EdgeInsets.all(8),
                    child: CircularProgressIndicator(strokeWidth: 2)))
            : IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                iconSize: 36,
                onPressed: _failed ? null : _toggle,
                icon: Icon(_failed
                    ? Icons.error_outline
                    : (playing
                        ? Icons.pause_circle_filled
                        : Icons.play_circle_fill)),
              ),
        const SizedBox(width: 6),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LinearProgressIndicator(
                value: frac,
                minHeight: 4,
                borderRadius: BorderRadius.circular(4),
                backgroundColor: const Color(0x33FFFFFF),
              ),
              const SizedBox(height: 4),
              Text(_mmss(shown),
                  style:
                      const TextStyle(fontSize: 11, color: Color(0xCCFFFFFF))),
            ],
          ),
        ),
        const SizedBox(width: 6),
        GestureDetector(
          onTap: _cycleSpeed,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0x33FFFFFF),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              _speed == 1.0 ? '1x' : (_speed == 1.5 ? '1.5x' : '2x'),
              style: const TextStyle(fontSize: 11, color: Colors.white),
            ),
          ),
        ),
      ]),
    );
  }
}

// ---------- الفيديو ----------

class _VideoTile extends StatelessWidget {
  const _VideoTile({required this.ms});
  final int ms;

  @override
  Widget build(BuildContext context) => Container(
        width: 220,
        height: 150,
        decoration: BoxDecoration(
            color: const Color(0x66000000),
            borderRadius: BorderRadius.circular(16)),
        child: Stack(alignment: Alignment.center, children: [
          const Icon(Icons.play_circle_fill, size: 56, color: Colors.white),
          if (ms > 0)
            PositionedDirectional(
              bottom: 8,
              end: 10,
              child: Text(_mmss(ms),
                  style: const TextStyle(fontSize: 12, color: Colors.white)),
            ),
        ]),
      );
}

class VideoScreen extends StatefulWidget {
  const VideoScreen({super.key, required this.path});
  final String path;

  @override
  State<VideoScreen> createState() => _VideoScreenState();
}

class _VideoScreenState extends State<VideoScreen> {
  VideoPlayerController? _c;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final url = await MediaUrls.get('chat-media', widget.path);
    if (url == null) {
      if (mounted) setState(() => _failed = true);
      return;
    }
    final c = VideoPlayerController.networkUrl(Uri.parse(url));
    try {
      await c.initialize();
    } catch (_) {
      await c.dispose();
      if (mounted) setState(() => _failed = true);
      return;
    }
    if (!mounted) {
      await c.dispose();
      return;
    }
    c.addListener(_tick);
    setState(() => _c = c);
    await c.play();
  }

  void _tick() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    final c = _c;
    if (c != null) {
      c.removeListener(_tick);
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black, elevation: 0),
      body: Center(
        child: _failed
            ? const Text('تعذر تشغيل الفيديو.')
            : c == null
                ? const CircularProgressIndicator()
                : Column(mainAxisSize: MainAxisSize.min, children: [
                    AspectRatio(
                      aspectRatio:
                          c.value.aspectRatio > 0 ? c.value.aspectRatio : 16 / 9,
                      child: VideoPlayer(c),
                    ),
                    VideoProgressIndicator(c, allowScrubbing: true),
                    IconButton(
                      iconSize: 44,
                      onPressed: () =>
                          c.value.isPlaying ? c.pause() : c.play(),
                      icon: Icon(c.value.isPlaying
                          ? Icons.pause_circle_filled
                          : Icons.play_circle_fill),
                    ),
                  ]),
      ),
    );
  }
}
