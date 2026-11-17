part of 'main.dart';

// ---------- أشياء تعتمد على كود أندرويد الأصلي: ضغط الفيديو وأيقونة التطبيق ----------

const _mediaCh = MethodChannel('bainatna/media');

/// يضغط الفيديو الكبير قبل الإرسال (أقصر ضلع 720 وبت ريت معقول).
/// لو فشل الضغط أو ما صغّر الحجم بشكل واضح يرجع الملف الأصلي، فما يضيع شي.
Future<File> _compressVideo(File f) async {
  File? out;
  try {
    final size = await f.length();
    if (size < 6 * 1024 * 1024) return f; // صغير أصلاً
    final dir = await getTemporaryDirectory();
    out = File('${dir.path}/vc_${DateTime.now().millisecondsSinceEpoch}.mp4');
    final ok = await _mediaCh
        .invokeMethod<bool>('compress', {'in': f.path, 'out': out.path})
        .timeout(const Duration(minutes: 5));
    if (ok == true && await out.exists()) {
      final n = await out.length();
      if (n > 0 && n < size * 0.9) return out;
    }
  } on TimeoutException {
    try {
      await _mediaCh.invokeMethod<void>('cancel');
    } catch (_) {}
  } catch (_) {}
  try {
    if (out != null && await out.exists()) await out.delete();
  } catch (_) {}
  return f;
}

/// نمسح الملف المضغوط المؤقت بعد الإرسال (الأصلي ما نلمسه)
Future<void> _dropTemp(File used, File original) async {
  if (used.path == original.path) return;
  try {
    if (await used.exists()) await used.delete();
  } catch (_) {}
}

// ===== أيقونة التطبيق =====

const _iconCh = MethodChannel('bainatna/icon');

const _iconLabels = <String, String>{
  'Default': 'الأساسية',
  'Rose': 'وردي',
  'Mint': 'أخضر',
  'Sunset': 'غروب',
  'Night': 'ليلي',
};

const _iconColors = <String, List<Color>>{
  'Default': [Color(0xFF0C5AB8), Color(0xFF7B3FB8)],
  'Rose': [Color(0xFFA812B8), Color(0xFFC04058)],
  'Mint': [Color(0xFF1FA80A), Color(0xFF3DBBA0)],
  'Sunset': [Color(0xFFB0143C), Color(0xFFC8904A)],
  'Night': [Color(0xFF000000), Color(0xFF2A2A2A)],
};

/// معاينة صغيرة للأيقونة: خلفية متدرجة وحلقتين متداخلتين
class _IconPreview extends StatelessWidget {
  const _IconPreview({required this.name, this.size = 56});
  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = _iconColors[name] ?? _iconColors['Default']!;
    final ring = size * 0.36;
    Widget r(double dx) => Positioned(
          left: size / 2 - ring / 2 + dx,
          top: size / 2 - ring / 2,
          child: Container(
            width: ring,
            height: ring,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: size * 0.065),
            ),
          ),
        );
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.24),
        gradient: LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight, colors: c),
      ),
      child: Stack(children: [r(-ring * 0.2), r(ring * 0.2)]),
    );
  }
}

class _AppIconTile extends StatefulWidget {
  const _AppIconTile();

  @override
  State<_AppIconTile> createState() => _AppIconTileState();
}

class _AppIconTileState extends State<_AppIconTile> {
  List<String> _avail = const [];
  String _cur = '';

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final r = await _iconCh.invokeMapMethod<String, dynamic>('get');
      final a = ((r?['available'] as List?) ?? const []).map((e) => '$e').toList();
      if (mounted) {
        setState(() {
          _avail = a;
          _cur = '${r?['current'] ?? ''}';
        });
      }
    } catch (_) {}
  }

  Future<void> _choose() async {
    final pick = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(_Sp.lg),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('أيقونة التطبيق',
                style: TextStyle(
                    fontSize: _Fs.heading, fontWeight: FontWeight.w700)),
            const SizedBox(height: _Sp.lg),
            Wrap(
              spacing: _Sp.lg,
              runSpacing: _Sp.lg,
              alignment: WrapAlignment.center,
              children: [
                for (final n in _avail)
                  GestureDetector(
                    onTap: () => Navigator.pop(c, n),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                              color: n == _cur
                                  ? const Color(0xFF7CC0FF)
                                  : Colors.transparent,
                              width: 2),
                        ),
                        child: _IconPreview(name: n),
                      ),
                      const SizedBox(height: _Sp.xs),
                      Text(_iconLabels[n] ?? n,
                          style: const TextStyle(fontSize: _Fs.small)),
                    ]),
                  ),
              ],
            ),
            const SizedBox(height: _Sp.md),
          ]),
        ),
      ),
    );
    if (pick == null || pick == _cur || !mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('تغيير الأيقونة'),
        content: const Text(
            'التغيير يتطبق بعد ثواني. ممكن يختفي اختصار التطبيق من الشاشة الرئيسية، وتضيفه من جديد من قائمة التطبيقات. وبعض الجوالات تسكّر التطبيق وقت التبديل.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true), child: const Text('غيّر')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    bool done = false;
    try {
      done = await _iconCh.invokeMethod<bool>('set', {'name': pick}) == true;
    } catch (_) {}
    if (!mounted) return;
    if (!done) {
      _toast(context, 'تعذر تغيير الأيقونة على هذا الجهاز.');
    } else {
      setState(() => _cur = pick);
    }
  }

  @override
  Widget build(BuildContext context) {
    // ما تظهر إلا لو النسخة فيها أيقونات بديلة
    if (_avail.length < 2) return const SizedBox.shrink();
    return ListTile(
      leading: const Icon(Icons.apps_rounded),
      title: const Text('أيقونة التطبيق'),
      subtitle: Text(_iconLabels[_cur] ?? 'الأساسية'),
      trailing: _IconPreview(name: _cur.isEmpty ? 'Default' : _cur, size: 36),
      onTap: _choose,
    );
  }
}
