part of 'main.dart';

// ---------- الجولة الثانية: عناصر واجهة مشتركة ----------
// 261 حركة تحميل هيكلية بدل دائرة الانتظار

class _SkeletonPulse extends StatefulWidget {
  const _SkeletonPulse({required this.builder});
  final Widget Function(double t) builder;

  @override
  State<_SkeletonPulse> createState() => _SkeletonPulseState();
}

class _SkeletonPulseState extends State<_SkeletonPulse> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));

  @override
  void initState() {
    super.initState();
    if (!_Prefs.lowFx.value) _c.repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(animation: _c, builder: (_, __) => widget.builder(_c.value));
}

Widget _skBox(double t, {double? w, double? h, double r = 12}) => Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05 + 0.08 * t),
        borderRadius: BorderRadius.circular(r),
      ),
    );

/// شبكة صور هيكلية
class _SkeletonGrid extends StatelessWidget {
  const _SkeletonGrid({this.cols = 3, this.count = 18});
  final int cols;
  final int count;

  @override
  Widget build(BuildContext context) => _SkeletonPulse(
        builder: (t) => GridView.builder(
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.all(_Sp.sm),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: cols, mainAxisSpacing: 6, crossAxisSpacing: 6),
          itemCount: count,
          itemBuilder: (_, __) => _skBox(t),
        ),
      );
}

/// قائمة صفوف هيكلية
class _SkeletonList extends StatelessWidget {
  const _SkeletonList({this.count = 7});
  final int count;

  @override
  Widget build(BuildContext context) => _SkeletonPulse(
        builder: (t) => ListView.builder(
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          itemCount: count,
          itemBuilder: (_, __) => Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Row(children: [
              _skBox(t, w: 46, h: 46, r: 23),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _skBox(t, h: 12, r: 6),
                  const SizedBox(height: 8),
                  FractionallySizedBox(widthFactor: 0.6, child: _skBox(t, h: 10, r: 5)),
                ]),
              ),
            ]),
          ),
        ),
      );
}

// ===== سجل وسائط المحادثة (للتنقل بين الصور بالسحب 241 وتشغيل الصوتيات تباعاً 246) =====

class _MediaLog {
  static List<String> images = const []; // الأقدم أولاً
  static List<String> voices = const [];

  static void update(List<Msg> msgs) {
    final im = <String>[];
    final vo = <String>[];
    for (final m in msgs.reversed) {
      final p = m.mediaPath;
      if (p == null) continue;
      if (m.kind == 'image') im.add(p);
      if (m.kind == 'audio') vo.add(p);
    }
    images = im;
    voices = vo;
  }

  static String? nextVoice(String path) {
    final i = voices.indexOf(path);
    return (i >= 0 && i + 1 < voices.length) ? voices[i + 1] : null;
  }
}
