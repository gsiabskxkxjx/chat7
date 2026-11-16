part of 'main.dart';

// ---------- مكونات الزجاج ----------

/// يزيد تشبّع الألوان وراء الزجاج (مثل زجاج آيفون)
const _saturate = ColorFilter.matrix(<double>[
  1.47244, -0.42912, -0.04332, 0, 0, //
  -0.12756, 1.17088, -0.04332, 0, 0, //
  -0.12756, -0.42912, 1.55668, 0, 0, //
  0, 0, 0, 1, 0,
]);

/// هل الثيم الحالي نهاري (زجاج أبيض حليبي بدل الشفاف)
bool _lightLook(AppLook? look) => look != null && !look.theme.dark;

/// بطاقة زجاجية: تمويه وتشبّع للخلفية، تدرّج ضوئي، إطار لامع، خط انعكاس، وظل ناعم
class Glass extends StatelessWidget {
  const Glass({
    super.key,
    required this.child,
    this.radius = 24,
    this.padding = const EdgeInsets.all(16),
    this.blur = 24,
    this.shadow = true,
    this.tint,
  });
  final Widget child;
  final double radius;
  final EdgeInsets padding;

  /// قوة التمويه: 24 للبطاقات العادية، وأكثر للنوافذ
  final double blur;
  final bool shadow;

  /// لون خفيف يصبغ الزجاج (اختياري)
  final Color? tint;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<AppLook?>(
        valueListenable: _appLook,
        builder: (_, look, __) {
          final light = _lightLook(look);
          final br = BorderRadius.circular(radius);
          final top = tint?.withValues(alpha: 0.30) ??
              (light ? const Color(0x8CFFFFFF) : const Color(0x3DFFFFFF));
          final bottom = tint?.withValues(alpha: 0.12) ??
              (light ? const Color(0x52FFFFFF) : const Color(0x12FFFFFF));
          return DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: br,
              boxShadow: shadow
                  ? const [
                      BoxShadow(
                        color: Color(0x40000000),
                        blurRadius: 28,
                        offset: Offset(0, 12),
                        blurStyle: BlurStyle.outer,
                      ),
                    ]
                  : null,
            ),
            child: ClipRRect(
              borderRadius: br,
              child: BackdropFilter(
                filter: ImageFilter.compose(
                  outer: _saturate,
                  inner: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
                ),
                child: CustomPaint(
                  foregroundPainter: _GlassEdge(radius, light),
                  child: Container(
                    padding: padding,
                    decoration: BoxDecoration(
                      borderRadius: br,
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [top, bottom],
                      ),
                    ),
                    child: child,
                  ),
                ),
              ),
            ),
          );
        },
      );
}

/// الإطار اللامع وخط الانعكاس بأعلى الزجاج
class _GlassEdge extends CustomPainter {
  const _GlassEdge(this.radius, this.light);
  final double radius;
  final bool light;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;
    final rr =
        RRect.fromRectAndRadius(rect, Radius.circular(radius)).deflate(0.5);
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white.withValues(alpha: light ? 0.95 : 0.62),
          Colors.white.withValues(alpha: light ? 0.40 : 0.10),
          Colors.white.withValues(alpha: light ? 0.70 : 0.26),
        ],
        stops: const [0, 0.55, 1],
      ).createShader(rect);
    canvas.drawRRect(rr, edge);
    final r = radius < size.width / 3 ? radius : size.width / 3;
    if (size.width > r * 2 + 12) {
      final line = Rect.fromLTWH(r, 0, size.width - r * 2, 3);
      final shine = Paint()
        ..strokeWidth = 1.2
        ..shader = LinearGradient(colors: [
          Colors.white.withValues(alpha: 0),
          Colors.white.withValues(alpha: light ? 0.9 : 0.55),
          Colors.white.withValues(alpha: 0),
        ]).createShader(line);
      canvas.drawLine(Offset(r, 1.6), Offset(size.width - r, 1.6), shine);
    }
  }

  @override
  bool shouldRepaint(_GlassEdge old) =>
      old.radius != radius || old.light != light;
}

/// يصغّر العنصر لحظة اللمس ويعطي اهتزاز خفيف
class _Press extends StatefulWidget {
  const _Press({
    required this.child,
    required this.onTap,
    this.onLongPress,
    this.scale = 0.92,
    this.haptic = true,
    this.dimWhenOff = true,
  });
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double scale;
  final bool haptic;
  final bool dimWhenOff;

  @override
  State<_Press> createState() => _PressState();
}

class _PressState extends State<_Press> {
  bool _down = false;

  void _set(bool v) {
    if (mounted && _down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final on = widget.onTap != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: on ? (_) => _set(true) : null,
      onTapUp: on ? (_) => _set(false) : null,
      onTapCancel: () => _set(false),
      onLongPress: widget.onLongPress,
      onTap: on
          ? () {
              if (widget.haptic) unawaited(HapticFeedback.lightImpact());
              widget.onTap!();
            }
          : null,
      child: AnimatedScale(
        scale: _down ? widget.scale : 1,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        child: AnimatedOpacity(
          opacity: !on && widget.dimWhenOff ? 0.45 : 1,
          duration: const Duration(milliseconds: 150),
          child: widget.child,
        ),
      ),
    );
  }
}

/// زر أيقونة زجاجي دائري موحّد
class _GlassIcon extends StatelessWidget {
  const _GlassIcon({
    required this.icon,
    required this.onTap,
    this.label,
    this.size = 40,
    this.color,
    this.tint,
  });
  final IconData icon;
  final VoidCallback? onTap;
  final String? label;
  final double size;
  final Color? color;

  /// لون الزجاج (مثلاً أحمر لزر الإنهاء)
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final t = tint;
    final body = _Press(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: t == null
                ? const [Color(0x38FFFFFF), Color(0x0FFFFFFF)]
                : [t.withValues(alpha: 0.95), t.withValues(alpha: 0.70)],
          ),
          border: Border.all(color: const Color(0x4DFFFFFF), width: 0.8),
          boxShadow: t == null
              ? null
              : [BoxShadow(color: t.withValues(alpha: 0.45), blurRadius: 16)],
        ),
        child: Icon(icon,
            size: size * 0.5, color: color ?? (t == null ? null : Colors.white)),
      ),
    );
    return Semantics(button: true, label: label, child: body);
  }
}

class Backdrop extends StatelessWidget {
  const Backdrop({super.key, required this.child});
  final Widget child;

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
            const _DriftBlobs(),
            child,
          ],
        ),
      );
}

/// خلفية حيّة: بقع ألوان ناعمة تتحرك ببطء شديد (تتوقف إذا الجوال طالب تقليل الحركة)
class _DriftBlobs extends StatefulWidget {
  const _DriftBlobs();

  @override
  State<_DriftBlobs> createState() => _DriftBlobsState();
}

class _DriftBlobsState extends State<_DriftBlobs>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(seconds: 24));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (still) {
      _c.stop();
    } else if (!_c.isAnimating) {
      unawaited(_c.repeat());
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Widget _blob(double size, Color c) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [c, c.withValues(alpha: 0)]),
        ),
      );

  @override
  Widget build(BuildContext context) => RepaintBoundary(
        child: LayoutBuilder(
          builder: (_, box) => AnimatedBuilder(
            animation: _c,
            builder: (_, __) {
              final a = _c.value * 2 * math.pi;
              final w = box.maxWidth, h = box.maxHeight;
              return Stack(children: [
                Positioned(
                  left: -120 + math.sin(a) * 40,
                  top: -110 + math.cos(a) * 30,
                  child: _blob(380, const Color(0xAA0A84FF)),
                ),
                Positioned(
                  left: w - 260 + math.cos(a) * 45,
                  top: h * 0.45 + math.sin(a * 2) * 35,
                  child: _blob(400, const Color(0x99BF5AF2)),
                ),
                Positioned(
                  left: 20 + math.sin(a + 2) * 50,
                  top: h - 220 + math.cos(a + 1) * 30,
                  child: _blob(320, const Color(0x8830D5C8)),
                ),
              ]);
            },
          ),
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
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: label,
        child: _Press(
          onTap: busy ? null : onTap,
          dimWhenOff: false,
          scale: 0.96,
          child: Container(
            constraints: const BoxConstraints(minHeight: 54),
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 15),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF4FA6FF), Color(0xFF0A6CFF)],
              ),
              border: Border.all(color: const Color(0x73FFFFFF), width: 0.8),
              boxShadow: const [
                BoxShadow(
                    color: Color(0x660A84FF),
                    blurRadius: 22,
                    offset: Offset(0, 8)),
              ],
            ),
            foregroundDecoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment(0, 0.15),
                colors: [Color(0x40FFFFFF), Color(0x00FFFFFF)],
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (busy)
                  const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.5, color: Colors.white),
                  )
                else
                  Flexible(
                    child: Text(label,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600)),
                  ),
              ],
            ),
          ),
        ),
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
