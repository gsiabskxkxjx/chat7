part of 'main.dart';

// ---------- إكمال الملف الشخصي بعد التسجيل: اسم إجباري وصورة اختيارية ----------

/// يقرأ الاسم وتاريخ الميلاد. يرجع null إذا قاعدة البيانات ما فيها العمود بعد.
Future<({String? name, DateTime? birth})?> _profileExtra(String uid) async {
  try {
    final r = await _db
        .from('profiles')
        .select('display_name,birth_date')
        .eq('id', uid)
        .maybeSingle();
    if (r == null) return null;
    final n = (r['display_name'] as String?)?.trim();
    return (
      name: (n == null || n.isEmpty) ? null : n,
      birth: DateTime.tryParse((r['birth_date'] as String?) ?? ''),
    );
  } on PostgrestException {
    return null;
  }
}

class ProfileSetupScreen extends StatefulWidget {
  const ProfileSetupScreen({
    super.key,
    this.name,
    this.avatarPath,
    this.birthDate,
    this.gender,
  });
  final String? name;
  final String? avatarPath;
  final DateTime? birthDate;
  final String? gender;

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupState();
}

class _ProfileSetupState extends State<ProfileSetupScreen> {
  late final _name = TextEditingController(text: widget.name ?? '');
  final _picker = ImagePicker();
  XFile? _photo;
  List<String> _interests = [];
  late DateTime? _birth = widget.birthDate;
  bool _busy = false;
  String? _nameErr;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  String get _uid => _db.auth.currentUser!.id;

  Future<void> _pickPhoto() async {
    final act = await _photoSheet(context, canRemove: _photo != null);
    if (!mounted || act == null) return;
    if (act == 'remove') {
      setState(() => _photo = null);
      return;
    }
    try {
      final x = await _picker.pickImage(
        source: act == 'camera' ? ImageSource.camera : ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 85,
      );
      if (x != null && mounted) setState(() => _photo = x);
    } catch (_) {
      if (mounted) _toast(context, 'تعذر فتح الصور.');
    }
  }

  Future<void> _pickBirth() async {
    if (widget.birthDate != null) return; // ما يتغير بعد الحفظ
    final now = DateTime.now();
    final last = DateTime(now.year - 13, now.month, now.day);
    final d = await showDatePicker(
      context: context,
      initialDate: _birth ?? DateTime(now.year - 20, 1, 1),
      firstDate: DateTime(1920),
      lastDate: last,
      helpText: 'تاريخ ميلادك',
      cancelText: 'إلغاء',
      confirmText: 'تم',
    );
    if (d != null && mounted) setState(() => _birth = d);
  }

  Future<void> _save() async {
    if (_busy) return;
    final n = _name.text.trim();
    if (n.length < 2) {
      setState(() => _nameErr = 'اكتب اسم من حرفين على الأقل.');
      return;
    }
    if (_birth == null) {
      _toast(context, 'اختر تاريخ ميلادك.');
      return;
    }
    setState(() {
      _busy = true;
      _nameErr = null;
    });
    try {
      final upd = <String, dynamic>{'display_name': n};
      if (widget.birthDate == null) {
        final b = _birth!;
        upd['birth_date'] =
            '${b.year.toString().padLeft(4, '0')}-${_two(b.month)}-${_two(b.day)}';
      }
      final x = _photo;
      if (x != null) {
        final path =
            '$_uid/avatar_${DateTime.now().millisecondsSinceEpoch}.${_extFor(x.path)}';
        await _db.storage.from('avatars').upload(path, File(x.path),
            fileOptions: FileOptions(contentType: _mimeFor(x.path)));
        upd['avatar_path'] = path;
      }
      await _db.from('profiles').update(upd).eq('id', _uid);
      if (_interests.isNotEmpty) {
        try {
          await _db
              .from('profiles')
              .update({'interests': _interests}).eq('id', _uid);
        } catch (_) {} // السيرفر قديم: نتخطى الاهتمامات
      }
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const Boot()), (_) => false);
    } on PostgrestException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      final m = e.message;
      if (m.contains('bad_name')) {
        setState(() => _nameErr = 'الاسم لازم يكون من 2 إلى 30 حرف.');
      } else if (m.contains('bad_birth')) {
        _toast(context, 'تاريخ الميلاد غير صحيح. لازم يكون عمرك 13 سنة أو أكثر.');
      } else {
        _toast(context, 'تعذر الحفظ، جرّب مرة ثانية.');
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      _toast(context, 'تعذر الحفظ. تأكد من الإنترنت وجرّب مرة ثانية.');
    }
  }

  String _birthText() {
    final b = _birth;
    if (b == null) return 'اختر تاريخ ميلادك';
    return '${b.day}/${b.month}/${b.year}';
  }

  @override
  Widget build(BuildContext context) {
    final photo = _photo;
    final g = widget.gender;
    return Scaffold(
      body: Backdrop(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(_Sp.xl),
              child: Glass(
                radius: 32,
                padding: const EdgeInsets.all(_Sp.xl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('ملفك',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 26, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    const Text('اسمك يظهر للطرف الثاني. الصورة اختيارية.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Color(0xCCFFFFFF))),
                    const SizedBox(height: 20),
                    Center(
                      child: Semantics(
                        button: true,
                        label: 'اختيار صورة الملف',
                        child: _Press(
                          onTap: _busy ? null : _pickPhoto,
                          dimWhenOff: false,
                          child: Stack(children: [
                            Container(
                              width: 112,
                              height: 112,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    _genderColor(g).withValues(alpha: 0.55),
                                    _genderColor(g).withValues(alpha: 0.20),
                                  ],
                                ),
                                border: Border.all(
                                    color: const Color(0x80FFFFFF), width: 1.5),
                                image: photo == null
                                    ? null
                                    : DecorationImage(
                                        image: FileImage(File(photo.path)),
                                        fit: BoxFit.cover),
                              ),
                              child: photo == null
                                  ? const Icon(Icons.person_rounded,
                                      size: 56, color: Colors.white)
                                  : null,
                            ),
                            Positioned(
                              bottom: 2,
                              left: 2,
                              child: Container(
                                width: 34,
                                height: 34,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: _blue,
                                  border:
                                      Border.all(color: Colors.white, width: 2),
                                ),
                                child: const Icon(Icons.photo_camera_rounded,
                                    size: 18, color: Colors.white),
                              ),
                            ),
                          ]),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: _name,
                      maxLength: 30,
                      textInputAction: TextInputAction.done,
                      onChanged: (_) {
                        if (_nameErr != null) setState(() => _nameErr = null);
                      },
                      decoration: InputDecoration(
                        labelText: 'اسمك (إجباري)',
                        prefixIcon: const Icon(Icons.badge_rounded),
                        errorText: _nameErr,
                        counterText: '',
                        filled: true,
                        fillColor: const Color(0x1AFFFFFF),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: const BorderSide(color: _edge),
                        ),
                      ),
                    ),
                    const SizedBox(height: _Sp.md),
                    _Press(
                      onTap: widget.birthDate != null || _busy
                          ? null
                          : _pickBirth,
                      dimWhenOff: false,
                      scale: 0.98,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: _Sp.lg),
                        decoration: BoxDecoration(
                          color: const Color(0x1AFFFFFF),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: _edge),
                        ),
                        child: Row(children: [
                          const Icon(Icons.cake_rounded),
                          const SizedBox(width: _Sp.md),
                          Expanded(
                            child: Text(_birthText(),
                                style: TextStyle(
                                    fontSize: _Fs.title,
                                    color: _birth == null
                                        ? const Color(0x99FFFFFF)
                                        : Colors.white)),
                          ),
                          if (widget.birthDate == null)
                            const Icon(Icons.expand_more_rounded),
                        ]),
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                        'تاريخ الميلاد ما يظهر لأحد، وما يتغير بعد الحفظ. البحث عن شريك للي عمرهم 18 وفوق.',
                        style: TextStyle(fontSize: _Fs.small, color: Color(0x99FFFFFF))),
                    const SizedBox(height: _Sp.lg),
                    const Text('اهتماماتك (اختياري، لين 3)',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: _Sp.sm),
                    _InterestsPicker(
                        selected: _interests,
                        onChanged: (v) => setState(() => _interests = v)),
                    const SizedBox(height: 20),
                    _Btn(label: 'متابعة', onTap: _save, busy: _busy),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
