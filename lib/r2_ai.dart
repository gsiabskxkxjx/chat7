part of 'main.dart';

// ---------- الجولة الثانية: المساعد الذكي (Groq عبر دالة ai-assist) ----------
// ترجمة (361)، تلخيص صوتي (362)، اقتراح رد (363)، تصحيح (364)، التقاط المواعيد محلياً (366)،
// شنو فاتك (367)، هدايا (368)، طلعات (369)، رسائل مناسبات (370)

Future<bool> _aiConsent(BuildContext context) async {
  if (_R2Store.get<bool>('ai_ok') == true) return true;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('المساعد الذكي 🤖'),
      content: const Text(
          'النص اللي تختاره ينرسل عبر سيرفرنا لخدمة ذكاء اصطناعي خارجية (Groq) حتى ترجع النتيجة، وما ننحفظ عندنا ولا عندهم. بدون موافقتك ما يشتغل. تكمل؟',
          style: TextStyle(height: 1.6)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('لا')),
        TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('أوافق')),
      ],
    ),
  );
  if (ok == true) await _R2Store.set('ai_ok', true);
  return ok == true;
}

/// يستدعي المساعد ويرجّع الرد، أو null مع رسالة خطأ
Future<Map<String, dynamic>?> _aiCall(BuildContext context, String task, String text,
    {String? lang, String? style}) async {
  if (!await _aiConsent(context) || !context.mounted) return null;
  unawaited(showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(child: CircularProgressIndicator()),
  ));
  Map<String, dynamic>? out;
  Object? err;
  try {
    final res = await _db.functions
        .invoke('ai-assist', body: {'task': task, 'text': text, if (lang != null) 'lang': lang, if (style != null) 'style': style})
        .timeout(const Duration(seconds: 45), onTimeout: () => throw const _NetTimeout());
    final d = res.data;
    if (d is Map) {
      out = Map<String, dynamic>.from(d);
    } else if (d is String) {
      out = Map<String, dynamic>.from(jsonDecode(d) as Map);
    }
  } catch (e) {
    err = e;
  }
  if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
  if (out == null && context.mounted) {
    _toast(context, _friendlyError(err ?? 'x', fallback: 'تعذر الحصول على رد. جرّب مرة ثانية.'));
  }
  return out;
}

Future<void> _aiShow(BuildContext context, String title, String text, {String? useLabel, VoidCallback? onUse}) =>
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(child: SelectableText(text, style: const TextStyle(height: 1.7))),
        actions: [
          TextButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: text));
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('نسخ')),
          if (onUse != null)
            TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  onUse();
                },
                child: Text(useLabel ?? 'استخدمه')),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إغلاق')),
        ],
      ),
    );

const _aiLangs = [
  ('ar', 'العربية'),
  ('en', 'English'),
  ('tr', 'Türkçe'),
  ('fa', 'فارسی'),
  ('ku', 'کوردی'),
  ('fr', 'Français'),
  ('de', 'Deutsch'),
  ('es', 'Español'),
  ('ru', 'Русский'),
  ('ur', 'اردو'),
];

// ----- التقاط المواعيد من النص محلياً (بدون ذكاء اصطناعي) -----

class _Appt {
  const _Appt(this.date, this.label);
  final DateTime date;
  final String label;
}

_Appt? _findAppointment(String text, [DateTime? now]) {
  final t = _asciiDigits(text);
  final today = now ?? _today();
  DateTime? d;
  String label = '';
  if (t.contains('بعد بكرة') || t.contains('بعد بكره')) {
    d = today.add(const Duration(days: 2));
    label = 'بعد بكرة';
  } else if (t.contains('بكرة') || t.contains('بكره') || t.contains('غداً') || t.contains('غدا')) {
    d = today.add(const Duration(days: 1));
    label = 'بكرة';
  } else if (t.contains('اليوم') || t.contains('الليلة')) {
    d = today;
    label = 'اليوم';
  } else {
    const days = {'الأحد': 7, 'الاثنين': 1, 'الإثنين': 1, 'الثلاثاء': 2, 'الأربعاء': 3, 'الخميس': 4, 'الجمعة': 5, 'السبت': 6};
    for (final e in days.entries) {
      if (t.contains(e.key)) {
        var diff = (e.value - today.weekday) % 7;
        if (diff == 0) diff = 7;
        d = today.add(Duration(days: diff));
        label = e.key;
        break;
      }
    }
    final m = RegExp(r'(\d{1,2})[/-](\d{1,2})').firstMatch(t);
    if (d == null && m != null) {
      final day = int.parse(m.group(1)!), mon = int.parse(m.group(2)!);
      if (day >= 1 && day <= 31 && mon >= 1 && mon <= 12) {
        var y = today.year;
        var cand = DateTime(y, mon, day);
        if (cand.isBefore(today)) cand = DateTime(y + 1, mon, day);
        d = cand;
        label = '${m.group(1)}/${m.group(2)}';
      }
    }
  }
  if (d == null) return null;
  // لازم يكون في إشارة لموعد أو وقت حتى ما نلتقط أي جملة فيها «اليوم»
  final hasTime = RegExp(r'(الساعة|الساعه|ساعة|\d{1,2}:\d{2}|موعد|نلتقي|نتقابل|عشاء|غداء|اجتماع|مكالمة|حفلة|سفر)').hasMatch(t);
  if (!hasTime) return null;
  return _Appt(d, label);
}

extension _R2Ai on _ChatState {
  Future<void> _aiTranslate(Msg m) async {
    final lang = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Padding(padding: EdgeInsets.all(12), child: Text('ترجمة إلى...')),
            for (final l in _aiLangs) ListTile(title: Text(l.$2), onTap: () => Navigator.pop(ctx, l.$1)),
          ]),
        ),
      ),
    );
    if (lang == null || !mounted) return;
    final r = await _aiCall(context, 'translate', m.text, lang: lang);
    if (r != null && mounted) await _aiShow(context, 'الترجمة', '${r['text']}');
  }

  Future<void> _aiReplies(Msg m) async {
    final r = await _aiCall(context, 'reply', m.text);
    if (r == null || !mounted) return;
    final opts = [for (final e in ((r['options'] as List?) ?? const [])) Map<String, dynamic>.from(e as Map)];
    if (opts.isEmpty) {
      _toast(context, 'ما طلعت اقتراحات.');
      return;
    }
    const names = {'romantic': '💗 رومانسي', 'funny': '😄 مرح', 'short': '⚡ مختصر'};
    final pick = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(padding: EdgeInsets.all(12), child: Text('اختر ردّ وعدّله قبل الإرسال')),
          for (final o in opts)
            ListTile(
              title: Text('${o['text']}'),
              subtitle: Text(names['${o['style']}'] ?? ''),
              onTap: () => Navigator.pop(ctx, '${o['text']}'),
            ),
        ]),
      ),
    );
    if (pick != null && mounted) {
      setState(() => _c.text = pick);
      _c.selection = TextSelection.collapsed(offset: _c.text.length);
    }
  }

  Future<void> _aiFixDraft() async {
    final t = _c.text.trim();
    if (t.isEmpty) {
      _toast(context, 'اكتب النص بمربع الكتابة أول.');
      return;
    }
    final r = await _aiCall(context, 'fix', t);
    if (r == null || !mounted) return;
    final fixed = '${r['text']}';
    await _aiShow(context, 'النص المصحّح', fixed, useLabel: 'استبدل', onUse: () {
      setState(() => _c.text = fixed);
    });
  }

  Future<void> _aiSummarizeText(String text) async {
    final r = await _aiCall(context, 'summarize', text);
    if (r != null && mounted) await _aiShow(context, 'الملخص', '${r['text']}');
  }

  Future<void> _aiCatchUp() async {
    final texts = _lastMsgs.where((m) => m.kind == 'text' && m.text.trim().isNotEmpty).take(80).toList().reversed.toList();
    if (texts.length < 3) {
      _toast(context, 'ما في رسائل كافية للتلخيص.');
      return;
    }
    final buf = StringBuffer();
    for (final m in texts) {
      buf.writeln('${m.mine ? 'أنا' : 'هو'}: ${m.text}');
    }
    final r = await _aiCall(context, 'catchup', buf.toString());
    if (r != null && mounted) await _aiShow(context, 'شنو فاتك', '${r['text']}');
  }

  Future<void> _addAppointment(_Appt a, String text) async {
    final title = text.length > 60 ? text.substring(0, 60) : text;
    try {
      await _net(_db.from('chat_events').insert({
        'chat_id': widget.chat.id,
        'title': title,
        'on_date': _dayStr(a.date),
      }));
      if (mounted) _toast(context, 'انضاف للتقويم: ${_Fmt.date(a.date)}');
    } catch (e) {
      if (mounted) _toast(context, _friendlyError(e));
    }
  }
}

// ===== شاشات المساعد (هدايا، طلعات، مناسبات) =====

class AiHelperScreen extends StatefulWidget {
  const AiHelperScreen({super.key, required this.chatId, required this.mode});
  final String chatId;
  final String mode; // gift | outing | occasion

  @override
  State<AiHelperScreen> createState() => _AiHelperState();
}

class _AiHelperState extends State<AiHelperScreen> {
  final _a = TextEditingController();
  final _b = TextEditingController();
  String _style = 'romantic';
  String _when = 'المساء';
  String _weather = 'جو معتدل';
  bool _busy = false;
  List<Map<String, dynamic>> _ideas = const [];
  String? _text;

  @override
  void dispose() {
    _a.dispose();
    _b.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    if (widget.mode == 'gift') unawaited(_loadWishes());
  }

  Future<void> _loadWishes() async {
    try {
      final rows = await _db
          .from('shared_items')
          .select('body,list_name')
          .eq('chat_id', widget.chatId)
          .ilike('list_name', '%أمني%')
          .limit(20);
      final items = [for (final r in rows) '${r['body']}'];
      if (items.isNotEmpty && mounted) _a.text = items.join('، ');
    } catch (_) {}
  }

  String get _title => switch (widget.mode) {
        'gift' => '🎁 أفكار هدايا',
        'outing' => '🗺️ أفكار طلعات',
        _ => '✍️ رسالة مناسبة',
      };

  Future<void> _run() async {
    setState(() => _busy = true);
    final String task;
    final String input;
    switch (widget.mode) {
      case 'gift':
        task = 'gift';
        input = 'قائمة الأمنيات والاهتمامات: ${_a.text.trim().isEmpty ? 'غير محددة' : _a.text.trim()}\nالميزانية: ${_b.text.trim().isEmpty ? 'متوسطة' : _b.text.trim()}';
      case 'outing':
        task = 'outing';
        input = 'الوقت: $_when\nالميزانية: ${_b.text.trim().isEmpty ? 'متوسطة' : _b.text.trim()}\nالطقس: $_weather\nملاحظات: ${_a.text.trim()}';
      default:
        task = 'occasion';
        input = 'المناسبة: ${_a.text.trim().isEmpty ? 'عيد ميلاد' : _a.text.trim()}\nتفاصيل: ${_b.text.trim()}';
    }
    final r = await _aiCall(context, task, input, style: _style);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (r != null) {
        _ideas = [for (final e in ((r['ideas'] as List?) ?? const [])) Map<String, dynamic>.from(e as Map)];
        _text = r['text'] as String?;
      }
    });
  }

  @override
  Widget build(BuildContext context) => _R2Page(
        title: _title,
        child: ListView(padding: const EdgeInsets.all(_Sp.lg), children: [
          TextField(
            controller: _a,
            maxLines: 3,
            minLines: 1,
            decoration: InputDecoration(
                hintText: switch (widget.mode) {
              'gift' => 'اهتماماته وأمنياته',
              'outing' => 'ملاحظات (اختياري)',
              _ => 'المناسبة (عيد ميلاد، ذكرى...)',
            }),
          ),
          const SizedBox(height: _Sp.sm),
          TextField(
            controller: _b,
            decoration: InputDecoration(
                hintText: widget.mode == 'occasion' ? 'شي تبي تذكره (اختياري)' : 'الميزانية (مثلاً 50 ألف)'),
          ),
          const SizedBox(height: _Sp.md),
          if (widget.mode == 'outing') ...[
            Wrap(spacing: 8, children: [
              for (final w in const ['الصبح', 'العصر', 'المساء', 'الليل', 'نهاية الأسبوع'])
                ChoiceChip(label: Text(w), selected: _when == w, onSelected: (_) => setState(() => _when = w)),
            ]),
            const SizedBox(height: _Sp.sm),
            Wrap(spacing: 8, children: [
              for (final w in const ['جو حار', 'جو معتدل', 'بارد', 'ممطر'])
                ChoiceChip(label: Text(w), selected: _weather == w, onSelected: (_) => setState(() => _weather = w)),
            ]),
            const SizedBox(height: _Sp.md),
          ],
          if (widget.mode == 'occasion') ...[
            Wrap(spacing: 8, children: [
              for (final s in const [('romantic', 'رومانسي'), ('funny', 'مرح'), ('short', 'مختصر'), ('poetic', 'شاعري')])
                ChoiceChip(label: Text(s.$2), selected: _style == s.$1, onSelected: (_) => setState(() => _style = s.$1)),
            ]),
            const SizedBox(height: _Sp.md),
          ],
          _Btn(label: 'اقترح', onTap: _run, busy: _busy),
          const SizedBox(height: _Sp.lg),
          for (final i in _ideas)
            Padding(
              padding: const EdgeInsets.only(bottom: _Sp.sm),
              child: Glass(
                radius: 20,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${i['title']}', style: const TextStyle(fontSize: _Fs.title, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text('${i['why']}', style: const TextStyle(color: Color(0xCCFFFFFF), height: 1.5)),
                ]),
              ),
            ),
          if (_text != null)
            Glass(
              radius: 20,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                SelectableText(_text!, style: const TextStyle(height: 1.8, fontSize: _Fs.bodyL)),
                const SizedBox(height: _Sp.sm),
                Row(children: [
                  Expanded(
                      child: OutlinedButton(
                          onPressed: () async {
                            await Clipboard.setData(ClipboardData(text: _text!));
                            if (context.mounted) _toast(context, 'تم النسخ');
                          },
                          child: const Text('نسخ'))),
                  const SizedBox(width: _Sp.md),
                  Expanded(
                      child: _Btn(
                          label: 'أرسلها',
                          onTap: () async {
                            try {
                              await _sendText(widget.chatId, _text!);
                              if (context.mounted) _toast(context, 'انرسلت');
                            } catch (e) {
                              if (context.mounted) _toast(context, _friendlyError(e));
                            }
                          })),
                ]),
              ]),
            ),
          const SizedBox(height: _Sp.md),
          const Text('اقتراحات مولّدة بالذكاء الاصطناعي، راجعها قبل الاستخدام. الحد اليومي 40 طلب.',
              textAlign: TextAlign.center, style: TextStyle(fontSize: _Fs.small, color: Color(0xB3FFFFFF))),
        ]),
      );
}

List<_MenuItem> _r2AiItems(BuildContext context, String chatId) {
  void push(Widget w) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => w));
  return [
    (Icons.card_giftcard_rounded, 'أفكار هدايا', 'من أمنياتكم وميزانيتك', () => push(AiHelperScreen(chatId: chatId, mode: 'gift'))),
    (Icons.explore_rounded, 'أفكار طلعات', 'حسب الوقت والميزانية والطقس', () => push(AiHelperScreen(chatId: chatId, mode: 'outing'))),
    (Icons.edit_note_rounded, 'مساعد رسائل المناسبات', 'ميلاد، ذكرى... بأسلوبك', () => push(AiHelperScreen(chatId: chatId, mode: 'occasion'))),
  ];
}
