part of 'main.dart';

// ---------- الانطباع الأول: شاشة افتتاح متحركة + بطاقات تعريف أول مرة ----------

Future<File> _onboardFile() async {
  final dir = await getApplicationSupportDirectory();
  return File('${dir.path}/onboarding_seen');
}

Future<bool> _onboardSeen() async {
  try {
    return await (await _onboardFile()).exists();
  } catch (_) {
    return true;
  }
}

Future<void> _markOnboardSeen() async {
  try {
    await (await _onboardFile()).writeAsString('1');
  } catch (_) {}
}

/// الحلقتين يقربون من بعض ويتشابكون، بعدها يطلع الاسم
class _SplashRings extends StatefulWidget {
  const _SplashRings();

  @override
  State<_SplashRings> createState() => _SplashRingsState();
}

class _SplashRingsState extends State<_SplashRings>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1400))
    ..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Widget _ring(Color glow) => Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 5),
          boxShadow: [BoxShadow(color: glow, blurRadius: 22)],
        ),
      );

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (_, __) {
          final move = Curves.easeOutBack
              .transform((_c.value / 0.6).clamp(0.0, 1.0));
          final text = Curves.easeOut
              .transform(((_c.value - 0.55) / 0.45).clamp(0.0, 1.0));
          final gap = 70 * (1 - move);
          return Column(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(
              width: 220,
              height: 80,
              child: Stack(alignment: Alignment.center, children: [
                Transform.translate(
                    offset: Offset(-22 - gap, 0),
                    child: _ring(const Color(0x880A84FF))),
                Transform.translate(
                    offset: Offset(22 + gap, 0),
                    child: _ring(const Color(0x88FF5FA2))),
              ]),
            ),
            const SizedBox(height: 18),
            Opacity(
              opacity: text,
              child: Transform.translate(
                offset: Offset(0, 10 * (1 - text)),
                child: const Text(appName,
                    style:
                        TextStyle(fontSize: 38, fontWeight: FontWeight.w800)),
              ),
            ),
          ]);
        },
      );
}

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingState();
}

class _OnboardingState extends State<OnboardingScreen> {
  final _page = PageController();
  int _i = 0;

  static const _cards = [
    (
      icon: Icons.lock_rounded,
      title: 'مساحتكم الخاصة',
      text: 'محادثة لشخصين بس. بدون رقم جوال، بدون إعلانات، وتقدر تقفلها بالبصمة.',
      color: Color(0xFF0A84FF),
    ),
    (
      icon: Icons.favorite_rounded,
      title: 'أكثر من رسائل',
      text: 'مكالمات صوت وفيديو، ألعاب، سؤال اليوم، وقلوب تطير لما تقول «أحبك».',
      color: Color(0xFFFF5FA2),
    ),
    (
      icon: Icons.photo_album_rounded,
      title: 'ذكرياتكم محفوظة',
      text: 'صوركم وأيامكم سوا بمكان واحد، مع احتفال بكل مرحلة توصلون لها.',
      color: Color(0xFF30D5C8),
    ),
  ];

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  Future<void> _done() async {
    await _markOnboardSeen();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const WelcomeScreen()));
  }

  void _next() {
    if (_i >= _cards.length - 1) {
      unawaited(_done());
      return;
    }
    unawaited(_page.nextPage(
        duration: const Duration(milliseconds: 350), curve: Curves.easeOut));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Backdrop(
          child: SafeArea(
            child: Column(children: [
              Align(
                alignment: AlignmentDirectional.topEnd,
                child: TextButton(
                  onPressed: _done,
                  child: const Text('تخطي',
                      style: TextStyle(color: Color(0xCCFFFFFF))),
                ),
              ),
              Expanded(
                child: PageView.builder(
                  controller: _page,
                  itemCount: _cards.length,
                  onPageChanged: (i) => setState(() => _i = i),
                  itemBuilder: (_, i) {
                    final c = _cards[i];
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Center(
                        child: Glass(
                          radius: 32,
                          padding: const EdgeInsets.fromLTRB(24, 36, 24, 32),
                          child: Column(mainAxisSize: MainAxisSize.min, children: [
                            Container(
                              width: 110,
                              height: 110,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: RadialGradient(
                                  center: const Alignment(-0.3, -0.4),
                                  colors: [
                                    Colors.white.withValues(alpha: 0.55),
                                    c.color.withValues(alpha: 0.35),
                                  ],
                                ),
                                border: Border.all(
                                    color: const Color(0x99FFFFFF), width: 1.2),
                                boxShadow: [
                                  BoxShadow(
                                      color: c.color.withValues(alpha: 0.5),
                                      blurRadius: 30),
                                ],
                              ),
                              child: Icon(c.icon, size: 52, color: Colors.white),
                            ),
                            const SizedBox(height: 26),
                            Text(c.title,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                    fontSize: 24, fontWeight: FontWeight.w700)),
                            const SizedBox(height: 10),
                            Text(c.text,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                    fontSize: 16,
                                    height: 1.6,
                                    color: Color(0xDDFFFFFF))),
                          ]),
                        ),
                      ),
                    );
                  },
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var k = 0; k < _cards.length; k++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: k == _i ? 22 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: k == _i ? Colors.white : const Color(0x66FFFFFF),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
                child: SizedBox(
                  width: double.infinity,
                  child: _Btn(
                    label: _i >= _cards.length - 1 ? 'ابدأ' : 'التالي',
                    onTap: _next,
                  ),
                ),
              ),
            ]),
          ),
        ),
      );
}
