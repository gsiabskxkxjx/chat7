part of 'main.dart';

// ---------- تعديل الصورة قبل الإرسال، بطاقة ملوّنة، فيديو دائري، ملفات، نبضة ----------

// ===== تعديل الصورة: فلاتر، تدوير، قص =====

const _filterNames = ['بدون', 'أبيض وأسود', 'دافئ', 'بارد', 'قديم', 'مشرق'];
const List<List<double>?> _filterMatrices = [
  null,
  [0.2126, 0.7152, 0.0722, 0, 0, 0.2126, 0.7152, 0.0722, 0, 0, 0.2126, 0.7152, 0.0722, 0, 0, 0, 0, 0, 1, 0],
  [1.1, 0, 0, 0, 12, 0, 1.0, 0, 0, 4, 0, 0, 0.88, 0, -10, 0, 0, 0, 1, 0],
  [0.9, 0, 0, 0, -8, 0, 1.0, 0, 0, 0, 0, 0, 1.12, 0, 14, 0, 0, 0, 1, 0],
  [0.393, 0.769, 0.189, 0, 0, 0.349, 0.686, 0.168, 0, 0, 0.272, 0.534, 0.131, 0, 0, 0, 0, 0, 1, 0],
  [1.18, 0, 0, 0, 12, 0, 1.18, 0, 0, 12, 0, 0, 1.18, 0, 12, 0, 0, 0, 1, 0],
];
const _cropNames = ['الأصل', 'مربع', 'طولي'];

class _ImageEditScreen extends StatefulWidget {
  const _ImageEditScreen({required this.file});
  final File file;

  @override
  State<_ImageEditScreen> createState() => _ImageEditState();
}

class _ImageEditState extends State<_ImageEditScreen> {
  final _key = GlobalKey();
  int _turns = 0, _filter = 0, _crop = 0;
  double? _aspect; // عرض/ارتفاع الصورة الأصلية
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_readSize());
  }

  Future<void> _readSize() async {
    try {
      final img = await decodeImageFromList(await widget.file.readAsBytes());
      if (mounted) setState(() => _aspect = img.width / img.height);
      img.dispose();
    } catch (_) {
      if (mounted) setState(() => _aspect = 1);
    }
  }

  double get _boxAspect {
    if (_crop == 1) return 1;
    if (_crop == 2) return 0.8;
    final a = _aspect ?? 1;
    return _turns.isOdd ? 1 / a : a;
  }

  bool get _untouched => _turns == 0 && _filter == 0 && _crop == 0;

  Future<void> _done() async {
    if (_untouched) {
      Navigator.pop(context, widget.file);
      return;
    }
    setState(() => _busy = true);
    try {
      final box = _key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final longest = math.max(box.size.width, box.size.height);
      final img = await box.toImage(pixelRatio: 1600 / longest);
      final data = await img.toByteData(format: ImageByteFormat.png);
      img.dispose();
      final dir = await getTemporaryDirectory();
      final f = File('${dir.path}/edit_${DateTime.now().millisecondsSinceEpoch}.png');
      await f.writeAsBytes(data!.buffer.asUint8List());
      if (mounted) Navigator.pop(context, f);
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      _toast(context, 'تعذر حفظ التعديل، نرسلها بدون تعديل.');
      Navigator.pop(context, widget.file);
    }
  }

  Widget _preview(int filter, {double? size}) {
    Widget img = RotatedBox(
      quarterTurns: _turns,
      child: Image.file(widget.file, fit: BoxFit.cover, cacheWidth: size == null ? null : 200),
    );
    final m = _filterMatrices[filter];
    if (m != null) img = ColorFiltered(colorFilter: ColorFilter.matrix(m), child: img);
    return img;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          title: const Text('تعديل الصورة'),
          actions: [
            IconButton(
                tooltip: 'تدوير',
                onPressed: () => setState(() => _turns = (_turns + 1) % 4),
                icon: const Icon(Icons.rotate_90_degrees_ccw_rounded)),
          ],
        ),
        body: SafeArea(
          child: Column(children: [
            Expanded(
              child: Center(
                child: _aspect == null
                    ? const CircularProgressIndicator()
                    : RepaintBoundary(
                        key: _key,
                        child: AspectRatio(
                          aspectRatio: _boxAspect,
                          child: ClipRect(
                            child: SizedBox.expand(child: _preview(_filter)),
                          ),
                        ),
                      ),
              ),
            ),
            SizedBox(
              height: 92,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                itemCount: _filterNames.length,
                itemBuilder: (_, i) => GestureDetector(
                  onTap: () => setState(() => _filter = i),
                  child: Padding(
                    padding: const EdgeInsets.all(5),
                    child: Column(children: [
                      Container(
                        width: 58,
                        height: 58,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: _filter == i ? Colors.white : Colors.transparent, width: 2),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: _preview(i, size: 58),
                      ),
                      const SizedBox(height: _Sp.xs),
                      Text(_filterNames[i], style: const TextStyle(fontSize: _Fs.caption)),
                    ]),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              child: Row(children: [
                for (var i = 0; i < _cropNames.length; i++)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 8),
                    child: ChoiceChip(
                      label: Text(_cropNames[i]),
                      selected: _crop == i,
                      onSelected: (_) => setState(() => _crop = i),
                    ),
                  ),
                const Spacer(),
                _Btn(label: 'إرسال', onTap: _done, busy: _busy),
              ]),
            ),
          ]),
        ),
      );
}

// ===== بطاقة ملوّنة (رسالة مهمة) =====

const _cardColors = [
  [Color(0xFFFF5FA2), Color(0xFFBF5AF2)],
  [Color(0xFF0A84FF), Color(0xFF30D5C8)],
  [Color(0xFFFF9F0A), Color(0xFFFF453A)],
  [Color(0xFF34C759), Color(0xFF0A84FF)],
  [Color(0xFF5E5CE6), Color(0xFF1C1C3A)],
  [Color(0xFFFFD60A), Color(0xFFFF9F0A)],
  [Color(0xFF2C2C2E), Color(0xFF000000)],
  [Color(0xFFFF7EB6), Color(0xFFFFB37A)],
];

class _CardMsg extends StatelessWidget {
  const _CardMsg({required this.text, required this.color});
  final String text;
  final int color;

  @override
  Widget build(BuildContext context) {
    final c = _cardColors[color.abs() % _cardColors.length];
    return Container(
      constraints: const BoxConstraints(minWidth: 200, minHeight: 120),
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight, colors: c),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [BoxShadow(color: c.first.withValues(alpha: 0.45), blurRadius: 18)],
      ),
      alignment: Alignment.center,
      child: Text(text,
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: _Fs.display * _Prefs.fontScale.value,
              height: 1.5,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              shadows: const [Shadow(color: Color(0x66000000), blurRadius: 6)])),
    );
  }
}

// ===== فيديو دائري =====

class _VideoNote extends StatefulWidget {
  const _VideoNote({super.key, required this.path, required this.ms});
  final String path;
  final int ms;

  @override
  State<_VideoNote> createState() => _VideoNoteState();
}

class _VideoNoteState extends State<_VideoNote> {
  VideoPlayerController? _c;
  bool _loading = false;

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    final c = _c;
    if (c != null) {
      if (c.value.isPlaying) {
        await c.pause();
      } else {
        if (c.value.position >= c.value.duration) await c.seekTo(Duration.zero);
        await c.play();
      }
      return;
    }
    setState(() => _loading = true);
    final f = await _MediaFiles.get(widget.path);
    if (!mounted) return;
    if (f == null) {
      setState(() => _loading = false);
      _toast(context, 'تعذر تحميل الفيديو.');
      return;
    }
    final nc = VideoPlayerController.file(f);
    try {
      await nc.initialize();
    } catch (_) {
      await nc.dispose();
      if (mounted) setState(() => _loading = false);
      return;
    }
    if (!mounted) {
      await nc.dispose();
      return;
    }
    nc.addListener(() {
      if (mounted) setState(() {});
    });
    setState(() {
      _c = nc;
      _loading = false;
    });
    await nc.play();
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    final ready = c != null && c.value.isInitialized;
    final playing = ready && c.value.isPlaying;
    final total = ready ? c.value.duration.inMilliseconds : widget.ms;
    final pos = ready ? c.value.position.inMilliseconds : 0;
    final secs = ((playing ? total - pos : total) / 1000).ceil();
    return GestureDetector(
      onTap: _toggle,
      child: SizedBox(
        width: 210,
        height: 210,
        child: Stack(alignment: Alignment.center, children: [
          ClipOval(
            child: SizedBox(
              width: 200,
              height: 200,
              child: ready
                  ? FittedBox(
                      fit: BoxFit.cover,
                      clipBehavior: Clip.hardEdge,
                      child: SizedBox(
                          width: c.value.size.width,
                          height: c.value.size.height,
                          child: VideoPlayer(c)),
                    )
                  : const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                            colors: [Color(0x660A84FF), Color(0x66FF5FA2)]),
                      ),
                    ),
            ),
          ),
          SizedBox(
            width: 208,
            height: 208,
            child: CircularProgressIndicator(
              value: total > 0 ? (pos / total).clamp(0.0, 1.0) : 0,
              strokeWidth: 3,
              backgroundColor: const Color(0x33FFFFFF),
              color: Colors.white,
            ),
          ),
          if (_loading)
            const CircularProgressIndicator()
          else if (!playing)
            const Icon(Icons.play_arrow_rounded, size: 56, color: Colors.white),
          PositionedDirectional(
            bottom: 14,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: _Sp.sm, vertical: 2),
              decoration: BoxDecoration(
                  color: const Color(0x88000000), borderRadius: BorderRadius.circular(10)),
              child: Text('0:${_two(secs.clamp(0, 59))}',
                  style: const TextStyle(fontSize: _Fs.small, color: Colors.white)),
            ),
          ),
        ]),
      ),
    );
  }
}

// ===== ملفات و PDF =====

String _sizeLabel(int b) {
  if (b <= 0) return '';
  if (b < 1024) return '$b بايت';
  if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(0)} كيلو';
  return '${(b / (1024 * 1024)).toStringAsFixed(1)} ميجا';
}

String _fileMime(String name) {
  final e = name.toLowerCase().split('.').last;
  return switch (e) {
    'pdf' => 'application/pdf',
    'doc' => 'application/msword',
    'docx' => 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'xls' => 'application/vnd.ms-excel',
    'xlsx' => 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'ppt' => 'application/vnd.ms-powerpoint',
    'pptx' => 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    'txt' => 'text/plain',
    'zip' => 'application/zip',
    'mp3' => 'audio/mpeg',
    'jpg' || 'jpeg' => 'image/jpeg',
    'png' => 'image/png',
    _ => 'application/octet-stream',
  };
}

IconData _fileIcon(String name) {
  final e = name.toLowerCase().split('.').last;
  return switch (e) {
    'pdf' => Icons.picture_as_pdf_rounded,
    'doc' || 'docx' || 'txt' => Icons.description_rounded,
    'xls' || 'xlsx' => Icons.table_chart_rounded,
    'ppt' || 'pptx' => Icons.slideshow_rounded,
    'zip' => Icons.folder_zip_rounded,
    'mp3' || 'm4a' || 'wav' => Icons.audio_file_rounded,
    _ => Icons.insert_drive_file_rounded,
  };
}

class _FileTile extends StatefulWidget {
  const _FileTile({required this.path, required this.name, required this.size});
  final String path;
  final String name;
  final int size;

  @override
  State<_FileTile> createState() => _FileTileState();
}

class _FileTileState extends State<_FileTile> {
  bool _busy = false;

  Future<void> _open() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final f = await _MediaFiles.get(widget.path);
      if (f == null) throw Exception('no file');
      final dir = await getTemporaryDirectory();
      final safe = widget.name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final named = await f.copy('${dir.path}/$safe');
      await SharePlus.instance.share(ShareParams(files: [XFile(named.path)]));
    } catch (_) {
      if (mounted) _toast(context, 'تعذر فتح الملف.');
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: _open,
        child: Container(
          constraints: const BoxConstraints(minWidth: 200, maxWidth: 260),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0x26000000),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            _busy
                ? const SizedBox(
                    width: 36, height: 36, child: Padding(padding: EdgeInsets.all(_Sp.sm), child: CircularProgressIndicator(strokeWidth: 2)))
                : Icon(_fileIcon(widget.name), size: 36, color: Colors.white),
            const SizedBox(width: 10),
            Flexible(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(widget.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.white)),
                Text('${_sizeLabel(widget.size)} · اضغط تفتحه',
                    style: const TextStyle(fontSize: _Fs.caption, color: Color(0xB3FFFFFF))),
              ]),
            ),
          ]),
        ),
      );
}

// ===== إرسال: بطاقة، نبضة، فيديو دائري، ملف =====

extension _ChatMedia on _ChatState {
  Future<void> _sendCard() async {
    final c = TextEditingController();
    var color = 0;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('بطاقة ملوّنة'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: c,
              autofocus: true,
              maxLength: 200,
              maxLines: 3,
              decoration: const InputDecoration(hintText: 'رسالة مهمة تطلع كبيرة وملوّنة'),
            ),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (var i = 0; i < _cardColors.length; i++)
                GestureDetector(
                  onTap: () => set(() => color = i),
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(colors: _cardColors[i]),
                      border: Border.all(
                          color: color == i ? Colors.white : Colors.transparent, width: 3),
                    ),
                  ),
                ),
            ]),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('أرسل')),
          ],
        ),
      ),
    );
    final t = c.text.trim();
    c.dispose();
    if (ok != true || t.isEmpty) return;
    try {
      await _db.from('messages').insert(
          {'chat_id': widget.chat.id, 'kind': 'card', 'body': t, 'duration_ms': color});
    } on PostgrestException catch (e) {
      if (mounted) {
        _toast(context,
            e.message.contains('kind') ? 'البطاقات تحتاج تحديث السيرفر (update_4).' : 'تعذر الإرسال.');
      }
    } catch (_) {
      if (mounted) _toast(context, 'تعذر الإرسال.');
    }
  }

  /// نبضة: صوت 5 ثواني ينرسل لحاله
  Future<void> _sendPulse() async {
    await _startRec();
    if (!_recording) return;
    Timer(const Duration(seconds: 5), () => unawaited(_finishRec(true)));
  }

  Future<void> _recordVideoNote() async {
    if (_blockedByTrust()) return;
    final okExplain = await _explainOnce(context,
        key: 'camera_vnote',
        icon: Icons.videocam_rounded,
        title: 'فيديو دائري',
        text: 'نحتاج الكاميرا والمايك حتى تسجل فيديو قصير (لين 30 ثانية) بالكاميرا الأمامية.');
    if (!okExplain || !mounted) return;
    XFile? x;
    try {
      x = await _picker.pickVideo(
          source: ImageSource.camera,
          preferredCameraDevice: CameraDevice.front,
          maxDuration: const Duration(seconds: 30));
    } catch (_) {
      if (mounted) _toast(context, 'تعذر فتح الكاميرا.');
      return;
    }
    if (x == null || !mounted) return;
    final original = File(x.path);
    if (await original.length() > 6 * 1024 * 1024 && mounted) {
      _toast(context, 'نضغط الفيديو قبل الإرسال...');
    }
    final file = await _compressVideo(original);
    if (await file.length() > 25 * 1024 * 1024) {
      await _dropTemp(file, original);
      if (mounted) _toast(context, 'الفيديو كبير، الحد 25 ميجا.');
      return;
    }
    var ms = 0;
    try {
      final vc = VideoPlayerController.file(file);
      await vc.initialize();
      ms = vc.value.duration.inMilliseconds;
      await vc.dispose();
    } catch (_) {}
    if (!mounted) return;
    setState(() => _uploading = true);
    try {
      await _sendMedia(
          chatId: widget.chat.id,
          file: file,
          kind: 'vnote',
          ext: _extOf(file.path),
          mime: _mimeForVideo(file.path),
          durationMs: ms);
    } on PostgrestException catch (e) {
      if (mounted) {
        _toast(
            context,
            e.message.contains('media_locked')
                ? 'الفيديو ينفتح لما الطرفين يضغطون «أثق فيه».'
                : e.message.contains('kind')
                    ? 'الفيديو الدائري يحتاج تحديث السيرفر (update_4).'
                    : 'تعذر الإرسال.');
      }
    } catch (_) {
      if (mounted) _toast(context, 'تعذر الإرسال، تأكد من الإنترنت.');
    }
    await _dropTemp(file, original);
    if (mounted) setState(() => _uploading = false);
  }

  Future<void> _sendFile() async {
    if (_blockedByTrust()) return;
    XFile? f;
    var size = 0;
    try {
      f = await openFile();
      if (f != null) size = await f.length();
    } catch (_) {
      if (mounted) _toast(context, 'تعذر فتح الملفات.');
      return;
    }
    final local = f?.path;
    if (f == null || local == null || local.isEmpty || !mounted) return;
    if (size > 25 * 1024 * 1024) {
      _toast(context, 'الملف كبير، الحد 25 ميجا.');
      return;
    }
    final name = f.name.length > 120 ? f.name.substring(f.name.length - 120) : f.name;
    var ext = name.contains('.') ? name.split('.').last.toLowerCase() : 'bin';
    if (!RegExp(r'^[a-z0-9]{1,8}$').hasMatch(ext)) ext = 'bin';
    setState(() => _uploading = true);
    try {
      final path = '${widget.chat.id}/${DateTime.now().microsecondsSinceEpoch}_file.$ext';
      await _db.storage.from('chat-media').upload(path, File(local),
          fileOptions: FileOptions(contentType: _fileMime(name)));
      try {
        await _db.from('messages').insert({
          'chat_id': widget.chat.id,
          'kind': 'file',
          'media_path': path,
          'body': name,
          'duration_ms': size,
        });
      } catch (_) {
        try {
          await _db.storage.from('chat-media').remove([path]);
        } catch (_) {}
        rethrow;
      }
    } on PostgrestException catch (e) {
      if (mounted) {
        _toast(
            context,
            e.message.contains('media_locked')
                ? 'الملفات تنفتح لما الطرفين يضغطون «أثق فيه».'
                : e.message.contains('kind')
                    ? 'الملفات تحتاج تحديث السيرفر (update_4).'
                    : 'تعذر الإرسال.');
      }
    } catch (_) {
      if (mounted) _toast(context, 'تعذر الإرسال، تأكد من الإنترنت.');
    }
    if (mounted) setState(() => _uploading = false);
  }
}

// ===== شكل ولون الفقاعات وإطار الصورة (تخصيص محلي) =====

const _bubblePalette = [
  Color(0xFF0A84FF), Color(0xFFFF5FA2), Color(0xFFBF5AF2), Color(0xFF34C759),
  Color(0xFFFF9F0A), Color(0xFF30B0C7), Color(0xFFFF453A), Color(0xFF3A3A4A),
];

const _ringStyles = [
  'لون الثيم', 'ذهبي', 'قوس قزح', 'وردي', 'بدون',
];

List<Color>? _ringColors(int style, Color accent) => switch (style) {
      1 => const [Color(0xFFFFE08A), Color(0xFFC9932C), Color(0xFFFFE08A)],
      2 => const [Color(0xFFFF453A), Color(0xFFFFD60A), Color(0xFF34C759), Color(0xFF0A84FF), Color(0xFFBF5AF2)],
      3 => const [Color(0xFFFF5FA2), Color(0xFFFFB3D1)],
      4 => null,
      _ => [accent, const Color(0xFFFF7EB6)],
    };
