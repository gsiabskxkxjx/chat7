part of 'main.dart';

// ---------- اختيار الجنس (أول ما تفتح التطبيق) ----------

const _femaleColor = Color(0xFFE0568F);

Color _genderColor(String? g) => g == 'female' ? _femaleColor : _blue;

class GenderScreen extends StatefulWidget {
  const GenderScreen({super.key, required this.onPicked});

  /// يستلم الجنس ('male' أو 'female') ويرجع الشاشة اللي تنفتح بعدها.
  final Future<Widget> Function(String gender) onPicked;

  @override
  State<GenderScreen> createState() => _GenderState();
}

class _GenderState extends State<GenderScreen> {
  String? _g;
  bool _busy = false;

  Future<void> _next() async {
    final g = _g;
    if (g == null) {
      _toast(context, 'اختر جنسك أولاً.');
      return;
    }
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final next = await widget.onPicked(g);
      if (!mounted) return;
      Navigator.of(context)
          .pushReplacement(MaterialPageRoute(builder: (_) => next));
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      _toast(context, 'تعذر الحفظ، جرّب مرة ثانية.');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Backdrop(
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Glass(
                  radius: 32,
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Center(child: _Rings()),
                      const SizedBox(height: 20),
                      const Text(appName,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 34, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 8),
                      const Text('أهلاً بك! حدد جنسك للبدء',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 18, color: Color(0xCCFFFFFF))),
                      const SizedBox(height: 24),
                      Row(children: [
                        Expanded(
                          child: _GenderCard(
                            icon: Icons.male,
                            label: 'ذكر',
                            color: _blue,
                            selected: _g == 'male',
                            onTap: () => setState(() => _g = 'male'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _GenderCard(
                            icon: Icons.female,
                            label: 'أنثى',
                            color: _femaleColor,
                            selected: _g == 'female',
                            onTap: () => setState(() => _g = 'female'),
                          ),
                        ),
                      ]),
                      const SizedBox(height: 24),
                      _Btn(label: 'متابعة', onTap: _next, busy: _busy),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}

class _GenderCard extends StatelessWidget {
  const _GenderCard({
    required this.icon,
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 22),
          decoration: BoxDecoration(
            color: selected ? const Color(0x33FFFFFF) : const Color(0x14FFFFFF),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: selected ? color : _edge, width: selected ? 2.5 : 1),
          ),
          child: Column(children: [
            Icon(icon, size: 44, color: selected ? color : Colors.white70),
            const SizedBox(height: 8),
            Text(label,
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          ]),
        ),
      );
}
