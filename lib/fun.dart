part of 'main.dart';

// ---------- متعة: رسم بالإصبع، بطاقات تهنئة، لو خيّروك، أسئلة تعارف، أفكار للطلعات ----------

// ========== رسم بالإصبع وإرساله كصورة ==========

class _Stroke {
  _Stroke(this.color, this.width);
  final Color color;
  final double width;
  final points = <Offset>[];
}

class DrawScreen extends StatefulWidget {
  const DrawScreen({super.key, required this.chatId, this.prompt});
  final String chatId;

  /// كلمة "ارسم وخمّن" (تظهر لك بس)
  final String? prompt;

  @override
  State<DrawScreen> createState() => _DrawState();
}

class _DrawState extends State<DrawScreen> {
  final _key = GlobalKey();
  final _strokes = <_Stroke>[];
  Color _color = Colors.white;
  double _width = 6;
  bool _busy = false;

  static const _palette = [
    Colors.white, Color(0xFFFF5FA2), Color(0xFF0A84FF), Color(0xFF34C759),
    Color(0xFFFFD60A), Color(0xFFFF9F0A), Color(0xFFBF5AF2), Colors.black,
  ];

  Future<void> _send() async {
    if (_strokes.isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      final box = _key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final img = await box.toImage(pixelRatio: 2);
      final data = await img.toByteData(format: ImageByteFormat.png);
      final dir = await getTemporaryDirectory();
      final f = File('${dir.path}/drawing_${DateTime.now().millisecondsSinceEpoch}.png');
      await f.writeAsBytes(data!.buffer.asUint8List());
      await _sendMedia(
          chatId: widget.chatId, file: f, kind: 'image', ext: 'png', mime: 'image/png');
      if (widget.prompt != null) {
        unawaited(_sendText(widget.chatId, '🎨 ارسم وخمّن: شنو رسمت؟ اكتب جوابك!'));
      }
      if (mounted) Navigator.pop(context);
    } on PostgrestException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _toast(
          context,
          e.message.contains('media_locked')
              ? 'الصور تنفتح لما الطرفين يضغطون «أثق فيه».'
              : 'تعذر الإرسال.');
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      _toast(context, 'تعذر الإرسال.');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(widget.prompt == null ? 'ارسم' : 'ارسم: ${widget.prompt}'),
          backgroundColor: Colors.transparent,
          actions: [
            IconButton(
              tooltip: 'تراجع',
              onPressed: _strokes.isEmpty
                  ? null
                  : () => setState(() => _strokes.removeLast()),
              icon: const Icon(Icons.undo_rounded),
            ),
            IconButton(
              tooltip: 'مسح',
              onPressed:
                  _strokes.isEmpty ? null : () => setState(_strokes.clear),
              icon: const Icon(Icons.delete_sweep_rounded),
            ),
          ],
        ),
        extendBodyBehindAppBar: true,
        body: Backdrop(
          child: SafeArea(
            child: Column(children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: RepaintBoundary(
                      key: _key,
                      child: Container(
                        color: const Color(0xFF1A1F3D),
                        child: GestureDetector(
                          onPanStart: (d) => setState(() => _strokes
                              .add(_Stroke(_color, _width)..points.add(d.localPosition))),
                          onPanUpdate: (d) => setState(
                              () => _strokes.last.points.add(d.localPosition)),
                          child: CustomPaint(
                            painter: _DrawPainter(_strokes),
                            size: Size.infinite,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(
                height: 52,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: [
                    for (final c in _palette)
                      GestureDetector(
                        onTap: () => setState(() => _color = c),
                        child: Container(
                          width: 36,
                          height: 36,
                          margin: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: c,
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: _color == c ? Colors.white : const Color(0x55FFFFFF),
                                width: _color == c ? 3 : 1),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Row(children: [
                const SizedBox(width: 16),
                const Icon(Icons.brush_rounded, size: 18),
                Expanded(
                  child: Slider(
                    value: _width,
                    min: 2,
                    max: 20,
                    onChanged: (v) => setState(() => _width = v),
                  ),
                ),
              ]),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: SizedBox(
                  width: double.infinity,
                  child: _Btn(label: 'إرسال الرسمة', onTap: _send, busy: _busy),
                ),
              ),
            ]),
          ),
        ),
      );
}

class _DrawPainter extends CustomPainter {
  _DrawPainter(this.strokes);
  final List<_Stroke> strokes;

  @override
  void paint(Canvas canvas, Size size) {
    for (final s in strokes) {
      final p = Paint()
        ..color = s.color
        ..strokeWidth = s.width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;
      if (s.points.length == 1) {
        canvas.drawCircle(s.points.first, s.width / 2, p..style = PaintingStyle.fill);
        continue;
      }
      final path = Path()..moveTo(s.points.first.dx, s.points.first.dy);
      for (final pt in s.points.skip(1)) {
        path.lineTo(pt.dx, pt.dy);
      }
      canvas.drawPath(path, p);
    }
  }

  @override
  bool shouldRepaint(_DrawPainter old) => true;
}

// ========== بطاقات جاهزة (صباح الخير، تصبح على خير، تهاني) ==========

const _greetCards = [
  ('☀️', 'صباح الخير', '☀️ صباح الخير يا أحلى صباح، يومك حلو مثلك', 'stars'),
  ('🌙', 'تصبح على خير', '🌙 تصبح على خير، نوم هني وأحلام حلوة', 'stars'),
  ('🌙', 'رمضان كريم', '🌙 رمضان كريم، الله يتقبل منا ومنك', 'stars'),
  ('🎉', 'عيد مبارك', '🎉 عيد مبارك وكل عام وأنت بخير', 'confetti'),
  ('🐑', 'عيد الأضحى', '🐑 عيد أضحى مبارك، ينعاد علينا وعليك بالخير', 'confetti'),
  ('🏮', 'ليالي رمضان', '🏮 ليالي رمضان أحلى وياك، الله يتقبل صيامك', 'stars'),
  ('🕌', 'جمعة مباركة', '🕌 جمعة مباركة، الله يسعدك ويحفظك', 'stars'),
  ('🎂', 'عيد ميلاد سعيد', '🎂 كل عام وأنت بخير، عيد ميلاد سعيد', 'confetti'),
  ('🎆', 'سنة حلوة', '🎆 سنة جديدة حلوة، وأحلى شي فيها إنك موجود', 'confetti'),
  ('💪', 'بالتوفيق', '💪 بالتوفيق اليوم، أنا واثق فيك', 'stars'),
  ('🤍', 'آسف', '🤍 آسف، ما كان قصدي أزعلك', 'hearts'),
];

Future<void> showCardsSheet(BuildContext context, String chatId) async {
  final pick = await showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text('بطاقات جاهزة',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
          ),
          for (var i = 0; i < _greetCards.length; i++)
            ListTile(
              leading: Text(_greetCards[i].$1, style: const TextStyle(fontSize: 24)),
              title: Text(_greetCards[i].$2),
              onTap: () => Navigator.pop(ctx, i),
            ),
        ]),
      ),
    ),
  );
  if (pick == null) return;
  final c = _greetCards[pick];
  try {
    await _db.from('messages').insert({'chat_id': chatId, 'body': c.$3, 'effect': c.$4});
  } catch (_) {
    try {
      await _sendText(chatId, c.$3);
    } catch (_) {
      if (context.mounted) _toast(context, 'تعذر الإرسال.');
    }
  }
}

// ========== لو خيّروك + أسئلة تعارف + أفكار للطلعات ==========

const _wouldYouRather = [
  ('تسافر للبحر', 'تسافر للجبل'),
  ('تاكل بيتزا طول عمرك', 'تاكل برگر طول عمرك'),
  ('تعرف المستقبل', 'تغيّر الماضي'),
  ('تعيش بمدينة كبيرة', 'تعيش بقرية هادئة'),
  ('تطير', 'تختفي'),
  ('صيف دائم', 'شتاء دائم'),
  ('سهرة بالبيت', 'طلعة برّا'),
  ('تقرأ أفكار الناس', 'تتكلم كل اللغات'),
  ('رحلة بالسيارة', 'رحلة بالطيارة'),
  ('فلم رعب', 'فلم كوميدي'),
  ('تصحى بدري', 'تسهر للصبح'),
  ('هدية مفاجأة', 'هدية تختارها'),
  ('قهوة', 'شاي'),
  ('تتذكر كل شي', 'تنسى اللي يزعلك'),
  ('بيت كبير بعيد', 'بيت صغير قريب'),
];

const _deepQuestions = [
  'شنو أكثر شي يخليك تحس بالأمان؟',
  'شنو الشي اللي تتمنى الناس يفهمونه عنك؟',
  'شنو أصعب قرار أخذته بحياتك؟',
  'شنو معنى الحب بالنسبة لك؟',
  'شنو الشي اللي غيّرك أكثر شي بالسنين اللي فاتت؟',
  'شنو تحتاج مني لما تكون تعبان؟',
  'شنو الذكرى اللي تبتسم كل ما تتذكرها؟',
  'شنو الحلم اللي تخاف تقوله؟',
  'شنو أكثر شي تفتخر فيه بنفسك؟',
  'وين تحس إنك بأحسن حالاتك؟',
];

const _dateIdeas = [
  'نطبخ أكلة جديدة سوا 🍳',
  'نشوف فلم ونطلب أكل 🍿',
  'تمشية وقت الغروب 🌅',
  'نروح كوفي جديد ما جربناه ☕',
  'ليلة ألعاب 🎲',
  'نسوي ألبوم صور لذكرياتنا 📸',
  'نزور مكان أول مرة نروحه 🗺️',
  'نكتب رسالة لبعض ونفتحها بعد سنة ✉️',
  'نتعلم شي جديد سوا (رقص، رسم، لغة) 🎨',
  'رحلة يوم واحد لمدينة قريبة 🚗',
  'جلسة نجوم بليلة صافية ✨',
  'فطور بالحديقة 🧺',
];

Future<void> showTalkCards(BuildContext context, String chatId, String kind) async {
  final r = Random();
  String make() {
    switch (kind) {
      case 'wyr':
        final p = _wouldYouRather[r.nextInt(_wouldYouRather.length)];
        return '🤔 لو خيّروك: ${p.$1} ولا ${p.$2}؟';
      case 'deep':
        return '💭 ${_deepQuestions[r.nextInt(_deepQuestions.length)]}';
      default:
        return '💡 فكرة لطلعتنا: ${_dateIdeas[r.nextInt(_dateIdeas.length)]}';
    }
  }

  var text = make();
  final send = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => AlertDialog(
        title: Text(kind == 'wyr'
            ? 'لو خيّروك'
            : kind == 'deep'
                ? 'سؤال تعارف'
                : 'أفكار للطلعات'),
        content: Text(text, style: const TextStyle(fontSize: 18, height: 1.5)),
        actions: [
          TextButton(
              onPressed: () => set(() => text = make()),
              child: const Text('غيرها')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('أرسل')),
        ],
      ),
    ),
  );
  if (send != true) return;
  try {
    await _sendText(chatId, text);
  } catch (_) {
    if (context.mounted) _toast(context, 'تعذر الإرسال.');
  }
}
