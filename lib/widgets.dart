part of 'main.dart';

// ---------- مكونات الزجاج ----------

class Glass extends StatelessWidget {
  const Glass({
    super.key,
    required this.child,
    this.radius = 24,
    this.padding = const EdgeInsets.all(16),
  });
  final Widget child;
  final double radius;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              color: _glass,
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(color: _edge),
            ),
            child: child,
          ),
        ),
      );
}

class Backdrop extends StatelessWidget {
  const Backdrop({super.key, required this.child});
  final Widget child;

  Widget _blob(double s, Color c) => ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: 50, sigmaY: 50),
        child: Container(
          width: s,
          height: s,
          decoration: BoxDecoration(shape: BoxShape.circle, color: c),
        ),
      );

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<AppLook?>(
        valueListenable: _appLook,
        builder: (_, look, __) =>
            look == null ? _defaultBg(context) : _lookBg(look),
      );

  /// الخلفية المشتركة (ثيم الزوج وخلفيته)
  Widget _lookBg(AppLook look) {
    final t = look.theme;
    final grad = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [t.top, t.bottom],
        ),
      ),
    );
    Widget bg = grad;
    final url = look.url;
    if (look.kind != 'gradient' && url != null) {
      final img = Image.network(
        url,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (_, __, ___) => grad,
      );
      if (look.kind == 'plain') {
        bg = img;
      } else {
        final s = look.strength.toDouble();
        final blurred = ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: s, sigmaY: s),
          child: img,
        );
        bg = look.kind == 'blur'
            ? blurred
            : Stack(fit: StackFit.expand, children: [
                blurred,
                ColoredBox(color: t.top.withValues(alpha: 0.45)),
              ]);
      }
    }
    // الثيم النهاري: النص والأيقونات داكنة عشان تبان
    return Stack(fit: StackFit.expand, children: [
      bg,
      DefaultTextStyle.merge(
        style: TextStyle(color: t.text),
        child: IconTheme(
          data: IconThemeData(color: t.text),
          child: child,
        ),
      ),
    ]);
  }

  Widget _defaultBg(BuildContext context) => Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [Color(0xFF0B1B3A), Color(0xFF2B2A7A)],
          ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Positioned(
                top: -60, left: -40, child: _blob(240, const Color(0xAA0A84FF))),
            Positioned(
                bottom: 90,
                right: -70,
                child: _blob(260, const Color(0x99BF5AF2))),
            Positioned(
                bottom: -80,
                left: 40,
                child: _blob(200, const Color(0x8830D5C8))),
            child,
          ],
        ),
      );
}

class _Rings extends StatelessWidget {
  const _Rings();

  Widget _r() => Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 4),
        ),
      );

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 84,
        height: 52,
        child: Stack(children: [
          Positioned(left: 0, child: _r()),
          Positioned(right: 0, child: _r()),
        ]),
      );
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.label,
    required this.icon,
    required this.onSubmit,
    this.error,
    this.maxLength = 20,
    this.pattern = r'[A-Za-z0-9_]',
    this.upper = false,
  });
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final VoidCallback onSubmit;
  final String? error;
  final int maxLength;
  final String pattern;
  final bool upper;

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        textDirection: TextDirection.ltr,
        textCapitalization:
            upper ? TextCapitalization.characters : TextCapitalization.none,
        autocorrect: false,
        enableSuggestions: false,
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(pattern)),
          LengthLimitingTextInputFormatter(maxLength),
        ],
        onSubmitted: (_) => onSubmit(),
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon),
          errorText: error,
          errorMaxLines: 2,
          filled: true,
          fillColor: const Color(0x1AFFFFFF),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: _edge),
          ),
        ),
      );
}

class _Btn extends StatelessWidget {
  const _Btn({required this.label, required this.onTap, this.busy = false});
  final String label;
  final VoidCallback onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) => FilledButton(
        onPressed: busy ? null : onTap,
        style: FilledButton.styleFrom(
          backgroundColor: _blue,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        child: busy
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              )
            : Text(label,
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
      );
}

void _toast(BuildContext c, String msg) =>
    ScaffoldMessenger.of(c).showSnackBar(SnackBar(
      content: Text(msg),
      behavior: SnackBarBehavior.floating,
    ));

void _soon(BuildContext c, String what) => _toast(c, '$what — قريباً');

// ---------- بيانات المحادثة ----------

class ChatInfo {
  const ChatInfo(
    this.id,
    this.partner, {
    this.me = '',
    this.partnerName,
    this.partnerAvatar,
    this.partnerGender,
    this.myGender,
  });
  final String id;
  final String partner; // اسم المستخدم للطرف الثاني
  final String me; // اسم المستخدم حقي
  final String? partnerName; // الاسم الظاهر للطرف الثاني
  final String? partnerAvatar; // مسار صورته
  final String? partnerGender; // male | female
  final String? myGender; // جنسي أنا (male | female)
}

/// يرجع محادثة المستخدم الحالي (إذا مربوط) أو null.
Future<ChatInfo?> _loadChat() async {
  final uid = _db.auth.currentUser!.id;
  final rows = await _db.from('chats').select().limit(1);
  if (rows.isEmpty) return null;
  final r = rows.first;
  final other = r['user_a'] == uid ? r['user_b'] : r['user_a'];
  final p = await _db
      .from('profiles')
      .select('username,display_name,avatar_path,gender')
      .eq('id', other)
      .maybeSingle();
  final m = await _db
      .from('profiles')
      .select('username,gender')
      .eq('id', uid)
      .maybeSingle();
  return ChatInfo(
    r['id'] as String,
    (p?['username'] as String?) ?? '?',
    me: (m?['username'] as String?) ?? '',
    partnerName: p?['display_name'] as String?,
    partnerAvatar: p?['avatar_path'] as String?,
    partnerGender: p?['gender'] as String?,
    myGender: m?['gender'] as String?,
  );
}
