part of 'main.dart';

// ---------- تأثيرات واحتفالات: قلوب، قصاصات، نجوم + سؤال اليوم + السلسلة + المناسبات ----------

/// كلمات تطيّر قلوب عند الطرفين
const _magic = [
  'أحبك', 'احبك', 'أحبج', 'احبج', 'اشتقتلك', 'اشتقت لك', 'اشتاقيتلك',
  'حبيبي', 'حبيبتي', 'عمري', 'روحي',
];

bool _hasMagic(String t) => _magic.any(t.contains);

/// يعرض تأثير على كامل الشاشة: hearts | confetti | stars
void _showEffect(BuildContext context, String kind) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  late OverlayEntry e;
  e = OverlayEntry(
    builder: (_) => _EffectLayer(kind: kind, onDone: () => e.remove()),
  );
  overlay.insert(e);
  unawaited(HapticFeedback.mediumImpact());
}

class _Particle {
  _Particle(Random r, this.glyph)
      : x = r.nextDouble(),
        delay = r.nextDouble() * 0.35,
        speed = 0.6 + r.nextDouble() * 0.6,
        size = 18 + r.nextDouble() * 22,
        drift = (r.nextDouble() - 0.5) * 0.25,
        spin = (r.nextDouble() - 0.5) * 6,
        color = Color.fromARGB(
            255, 150 + r.nextInt(106), 80 + r.nextInt(176), 120 + r.nextInt(136));
  final double x, delay, speed, size, drift, spin;
  final String glyph;
  final Color color;
}

class _EffectLayer extends StatefulWidget {
  const _EffectLayer({required this.kind, required this.onDone});
  final String kind;
  final VoidCallback onDone;

  @override
  State<_EffectLayer> createState() => _EffectLayerState();
}

class _EffectLayerState extends State<_EffectLayer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 2600));
  late final List<_Particle> _ps;

  @override
  void initState() {
    super.initState();
    final r = Random();
    const hearts = ['❤️', '💕', '💖', '💗', '💞'];
    const stars = ['⭐', '✨', '🌟', '💫'];
    _ps = List.generate(widget.kind == 'confetti' ? 60 : 34, (_) {
      switch (widget.kind) {
        case 'stars':
          return _Particle(r, stars[r.nextInt(stars.length)]);
        case 'confetti':
          return _Particle(r, '');
        default:
          return _Particle(r, hearts[r.nextInt(hearts.length)]);
      }
    });
    _c.forward().whenComplete(widget.onDone);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: LayoutBuilder(
          builder: (_, box) => AnimatedBuilder(
            animation: _c,
            builder: (_, __) {
              final w = box.maxWidth, h = box.maxHeight;
              final kids = <Widget>[];
              for (final p in _ps) {
                final t = ((_c.value - p.delay) / (1 - p.delay)).clamp(0.0, 1.0);
                if (t <= 0) continue;
                final fade = t < 0.8 ? 1.0 : (1 - (t - 0.8) / 0.2);
                double x, y;
                if (widget.kind == 'confetti') {
                  // تنزل من فوق
                  x = (p.x + p.drift * t) * w;
                  y = -40 + t * p.speed * (h + 80);
                } else if (widget.kind == 'stars') {
                  // تنفجر من النص
                  final ang = p.x * 2 * math.pi;
                  final dist = t * p.speed * w * 0.6;
                  x = w / 2 + math.cos(ang) * dist;
                  y = h / 2 + math.sin(ang) * dist;
                } else {
                  // القلوب تصعد من تحت
                  x = (p.x + math.sin(t * 6 + p.spin) * 0.04 + p.drift * t) * w;
                  y = h + 30 - t * p.speed * (h + 60);
                }
                kids.add(Positioned(
                  left: x - p.size / 2,
                  top: y - p.size / 2,
                  child: Opacity(
                    opacity: fade.clamp(0.0, 1.0),
                    child: Transform.rotate(
                      angle: p.spin * t,
                      child: widget.kind == 'confetti'
                          ? Container(
                              width: p.size * 0.35,
                              height: p.size * 0.6,
                              decoration: BoxDecoration(
                                color: p.color,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            )
                          : Text(p.glyph,
                              style: TextStyle(
                                  fontSize: p.size,
                                  decoration: TextDecoration.none)),
                    ),
                  ),
                ));
              }
              return Stack(children: kids);
            },
          ),
        ),
      );
}

// ---------- سؤال اليوم ----------

const _dailyQuestions = [
  'شنو أكثر شي يضحكك فيني؟',
  'لو نسافر بكرة، وين تختار؟',
  'شنو أول شي لاحظته فيني؟',
  'شنو الأغنية اللي تذكرك فيني؟',
  'شنو حلمك اللي ما قلته لأحد؟',
  'شنو أحلى ذكرى لنا لحد الحين؟',
  'لو تقدر تغيّر شي واحد بيومك، شنو هو؟',
  'شنو الأكلة اللي تتمنى نطبخها سوا؟',
  'شنو الشي اللي يخليك تحس إنك محبوب؟',
  'لو عندك يوم فاضي كامل معي، شنو نسوي؟',
  'شنو أكثر صفة تحبها بنفسك؟',
  'شنو الفلم اللي تتمنى نشوفه سوا؟',
  'شنو أكثر شي يزعلك وما تقوله؟',
  'وين تشوف نفسك بعد خمس سنين؟',
  'شنو الهدية اللي تفرحك أكثر شي؟',
  'شنو أكثر شي تخاف منه؟',
  'لو تكتب لي رسالة بكلمة وحدة، شنو تكون؟',
  'شنو العادة اللي تحب تسويها كل يوم؟',
  'شنو الشي اللي تعلمته مني؟',
  'شنو أكثر لحظة حسيت فيها بالفخر؟',
  'لو نعيش بأي مدينة بالعالم، وين؟',
  'شنو الشي الصغير اللي يسعدك؟',
  'شنو أكثر كلمة أقولها وتحبها؟',
  'شنو الذكرى اللي تتمنى تعيشها مرة ثانية؟',
  'شنو تسوي لما تكون زعلان؟',
  'شنو أول شي تسويه الصبح؟',
  'شنو الموسم اللي تحبه أكثر وليش؟',
  'لو تقدر تتعلم مهارة بيوم، شنو تختار؟',
  'شنو الكتاب أو المسلسل اللي غيّرك؟',
  'شنو الشي اللي تحب نسويه أكثر سوا؟',
  'شنو اللقب اللي تحب أناديك فيه؟',
  'شنو أكثر شي تشتاق له لما نكون بعيدين؟',
  'شنو الشي اللي ما تقدر تعيش بدونه؟',
  'لو اليوم آخر يوم بالسنة، شنو تتمنى؟',
  'شنو أطيب أكلة بحياتك؟',
  'شنو الشي اللي يخليك تبتسم بدون سبب؟',
  'شنو الطفولة اللي تتذكرها أكثر؟',
  'شنو الصفة اللي تتمنى أتعلمها منك؟',
  'لو عندنا بيت، شنو أول غرفة نرتبها؟',
  'شنو أحلى رسالة وصلتك مني؟',
  'شنو الشي اللي تحب تسمعه مني أكثر؟',
  'شنو المغامرة اللي تتمنى نسويها؟',
  'شنو الشي اللي تفتخر فيه بعلاقتنا؟',
  'شنو الشي اللي يريحك بعد يوم متعب؟',
  'شنو أكثر لون تحبه وليش؟',
  'لو نرجع لأول يوم تعرفنا فيه، شنو تغيّر؟',
  'شنو الهدف اللي تبينا نحققه سوا هالسنة؟',
  'شنو الشي اللي يخليك تثق بأحد؟',
  'شنو أكثر لحظة ضحكنا فيها سوا؟',
  'لو تكتب عنوان لقصتنا، شنو يكون؟',
];

DateTime _today() {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day);
}

String _dayStr(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${_two(d.month)}-${_two(d.day)}';

String _todayQuestion() {
  final idx = _today().difference(DateTime(2026, 1, 1)).inDays;
  return _dailyQuestions[idx % _dailyQuestions.length];
}

// ---------- المناسبات: احتفال مرة وحدة لكل مرحلة ----------

const _milestones = [7, 30, 100, 182, 365, 500, 730, 1000, 1095, 1825];

String _milestoneLabel(int d) {
  switch (d) {
    case 7:
      return 'أسبوع';
    case 30:
      return 'شهر';
    case 182:
      return '6 شهور';
    case 365:
      return 'سنة';
    case 730:
      return 'سنتين';
    case 1095:
      return '3 سنين';
    case 1825:
      return '5 سنين';
    default:
      return '$d يوم';
  }
}

/// يرجع المرحلة اللي لازم نحتفل فيها الحين (أو null). يحفظ إنها انعرضت.
Future<int?> _milestoneToCelebrate(String chatId, int days) async {
  int? reached;
  for (final m in _milestones) {
    if (days >= m) reached = m;
  }
  if (reached == null) return null;
  try {
    final dir = await getApplicationSupportDirectory();
    final f = File('${dir.path}/milestone_$chatId.txt');
    final last = await f.exists() ? int.tryParse(await f.readAsString()) ?? 0 : 0;
    if (last >= reached) return null;
    await f.writeAsString('$reached');
    return reached;
  } catch (_) {
    return null;
  }
}

// ---------- ربطها بشاشة المحادثة ----------

extension _ChatFx on _ChatState {
  /// يشغّل التأثيرات للرسائل الجديدة بس (مو اللي كانت موجودة لما فتحنا)
  void _fxCheck(List<Map<String, dynamic>> rows) {
    var newest = _fxSeen;
    String? fx;
    for (final r in rows) {
      final id = (r['id'] as num).toInt();
      if (id > newest) newest = id;
      if (_fxSeen < 0 || id <= _fxSeen) continue;
      final kind = (r['kind'] as String?) ?? 'text';
      final effect = r['effect'] as String?;
      if (effect != null) {
        fx = effect;
      } else if (kind == 'think') {
        fx = 'hearts';
      } else if (kind == 'text' && _hasMagic((r['body'] as String?) ?? '')) {
        fx = 'hearts';
      }
    }
    final first = _fxSeen < 0;
    _fxSeen = newest;
    if (first || fx == null) return;
    final kind = fx;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _showEffect(context, kind);
    });
    unawaited(_loadStreak());
  }

  /// ضغطة مطوّلة على زر الإرسال: اختيار تأثير
  Future<void> _sendWithEffect() async {
    if (_c.text.trim().isEmpty) return;
    unawaited(HapticFeedback.mediumImpact());
    final fx = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text('أرسل مع تأثير',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
          ),
          ListTile(
            leading: const Text('❤️', style: TextStyle(fontSize: 24)),
            title: const Text('قلوب'),
            onTap: () => Navigator.pop(ctx, 'hearts'),
          ),
          ListTile(
            leading: const Text('🎉', style: TextStyle(fontSize: 24)),
            title: const Text('احتفال'),
            onTap: () => Navigator.pop(ctx, 'confetti'),
          ),
          ListTile(
            leading: const Text('✨', style: TextStyle(fontSize: 24)),
            title: const Text('نجوم'),
            onTap: () => Navigator.pop(ctx, 'stars'),
          ),
        ]),
      ),
    );
    if (fx == null || !mounted) return;
    await _send(effect: fx);
  }

  Future<void> _loadStreak() async {
    try {
      final r = await _db.rpc('chat_streak', params: {'p_chat': widget.chat.id});
      final n = (r as num?)?.toInt() ?? 0;
      if (mounted && n != _streak) setState(() => _streak = n);
    } catch (_) {}
  }

  Future<void> _checkMilestone() async {
    final since = _linkedAt;
    if (since == null || _milestoneChecked) return;
    _milestoneChecked = true;
    final days = DateTime.now().difference(since).inDays;
    final m = await _milestoneToCelebrate(widget.chat.id, days);
    if (m == null || !mounted) return;
    _showEffect(context, 'confetti');
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('🎉 مبروك!', textAlign: TextAlign.center),
        content: Text('صار لكم ${_milestoneLabel(m)} سوا في بيناتنا.',
            textAlign: TextAlign.center, style: const TextStyle(fontSize: 17)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('حلو')),
        ],
      ),
    );
  }

  // ---------- سؤال اليوم ----------

  Future<void> _loadDaily() async {
    try {
      final r = await _db.rpc('daily_get',
          params: {'p_chat': widget.chat.id, 'p_day': _dayStr(_today())});
      if (!mounted || r == null) return;
      final m = Map<String, dynamic>.from(r as Map);
      setState(() {
        _dailyReady = true;
        _dailyMine = m['mine'] as String?;
        _dailyTheirs = m['theirs'] as String?;
        _dailyTheirDone = m['their_done'] == true;
      });
    } catch (_) {}
  }

  Widget _dailyBar() {
    final mine = _dailyMine;
    final text = mine == null
        ? 'سؤال اليوم بانتظارك'
        : (_dailyTheirs != null
            ? 'انكشفت أجوبة سؤال اليوم'
            : 'جاوبت سؤال اليوم، بانتظار الطرف الثاني');
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: _Press(
        onTap: _openDaily,
        scale: 0.97,
        child: Glass(
          radius: 20,
          padding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
          child: Row(children: [
            const Text('💬', style: TextStyle(fontSize: 20)),
            const SizedBox(width: 10),
            Expanded(
                child: Text(text,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600))),
            const Icon(Icons.chevron_left_rounded),
          ]),
        ),
      ),
    );
  }

  Future<void> _openDaily() async {
    await showDialog<void>(
      context: context,
      builder: (_) => _DailyDialog(
        chatId: widget.chat.id,
        mine: _dailyMine,
        theirs: _dailyTheirs,
        theirDone: _dailyTheirDone,
      ),
    );
    _dailySeenReveal = _dailyTheirs != null;
    await _loadDaily();
  }

  bool get _showDailyBar =>
      _dailyReady && (_dailyMine == null || !_dailySeenReveal);
}

class _DailyDialog extends StatefulWidget {
  const _DailyDialog({
    required this.chatId,
    this.mine,
    this.theirs,
    this.theirDone = false,
  });
  final String chatId;
  final String? mine;
  final String? theirs;
  final bool theirDone;

  @override
  State<_DailyDialog> createState() => _DailyDialogState();
}

class _DailyDialogState extends State<_DailyDialog> {
  final _c = TextEditingController();
  bool _busy = false;
  late String? _mine = widget.mine;
  late String? _theirs = widget.theirs;
  late bool _theirDone = widget.theirDone;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final t = _c.text.trim();
    if (t.isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      await _db.rpc('daily_answer', params: {
        'p_chat': widget.chatId,
        'p_day': _dayStr(_today()),
        'p_answer': t,
      });
      final r = await _db.rpc('daily_get',
          params: {'p_chat': widget.chatId, 'p_day': _dayStr(_today())});
      final m = Map<String, dynamic>.from(r as Map);
      if (!mounted) return;
      setState(() {
        _mine = m['mine'] as String?;
        _theirs = m['theirs'] as String?;
        _theirDone = m['their_done'] == true;
        _busy = false;
      });
      if (_theirs != null) _showEffect(context, 'stars');
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      _toast(context, 'تعذر الإرسال، جرّب مرة ثانية.');
    }
  }

  Widget _answer(String who, String text) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(top: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0x1FFFFFFF),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0x33FFFFFF)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(who,
              style: const TextStyle(fontSize: 12, color: Color(0xB3FFFFFF))),
          const SizedBox(height: 4),
          Text(text, style: const TextStyle(fontSize: 15)),
        ]),
      );

  @override
  Widget build(BuildContext context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(24),
        child: Glass(
          radius: 28,
          blur: 30,
          padding: const EdgeInsets.all(20),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('سؤال اليوم',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: Color(0xB3FFFFFF))),
                const SizedBox(height: 6),
                Text(_todayQuestion(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 19, fontWeight: FontWeight.w700)),
                const SizedBox(height: 14),
                if (_mine == null) ...[
                  TextField(
                    controller: _c,
                    maxLength: 500,
                    minLines: 2,
                    maxLines: 5,
                    decoration: InputDecoration(
                      hintText: 'جوابك... ينكشف لما الاثنين يجاوبون',
                      filled: true,
                      fillColor: const Color(0x1AFFFFFF),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(color: _edge),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  _Btn(label: 'إرسال', onTap: _submit, busy: _busy),
                ] else ...[
                  _answer('جوابك', _mine!),
                  if (_theirs != null)
                    _answer('جواب الطرف الثاني', _theirs!)
                  else
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        _theirDone
                            ? 'الطرف الثاني جاوب، افتح السؤال مرة ثانية.'
                            : 'بانتظار جواب الطرف الثاني. جوابه ينكشف لك أول ما يجاوب.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Color(0xCCFFFFFF)),
                      ),
                    ),
                ],
                const SizedBox(height: 6),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('إغلاق'),
                ),
              ],
            ),
          ),
        ),
      );
}
