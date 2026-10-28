part of 'main.dart';

// ---------- شاشة مظهر المحادثة: الثيم + الخلفية ----------

class ThemeSettingsScreen extends StatefulWidget {
  const ThemeSettingsScreen({super.key, required this.chatId});
  final String chatId;

  @override
  State<ThemeSettingsScreen> createState() => _ThemeSettingsState();
}

class _ThemeSettingsState extends State<ThemeSettingsScreen> {
  final _picker = ImagePicker();
  bool _loading = true;
  bool _busy = false;
  int _theme = 1;
  String _kind = 'gradient';
  int _strength = 10;
  String? _path; // الصورة المحفوظة حالياً
  XFile? _newImage; // صورة اختارها الآن (لسا ما انرفعت)

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await _db
          .from('chats')
          .select('theme_id,bg_kind,bg_path,bg_strength')
          .eq('id', widget.chatId)
          .single();
      if (!mounted) return;
      setState(() {
        _theme = (r['theme_id'] as num?)?.toInt() ?? 1;
        _kind = (r['bg_kind'] as String?) ?? 'gradient';
        _strength = (r['bg_strength'] as num?)?.toInt() ?? 10;
        _path = r['bg_path'] as String?;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      _toast(context, 'تعذر تحميل الإعدادات.');
    }
  }

  Future<void> _pickImage() async {
    if (_busy) return;
    try {
      // الضغط يصير هنا: عرض أقصى 1080 وجودة 70 (تطلع الصورة أصغر بكثير)
      final x = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1080,
        maxHeight: 1920,
        imageQuality: 70,
      );
      if (x == null || !mounted) return;
      setState(() => _newImage = x);
    } catch (_) {
      if (mounted) _toast(context, 'تعذر فتح المعرض.');
    }
  }

  Future<void> _save() async {
    if (_busy) return;
    final hasImage = _newImage != null || _path != null;
    if (_kind != 'gradient' && !hasImage) {
      _toast(context, 'اختر صورة أول.');
      return;
    }
    setState(() => _busy = true);
    String? uploaded;
    try {
      final img = _newImage;
      if (img != null && _kind != 'gradient') {
        uploaded =
            '${widget.chatId}/bg_${DateTime.now().millisecondsSinceEpoch}.${_extFor(img.path)}';
        await _db.storage.from('chat-bg').upload(
              uploaded,
              File(img.path),
              fileOptions: FileOptions(contentType: _mimeFor(img.path)),
            );
      }
      final newPath = _kind == 'gradient' ? null : (uploaded ?? _path);
      // الدالة تحفظ وترجع مكان الصورة القديمة (إذا تغيّرت) عشان نحذفها
      final old = await _db.rpc('set_chat_theme', params: {
        'p_chat': widget.chatId,
        'p_theme': _theme,
        'p_kind': _kind,
        'p_path': newPath,
        'p_strength': _strength,
      });
      if (old is String && old.isNotEmpty) {
        try {
          await _db.storage.from('chat-bg').remove([old]);
        } catch (_) {}
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      // إذا فشل الحفظ بعد الرفع، نحذف الصورة الجديدة عشان ما تبقى يتيمة
      if (uploaded != null) {
        try {
          await _db.storage.from('chat-bg').remove([uploaded]);
        } catch (_) {}
      }
      if (!mounted) return;
      setState(() => _busy = false);
      _toast(context, 'تعذر الحفظ. جرّب مرة ثانية.');
    }
  }

  Widget _section(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8, top: 4),
        child: Text(t,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      );

  Widget _themeGrid() => Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final t in chatThemes)
            GestureDetector(
              onTap: () => setState(() => _theme = t.id),
              child: _ThemeCard(t: t, selected: _theme == t.id),
            ),
        ],
      );

  Widget _kindChips() {
    const items = {
      'gradient': 'تدريج ألوان',
      'plain': 'عادية',
      'blur': 'ضبابية',
      'glass': 'زجاجية',
    };
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final e in items.entries)
          ChoiceChip(
            label: Text(e.value),
            selected: _kind == e.key,
            onSelected: (_) => setState(() => _kind = e.key),
          ),
      ],
    );
  }

  List<Widget> _bgOptions() {
    if (_kind == 'gradient') {
      return const [
        Text('الخلفية تتبع ألوان الثيم.',
            style: TextStyle(color: Color(0xAAFFFFFF))),
      ];
    }
    final hasImage = _newImage != null || _path != null;
    final label = _newImage != null
        ? 'اخترت صورة جديدة (تغيير)'
        : (hasImage ? 'تغيير الصورة' : 'اختيار صورة من المعرض');
    final out = <Widget>[
      const SizedBox(height: 8),
      OutlinedButton.icon(
        onPressed: _busy ? null : _pickImage,
        icon: const Icon(Icons.photo_library_outlined),
        label: Text(label),
      ),
    ];
    if (_kind == 'blur' || _kind == 'glass') {
      out.addAll([
        const SizedBox(height: 12),
        Text('القوة: $_strength'),
        Slider(
          value: _strength.toDouble(),
          min: 0,
          max: 20,
          divisions: 20,
          label: '$_strength',
          onChanged:
              _busy ? null : (v) => setState(() => _strength = v.round()),
        ),
      ]);
    }
    return out;
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
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.arrow_back)),
                  const Text('مظهر المحادثة',
                      style:
                          TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                ]),
              ),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _section('الثيم'),
                            _themeGrid(),
                            const SizedBox(height: 20),
                            _section('نوع الخلفية'),
                            _kindChips(),
                            const SizedBox(height: 8),
                            ..._bgOptions(),
                            const SizedBox(height: 24),
                            _Btn(label: 'حفظ', onTap: _save, busy: _busy),
                          ],
                        ),
                      ),
              ),
            ]),
          ),
        ),
      );
}

class _ThemeCard extends StatelessWidget {
  const _ThemeCard({required this.t, required this.selected});
  final ChatTheme t;
  final bool selected;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 150,
        height: 110,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [t.top, t.bottom]),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: selected ? t.accent : Colors.white24,
              width: selected ? 3 : 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                    color: t.mine, borderRadius: BorderRadius.circular(12)),
                child: const Text('مرحبا',
                    style: TextStyle(color: Colors.white, fontSize: 12)),
              ),
            ),
            const SizedBox(height: 6),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                    color: t.theirs, borderRadius: BorderRadius.circular(12)),
                child: Text('هلا',
                    style: TextStyle(color: t.text, fontSize: 12)),
              ),
            ),
            const Spacer(),
            Text('${t.id}. ${t.name}',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: t.text, fontSize: 12, fontWeight: FontWeight.w600)),
          ],
        ),
      );
}
