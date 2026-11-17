part of 'main.dart';

// ---------- سوا: جدار الحب، تقويمنا، تحدي الصورة، أسبوع التعارف، رسالة الوداع ----------

const _noteColors = [
  Color(0xFFFFD60A), Color(0xFFFF9FC6), Color(0xFF8FD3FF), Color(0xFFA6F0B5),
  Color(0xFFFFB37A), Color(0xFFCDB4FF), Color(0xFFFFFFFF), Color(0xFFFF8A80),
];

bool _missingTable(Object e) {
  final m = e.toString();
  return m.contains('does not exist') ||
      m.contains('PGRST205') ||
      m.contains('PGRST202') ||
      m.contains('schema cache');
}

// ===== جدار ملاحظات الحب =====

class LoveNotesScreen extends StatefulWidget {
  const LoveNotesScreen({super.key, required this.chatId});
  final String chatId;

  @override
  State<LoveNotesScreen> createState() => _LoveNotesState();
}

class _LoveNotesState extends State<LoveNotesScreen> {
  late final Stream<List<Map<String, dynamic>>> _s = _db
      .from('love_notes')
      .stream(primaryKey: ['id'])
      .eq('chat_id', widget.chatId)
      .order('id', ascending: false)
      .limit(200);

  String get _me => _db.auth.currentUser?.id ?? '';

  Future<void> _add() async {
    final c = TextEditingController();
    var color = 0;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('ملاحظة حب'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: c,
              autofocus: true,
              maxLength: 140,
              maxLines: 3,
              decoration: const InputDecoration(hintText: 'جملة قصيرة تبقى على الجدار'),
            ),
            Wrap(spacing: 8, children: [
              for (var i = 0; i < _noteColors.length; i++)
                GestureDetector(
                  onTap: () => set(() => color = i),
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: _noteColors[i],
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: color == i ? Colors.white : Colors.transparent,
                          width: 3),
                    ),
                  ),
                ),
            ]),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('إلغاء')),
            TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('علّقها')),
          ],
        ),
      ),
    );
    final t = c.text.trim();
    c.dispose();
    if (ok != true || t.isEmpty) return;
    try {
      await _db
          .from('love_notes')
          .insert({'chat_id': widget.chatId, 'body': t, 'color': color});
      unawaited(_sendText(widget.chatId, '📌 علّقت لك ملاحظة على جدار الحب'));
    } catch (e) {
      if (mounted) {
        _toast(context,
            _missingTable(e) ? 'جدار الحب يحتاج تحديث السيرفر (update_4).' : 'تعذر الحفظ.');
      }
    }
  }

  Future<void> _remove(Map<String, dynamic> n) async {
    if (n['author'] != _me) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تشيل الملاحظة؟'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false), child: const Text('لا')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true), child: const Text('شيلها')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _db.from('love_notes').delete().eq('id', n['id']);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
            title: const Text('جدار الحب'), backgroundColor: Colors.transparent),
        extendBodyBehindAppBar: true,
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _add,
          icon: const Icon(Icons.push_pin_rounded),
          label: const Text('ملاحظة'),
        ),
        body: Backdrop(
          child: SafeArea(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: _s,
              builder: (_, snap) {
                if (snap.hasError) {
                  return const Center(
                      child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text('جدار الحب يحتاج تحديث السيرفر (update_4).',
                        textAlign: TextAlign.center),
                  ));
                }
                final rows = snap.data;
                if (rows == null) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (rows.isEmpty) {
                  return const Center(
                      child: Text('علّق أول ملاحظة 📌',
                          style: TextStyle(fontSize: _Fs.heading)));
                }
                return GridView.builder(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 90),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 14,
                      crossAxisSpacing: 14,
                      childAspectRatio: 1),
                  itemCount: rows.length,
                  itemBuilder: (_, i) {
                    final n = rows[i];
                    final col = _noteColors[
                        ((n['color'] as num?)?.toInt() ?? 0) % _noteColors.length];
                    final mine = n['author'] == _me;
                    final at = DateTime.tryParse('${n['created_at']}')?.toLocal();
                    return GestureDetector(
                      onLongPress: () => _remove(n),
                      child: Transform.rotate(
                        angle: (i.isEven ? -1 : 1) * 0.025,
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: col,
                            borderRadius: BorderRadius.circular(6),
                            boxShadow: const [
                              BoxShadow(
                                  color: Color(0x55000000),
                                  blurRadius: 12,
                                  offset: Offset(0, 6)),
                            ],
                          ),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Text('${n['body']}',
                                      overflow: TextOverflow.fade,
                                      style: const TextStyle(
                                          fontSize: _Fs.title,
                                          height: 1.4,
                                          color: Color(0xFF2A2A2A),
                                          fontWeight: FontWeight.w600)),
                                ),
                                Text(
                                    '${mine ? 'منك' : 'منه'}${at == null ? '' : ' · ${at.day}/${at.month}'}',
                                    style: const TextStyle(
                                        fontSize: _Fs.caption, color: Color(0x99000000))),
                              ]),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ),
      );
}

// ===== تقويمنا =====

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key, required this.chatId});
  final String chatId;

  @override
  State<CalendarScreen> createState() => _CalendarState();
}

class _CalendarState extends State<CalendarScreen> {
  late final Stream<List<Map<String, dynamic>>> _s = _db
      .from('chat_events')
      .stream(primaryKey: ['id'])
      .eq('chat_id', widget.chatId)
      .order('on_date', ascending: true);
  bool _showPast = false;

  Future<void> _add() async {
    final c = TextEditingController();
    DateTime? day;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('موعد جديد'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: c,
              autofocus: true,
              maxLength: 60,
              decoration: const InputDecoration(hintText: 'مثل: عشاء، سفر، موعد'),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_rounded),
              title: Text(day == null
                  ? 'اختر اليوم'
                  : '${day!.day} ${_months[day!.month - 1]} ${day!.year}'),
              onTap: () async {
                final now = DateTime.now();
                final d = await showDatePicker(
                  context: ctx,
                  initialDate: now,
                  firstDate: DateTime(now.year - 1),
                  lastDate: DateTime(now.year + 5),
                );
                if (d != null) set(() => day = d);
              },
            ),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('إلغاء')),
            TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('حفظ')),
          ],
        ),
      ),
    );
    final t = c.text.trim();
    c.dispose();
    final d = day;
    if (ok != true || t.isEmpty || d == null) return;
    try {
      await _db.from('chat_events').insert(
          {'chat_id': widget.chatId, 'title': t, 'on_date': _dayStr(d)});
      unawaited(_sendText(widget.chatId,
          '📅 ضفت موعد: $t (${d.day} ${_months[d.month - 1]})'));
    } catch (e) {
      if (mounted) {
        _toast(context,
            _missingTable(e) ? 'التقويم يحتاج تحديث السيرفر (update_4).' : 'تعذر الحفظ.');
      }
    }
  }

  Future<void> _remove(Map<String, dynamic> e) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('تحذف «${e['title']}»؟'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false), child: const Text('لا')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true), child: const Text('احذف')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _db.from('chat_events').delete().eq('id', e['id']);
    } catch (_) {}
  }

  Widget _tile(Map<String, dynamic> e) {
    final d = DateTime.tryParse('${e['on_date']}');
    final days = d == null ? 0 : d.difference(_today()).inDays;
    final when = d == null
        ? ''
        : days == 0
            ? 'اليوم'
            : days == 1
                ? 'بكرة'
                : days > 1
                    ? 'بعد $days يوم'
                    : 'قبل ${-days} يوم';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onLongPress: () => _remove(e),
        child: Glass(
          radius: 20,
          shadow: false,
          padding: const EdgeInsets.all(_Sp.md),
          child: Row(children: [
            Container(
              width: 52,
              padding: const EdgeInsets.symmetric(vertical: 6),
              decoration: BoxDecoration(
                color: days == 0 ? const Color(0x66FF5FA2) : const Color(0x26FFFFFF),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(children: [
                Text(d == null ? '' : '${d.day}',
                    style: const TextStyle(fontSize: _Fs.display, fontWeight: FontWeight.w800)),
                Text(d == null ? '' : _months[d.month - 1],
                    style: const TextStyle(fontSize: 10)),
              ]),
            ),
            const SizedBox(width: _Sp.md),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${e['title']}',
                    style: const TextStyle(fontSize: _Fs.title, fontWeight: FontWeight.w600)),
                Text(when, style: const TextStyle(fontSize: _Fs.small, color: Color(0xB3FFFFFF))),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
            title: const Text('تقويمنا'), backgroundColor: Colors.transparent),
        extendBodyBehindAppBar: true,
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _add,
          icon: const Icon(Icons.add_rounded),
          label: const Text('موعد'),
        ),
        body: Backdrop(
          child: SafeArea(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: _s,
              builder: (_, snap) {
                if (snap.hasError) {
                  return const Center(
                      child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text('التقويم يحتاج تحديث السيرفر (update_4).',
                        textAlign: TextAlign.center),
                  ));
                }
                final rows = snap.data;
                if (rows == null) {
                  return const Center(child: CircularProgressIndicator());
                }
                final today = _today();
                final next = rows
                    .where((e) => !(DateTime.tryParse('${e['on_date']}') ?? today)
                        .isBefore(today))
                    .toList();
                final past = rows
                    .where((e) => (DateTime.tryParse('${e['on_date']}') ?? today)
                        .isBefore(today))
                    .toList()
                    .reversed
                    .toList();
                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
                  children: [
                    if (next.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(_Sp.xl),
                        child: Text('ما في مواعيد جاية. ضيفوا أول موعد 📅',
                            textAlign: TextAlign.center),
                      ),
                    for (final e in next) _tile(e),
                    if (past.isNotEmpty)
                      TextButton(
                        onPressed: () => setState(() => _showPast = !_showPast),
                        child: Text(_showPast
                            ? 'إخفاء المواعيد اللي فاتت'
                            : 'المواعيد اللي فاتت (${past.length})'),
                      ),
                    if (_showPast) for (final e in past) _tile(e),
                  ],
                );
              },
            ),
          ),
        ),
      );
}

// ===== تحدي الصورة اليومي =====

const _photoPrompts = [
  'شي أزرق حولك', 'منظر من شباكك', 'كوب مشروبك الحين', 'شي يضحكك', 'ظلّك',
  'أحلى زاوية بغرفتك', 'شي لونه أحمر', 'السما الحين', 'أكلك اليوم', 'يدك مع شي تحبه',
  'شي قديم عندك', 'حذاك اليوم', 'شي يذكرك فيني', 'نبتة أو وردة', 'كتاب أو دفتر',
  'شي دائري', 'الطريق اللي قدامك', 'شي يلمع', 'وجه مضحك', 'مكانك المفضل بالبيت',
  'شي حلو المذاق', 'رقم تشوفه الحين', 'شي ناعم', 'ضوء جميل', 'شي لونه أخضر',
  'أول شي تشوفه بالصبح', 'شي تستخدمه كل يوم', 'حيوان (أو صورته)', 'شي صغير جداً', 'الغروب أو الليل',
];

String _todayPrompt() {
  final d = _today();
  return _photoPrompts[d.difference(DateTime(2024)).inDays % _photoPrompts.length];
}

class PhotoChallengeScreen extends StatefulWidget {
  const PhotoChallengeScreen({super.key, required this.chatId});
  final String chatId;

  @override
  State<PhotoChallengeScreen> createState() => _PhotoChallengeState();
}

class _PhotoChallengeState extends State<PhotoChallengeScreen> {
  Map<String, dynamic>? _st;
  bool _busy = false;
  String? _err;
  final _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final r = await _db.rpc('challenge_get',
          params: {'p_chat': widget.chatId, 'p_day': _dayStr(_today())});
      if (mounted) {
        setState(() {
          _st = Map<String, dynamic>.from(r as Map);
          _err = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _err = _missingTable(e)
            ? 'التحدي يحتاج تحديث السيرفر (update_4).'
            : 'تعذر التحميل، تأكد من الإنترنت.');
      }
    }
  }

  Future<void> _shoot() async {
    if (_busy) return;
    final okExplain = await _explainOnce(context,
        key: 'camera',
        icon: Icons.photo_camera_rounded,
        title: 'الكاميرا',
        text: 'نحتاج الكاميرا حتى تصوّر وترسل للطرف الثاني مباشرة.');
    if (!okExplain || !mounted) return;
    final XFile? x;
    try {
      x = await _picker.pickImage(
          source: ImageSource.camera,
          maxWidth: 1600,
          maxHeight: 1600,
          imageQuality: 82);
    } catch (_) {
      if (mounted) _toast(context, 'تعذر فتح الكاميرا.');
      return;
    }
    if (x == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final day = _dayStr(_today());
      final path =
          '${widget.chatId}/challenge_${day}_${DateTime.now().millisecondsSinceEpoch}.${_extFor(x.path)}';
      await _db.storage.from('chat-media').upload(path, File(x.path),
          fileOptions: FileOptions(contentType: _mimeFor(x.path)));
      await _db.rpc('challenge_submit',
          params: {'p_chat': widget.chatId, 'p_day': day, 'p_path': path});
      unawaited(_sendText(widget.chatId, '📸 خلّصت تحدي الصورة اليوم، دورك!'));
      await _load();
    } on PostgrestException catch (e) {
      if (mounted) {
        _toast(
            context,
            e.message.contains('media_locked')
                ? 'الصور تنفتح لما الطرفين يضغطون «أثق فيه».'
                : 'تعذر الإرسال.');
      }
    } catch (_) {
      if (mounted) _toast(context, 'تعذر الإرسال، تأكد من الإنترنت.');
    }
    if (mounted) setState(() => _busy = false);
  }

  Widget _slot(String label, String? path, String empty, {VoidCallback? onTap}) =>
      Expanded(
        child: Column(children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: _Sp.sm),
          AspectRatio(
            aspectRatio: 0.8,
            child: _Press(
              onTap: onTap,
              dimWhenOff: false,
              child: Glass(
                radius: 20,
                shadow: false,
                padding: EdgeInsets.zero,
                child: path != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: SizedBox.expand(
                          child: FittedBox(
                              fit: BoxFit.cover,
                              clipBehavior: Clip.hardEdge,
                              child: _NetImage(path: path)),
                        ),
                      )
                    : Center(
                        child: Padding(
                          padding: const EdgeInsets.all(_Sp.md),
                          child: Text(empty,
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Color(0xCCFFFFFF))),
                        ),
                      ),
              ),
            ),
          ),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final st = _st;
    final mine = st?['mine'] as String?;
    final theirs = st?['theirs'] as String?;
    final theirDone = st?['their_done'] == true;
    return Scaffold(
      appBar: AppBar(
          title: const Text('تحدي الصورة'),
          backgroundColor: Colors.transparent,
          actions: [
            IconButton(
                tooltip: 'تحديث',
                onPressed: _load,
                icon: const Icon(Icons.refresh_rounded)),
          ]),
      extendBodyBehindAppBar: true,
      body: Backdrop(
        child: SafeArea(
          child: _err != null
              ? Center(
                  child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(_err!, textAlign: TextAlign.center)))
              : ListView(padding: const EdgeInsets.all(20), children: [
                  Glass(
                    radius: 24,
                    padding: const EdgeInsets.all(18),
                    child: Column(children: [
                      const Text('تحدي اليوم',
                          style: TextStyle(color: Color(0xB3FFFFFF))),
                      const SizedBox(height: 6),
                      Text(_todayPrompt(),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontSize: 22, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 6),
                      const Text('صوّر، والصورتين تنكشف لما الاثنين يخلصون.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: _Fs.small, color: Color(0xB3FFFFFF))),
                    ]),
                  ),
                  const SizedBox(height: 18),
                  if (st == null)
                    const Center(child: CircularProgressIndicator())
                  else
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      _slot('أنت', mine,
                          _busy ? 'جاري الإرسال...' : '📷\nاضغط وصوّر',
                          onTap: mine == null && !_busy ? _shoot : null),
                      const SizedBox(width: _Sp.md),
                      _slot(
                          'هو',
                          theirs,
                          theirDone
                              ? (mine == null ? 'خلّص! صوّر حتى تشوف صورته 👀' : '')
                              : 'بانتظاره ⏳'),
                    ]),
                ]),
        ),
      ),
    );
  }
}

// ===== رسالة الوداع =====

/// يرجع null لو ألغى، ونص (ممكن فاضي) لو كمّل
Future<String?> _askFarewell(BuildContext context) async {
  final c = TextEditingController();
  final r = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('كلمة أخيرة؟'),
      content: TextField(
        controller: c,
        maxLength: 200,
        maxLines: 3,
        decoration: const InputDecoration(
            hintText: 'اختياري: تصله مرة وحدة بعد فك الارتباط'),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx), child: const Text('تراجع')),
        TextButton(
            onPressed: () => Navigator.pop(ctx, c.text.trim()),
            child: const Text('كمّل')),
      ],
    ),
  );
  c.dispose();
  return r;
}

Future<void> _sendFarewell(String text) async {
  if (text.isEmpty) return;
  try {
    await _db.rpc('say_farewell', params: {'p_body': text});
  } catch (_) {}
}

/// بعد ما الطرف الثاني يفك الارتباط: نعرض كلمته الأخيرة (مرة وحدة)
Future<void> _checkFarewell(BuildContext context) async {
  try {
    final r = await _db.rpc('farewell_take');
    if (r is! Map || !context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Text('🕊️', style: TextStyle(fontSize: 36)),
        title: Text('كلمة من ${r['name'] ?? 'الطرف الثاني'}'),
        content: Text('${r['body']}', textAlign: TextAlign.center),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('تمام')),
        ],
      ),
    );
  } catch (_) {}
}

// ===== أسبوع التعارف + تذكيرات اليوم بالمحادثة =====

extension _ChatTogether on _ChatState {
  bool get _askContinue =>
      _matched &&
      _contMine == null &&
      _matchedOn != null &&
      DateTime.now().difference(_matchedOn!) >= const Duration(days: 7);

  Widget _continueBar() => Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: Glass(
          radius: 20,
          shadow: false,
          tint: const Color(0xFFFF5FA2),
          padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
          child: Row(children: [
            const Text('🌱', style: TextStyle(fontSize: 22)),
            const SizedBox(width: 10),
            const Expanded(
              child: Text('صار لكم أسبوع. تكملون سوا؟',
                  style: TextStyle(fontWeight: FontWeight.w600)),
            ),
            TextButton(onPressed: () => _answerContinue(false), child: const Text('لا')),
            FilledButton(
                onPressed: () => _answerContinue(true), child: const Text('نكمل 💞')),
          ]),
        ),
      );

  Future<void> _answerContinue(bool yes) async {
    if (!yes) {
      await _endMatch();
      return;
    }
    setState(() => _contMine = true);
    try {
      await _db
          .from('chats')
          .update({_iAmA ? 'continue_a' : 'continue_b': true}).eq('id', widget.chat.id);
      if (mounted) {
        _toast(context,
            _contTheirs == true ? 'الاثنين قررتوا تكملون 💞' : 'حلو! ننتظر جوابه.');
      }
    } catch (_) {
      if (mounted) {
        setState(() => _contMine = null);
        _toast(context, 'تعذر الحفظ (يحتاج تحديث السيرفر update_4).');
      }
    }
  }

  /// إنهاء المطابقة بلطف: كلمة وداع اختيارية ثم فك الارتباط
  Future<void> _endMatch() async {
    final bye = await _askFarewell(context);
    if (bye == null || !mounted) return;
    await _sendFarewell(bye);
    try {
      try {
        final files = await _db.storage.from('chat-media').list(path: widget.chat.id);
        if (files.isNotEmpty) {
          await _db.storage
              .from('chat-media')
              .remove(files.map((f) => '${widget.chat.id}/${f.name}').toList());
        }
      } catch (_) {}
      await _db.rpc('unlink_chat');
      await _MsgCache.clearAll();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => PairScreen(me: widget.chat.me)),
          (_) => false);
    } catch (_) {
      if (mounted) _toast(context, 'تعذر فك الارتباط، جرّب مرة ثانية.');
    }
  }

  /// مواعيد اليوم/بكرة، وبنود القوائم المستحقة
  Future<void> _loadToday() async {
    final today = _today();
    final tomorrow = today.add(const Duration(days: 1));
    final out = <String>[];
    try {
      final ev = await _db
          .from('chat_events')
          .select('title,on_date')
          .eq('chat_id', widget.chat.id)
          .gte('on_date', _dayStr(today))
          .lte('on_date', _dayStr(tomorrow))
          .order('on_date')
          .limit(3);
      for (final e in ev) {
        final d = DateTime.tryParse('${e['on_date']}');
        out.add('${d != null && _sameDay(d, today) ? 'اليوم' : 'بكرة'}: ${e['title']}');
      }
    } catch (_) {}
    try {
      final due = await _db
          .from('shared_items')
          .select('body')
          .eq('chat_id', widget.chat.id)
          .eq('done', false)
          .lte('due_on', _dayStr(today))
          .limit(3);
      for (final d in due) {
        out.add('مستحق: ${d['body']}');
      }
    } catch (_) {}
    if (mounted && out.isNotEmpty) setState(() => _todayNotes = out);
  }
}
