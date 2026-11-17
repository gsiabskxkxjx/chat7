part of 'main.dart';

// ---------- إضافات: عجلة القرار، إحصائياتنا، المفضلة، عدّ تنازلي، طلب ارتباط بالاسم ----------

Future<void> _sendText(String chatId, String text) =>
    _db.from('messages').insert({'chat_id': chatId, 'body': text});

// ========== عجلة القرار ==========

class DecisionWheelScreen extends StatefulWidget {
  const DecisionWheelScreen({super.key, required this.chatId});
  final String chatId;

  @override
  State<DecisionWheelScreen> createState() => _WheelState();
}

class _WheelState extends State<DecisionWheelScreen>
    with SingleTickerProviderStateMixin {
  final _c = TextEditingController(text: 'مطعم\nسينما\nكوفي\nتمشية');
  late final AnimationController _spin = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 3200));
  double _from = 0, _to = 0;
  String? _result;

  List<String> get _opts => _c.text
      .split('\n')
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .take(8)
      .toList();

  @override
  void dispose() {
    _c.dispose();
    _spin.dispose();
    super.dispose();
  }

  void _go() {
    final o = _opts;
    if (o.length < 2) {
      _toast(context, 'اكتب خيارين على الأقل، كل خيار بسطر.');
      return;
    }
    final pick = Random().nextInt(o.length);
    final seg = 2 * math.pi / o.length;
    // المؤشر فوق: نوقف بحيث نص الخيار المختار يكون تحت المؤشر
    final target = 2 * math.pi * 5 + (2 * math.pi - (pick + 0.5) * seg);
    setState(() {
      _from = _to % (2 * math.pi);
      _to = target;
      _result = null;
    });
    unawaited(HapticFeedback.mediumImpact());
    _spin
      ..reset()
      ..forward().whenComplete(() {
        if (!mounted) return;
        setState(() => _result = o[pick]);
        unawaited(HapticFeedback.heavyImpact());
      });
  }

  @override
  Widget build(BuildContext context) {
    final o = _opts;
    return Scaffold(
      appBar: AppBar(
          title: const Text('عجلة القرار'),
          backgroundColor: Colors.transparent),
      extendBodyBehindAppBar: true,
      body: Backdrop(
        child: SafeArea(
          child: ListView(padding: const EdgeInsets.all(20), children: [
            Center(
              child: SizedBox(
                width: 280,
                height: 300,
                child: Stack(alignment: Alignment.topCenter, children: [
                  Positioned(
                    top: 18,
                    child: AnimatedBuilder(
                      animation: _spin,
                      builder: (_, __) {
                        final t = Curves.easeOutCubic.transform(_spin.value);
                        return Transform.rotate(
                          angle: _from + (_to - _from) * t,
                          child: CustomPaint(
                            size: const Size(270, 270),
                            painter: _WheelPainter(o),
                          ),
                        );
                      },
                    ),
                  ),
                  const Icon(Icons.arrow_drop_down_rounded,
                      size: 52, color: Colors.white),
                ]),
              ),
            ),
            const SizedBox(height: _Sp.sm),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: Text(
                _result == null ? ' ' : 'العجلة اختارت: $_result',
                key: ValueKey<String?>(_result),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(height: _Sp.lg),
            _Btn(label: 'دوّر', onTap: _go),
            if (_result != null) ...[
              const SizedBox(height: 10),
              TextButton(
                onPressed: () async {
                  try {
                    await _sendText(widget.chatId, '🎡 العجلة اختارت: $_result');
                    if (mounted) Navigator.pop(context);
                  } catch (_) {
                    if (mounted) _toast(context, 'تعذر الإرسال.');
                  }
                },
                child: const Text('أرسل النتيجة بالمحادثة'),
              ),
            ],
            const SizedBox(height: _Sp.lg),
            Glass(
              radius: 20,
              padding: const EdgeInsets.all(_Sp.md),
              child: TextField(
                controller: _c,
                minLines: 3,
                maxLines: 8,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'الخيارات (كل خيار بسطر، لين 8)',
                  border: InputBorder.none,
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _WheelPainter extends CustomPainter {
  const _WheelPainter(this.opts);
  final List<String> opts;

  static const _colors = [
    Color(0xFF0A84FF), Color(0xFFFF5FA2), Color(0xFF30D5C8), Color(0xFFFF9F0A),
    Color(0xFFBF5AF2), Color(0xFF34C759), Color(0xFFFF6B60), Color(0xFF5E5CE6),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final n = math.max(opts.length, 2);
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    final seg = 2 * math.pi / n;
    for (var i = 0; i < n; i++) {
      final p = Paint()..color = _colors[i % _colors.length].withValues(alpha: 0.85);
      canvas.drawArc(Rect.fromCircle(center: c, radius: r), -math.pi / 2 + i * seg,
          seg, true, p);
      if (i < opts.length) {
        final mid = -math.pi / 2 + (i + 0.5) * seg;
        canvas.save();
        canvas.translate(c.dx, c.dy);
        canvas.rotate(mid);
        final tp = TextPainter(
          text: TextSpan(
              text: opts[i].length > 12 ? '${opts[i].substring(0, 12)}…' : opts[i],
              style: const TextStyle(
                  color: Colors.white, fontSize: _Fs.body, fontWeight: FontWeight.w700)),
          textDirection: TextDirection.rtl,
        )..layout(maxWidth: r * 0.7);
        tp.paint(canvas, Offset(r * 0.25, -tp.height / 2));
        canvas.restore();
      }
    }
    canvas.drawCircle(
        c,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = const Color(0xCCFFFFFF));
    canvas.drawCircle(c, 16, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_WheelPainter old) => old.opts.join() != opts.join();
}

// ========== إحصائياتنا ==========

class StatsScreen extends StatelessWidget {
  const StatsScreen({super.key, required this.chatId});
  final String chatId;

  Widget _tile(String emoji, String label, Object? value) => Glass(
        radius: 22,
        shadow: false,
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(emoji, style: const TextStyle(fontSize: 22)),
          const SizedBox(height: 6),
          Text('${value ?? 0}',
              style: const TextStyle(fontSize: _Fs.big, fontWeight: FontWeight.w700)),
          Text(label,
              style: const TextStyle(fontSize: _Fs.meta, color: Color(0xCCFFFFFF))),
        ]),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
            title: const Text('إحصائياتنا'),
            backgroundColor: Colors.transparent),
        extendBodyBehindAppBar: true,
        body: Backdrop(
          child: SafeArea(
            child: FutureBuilder<dynamic>(
              future: _db.rpc('chat_stats', params: {'p_chat': chatId}),
              builder: (_, snap) {
                if (snap.hasError) {
                  return const Center(
                      child: Text('الإحصائيات غير متوفرة بالسيرفر بعد.'));
                }
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final s = Map<String, dynamic>.from(snap.data as Map);
                return GridView.count(
                  padding: const EdgeInsets.all(_Sp.lg),
                  crossAxisCount: 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 1.35,
                  children: [
                    _tile('💬', 'رسالة بيناتكم', s['total']),
                    _tile('📅', 'يوم تكلمتوا فيه', s['days']),
                    _tile('🙋', 'رسائلك', s['mine']),
                    _tile('💌', 'رسائل الطرف الثاني', s['theirs']),
                    _tile('📷', 'صورة', s['photos']),
                    _tile('🎙️', 'رسالة صوتية', s['voice']),
                    _tile('📞', 'مكالمة', s['calls']),
                    _tile('❤️', 'أفكر فيك', s['hearts']),
                  ],
                );
              },
            ),
          ),
        ),
      );
}

// ========== الرسائل المفضلة ==========

// ========== عدّ تنازلي لموعد قادم ==========

Future<void> _setCountdown(BuildContext context, String chatId) async {
  final title = TextEditingController();
  DateTime? at;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => AlertDialog(
        title: const Text('عدّ تنازلي'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: title,
            maxLength: 40,
            decoration: const InputDecoration(labelText: 'على شنو؟ (مثلاً: لقاءنا)'),
          ),
          const SizedBox(height: _Sp.sm),
          OutlinedButton.icon(
            onPressed: () async {
              final now = DateTime.now();
              final d = await showDatePicker(
                context: ctx,
                initialDate: now.add(const Duration(days: 7)),
                firstDate: now,
                lastDate: DateTime(now.year + 3),
              );
              if (d != null) set(() => at = d);
            },
            icon: const Icon(Icons.event_rounded),
            label: Text(at == null ? 'اختر التاريخ' : '${at!.day}/${at!.month}/${at!.year}'),
          ),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child: const Text('إلغاء')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('حذف العدّ')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('حفظ')),
        ],
      ),
    ),
  );
  final t = title.text.trim();
  title.dispose();
  if (ok == null) return;
  try {
    if (ok) {
      if (t.isEmpty || at == null) {
        if (context.mounted) _toast(context, 'اكتب العنوان واختر التاريخ.');
        return;
      }
      await _db.from('chats').update({
        'countdown_title': t,
        'countdown_at': _dayStr(at!),
      }).eq('id', chatId);
    } else {
      await _db.from('chats').update(
          {'countdown_title': null, 'countdown_at': null}).eq('id', chatId);
    }
  } catch (_) {
    if (context.mounted) _toast(context, 'تعذر الحفظ.');
  }
}

// ========== طلب ارتباط باسم المستخدم ==========

class _RequestsPanel extends StatefulWidget {
  const _RequestsPanel({required this.onPaired});
  final Future<void> Function() onPaired;

  @override
  State<_RequestsPanel> createState() => _RequestsPanelState();
}

class _RequestsPanelState extends State<_RequestsPanel> {
  final _u = TextEditingController();
  Timer? _t;
  List<Map<String, dynamic>> _in = [];
  List<Map<String, dynamic>> _out = [];
  bool _busy = false;
  bool _available = true;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    _t = Timer.periodic(const Duration(seconds: 5), (_) => _load());
  }

  @override
  void dispose() {
    _t?.cancel();
    _u.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final a = await _db.rpc('pair_inbox');
      final b = await _db.rpc('pair_outbox');
      if (!mounted) return;
      setState(() {
        _in = (a as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _out = (b as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      });
    } on PostgrestException catch (e) {
      if (e.message.contains('function') && mounted) {
        setState(() => _available = false);
        _t?.cancel();
      }
    } catch (_) {}
  }

  Future<void> _send() async {
    final u = _u.text.trim();
    if (u.length < 3 || _busy) return;
    setState(() => _busy = true);
    try {
      await _db.rpc('pair_request', params: {'p_username': u});
      _u.clear();
      if (mounted) _toast(context, 'انرسل الطلب. ينتظر موافقته.');
      await _load();
    } on PostgrestException catch (e) {
      if (!mounted) return;
      final m = e.message;
      _toast(
          context,
          m.contains('no_user')
              ? 'ما لقينا هذا الاسم.'
              : m.contains('self')
                  ? 'هذا اسمك أنت.'
                  : m.contains('unavailable')
                      ? 'هذا الشخص مرتبط أو مو متاح.'
                      : m.contains('daily_limit')
                          ? 'وصلت حد الطلبات اليوم.'
                          : m.contains('already_paired')
                              ? 'أنت مرتبط أصلاً.'
                              : 'تعذر إرسال الطلب.');
    } catch (_) {
      if (mounted) _toast(context, 'تعذر الاتصال بالسيرفر.');
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _answer(int id, bool ok) async {
    try {
      await _db.rpc('pair_respond', params: {'p_id': id, 'p_ok': ok});
      if (ok) {
        await widget.onPaired();
      } else {
        await _load();
      }
    } catch (_) {
      if (mounted) _toast(context, 'تعذر، جرّب مرة ثانية.');
      await _load();
    }
  }

  Future<void> _cancel(int id) async {
    try {
      await _db.rpc('pair_cancel', params: {'p_id': id});
    } catch (_) {}
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (!_available) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final r in _in)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Glass(
            radius: 20,
            tint: const Color(0xFFFF5FA2),
            padding: const EdgeInsets.all(_Sp.md),
            child: Row(children: [
              _Avatar(
                  path: r['avatar_path'] as String?,
                  radius: 22,
                  gender: r['gender'] as String?),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                    '${r['display_name'] ?? '@${r['username']}'} يبي يرتبط معك',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
              _GlassIcon(
                  label: 'رفض',
                  icon: Icons.close_rounded,
                  size: 36,
                  onTap: () => _answer((r['id'] as num).toInt(), false)),
              const SizedBox(width: 6),
              _GlassIcon(
                  label: 'قبول',
                  icon: Icons.check_rounded,
                  size: 36,
                  tint: const Color(0xFF34C759),
                  onTap: () => _answer((r['id'] as num).toInt(), true)),
            ]),
          ),
        ),
      Row(children: [
        Expanded(
          child: TextField(
            controller: _u,
            textDirection: TextDirection.ltr,
            autocorrect: false,
            onSubmitted: (_) => _send(),
            decoration: InputDecoration(
              labelText: 'اطلب باسم المستخدم',
              prefixIcon: const Icon(Icons.alternate_email_rounded),
              filled: true,
              fillColor: const Color(0x1AFFFFFF),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: _edge),
              ),
            ),
          ),
        ),
        const SizedBox(width: _Sp.sm),
        _GlassIcon(
            label: 'إرسال الطلب',
            icon: Icons.send_rounded,
            size: 48,
            tint: _blue,
            onTap: _busy ? null : _send),
      ]),
      for (final r in _out)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(children: [
            const Icon(Icons.hourglass_top_rounded, size: 18),
            const SizedBox(width: 6),
            Expanded(
                child: Text('بانتظار موافقة @${r['username']}',
                    style: const TextStyle(fontSize: _Fs.meta, color: Color(0xCCFFFFFF)))),
            TextButton(
                onPressed: () => _cancel((r['id'] as num).toInt()),
                child: const Text('إلغاء')),
          ]),
        ),
    ]);
  }
}

// ========== ربطها بشاشة المحادثة ==========

extension _ChatExtras on _ChatState {
  Future<void> _loadStars() async {
    try {
      final rows = await _db.from('message_stars').select('message_id');
      if (!mounted) return;
      setState(() => _stars = {
            for (final r in rows) (r['message_id'] as num).toInt(),
          });
    } catch (_) {}
  }

  Future<void> _toggleStar(Msg m) async {
    final on = _stars.contains(m.id);
    setState(() => on ? _stars.remove(m.id) : _stars.add(m.id));
    try {
      if (on) {
        await _db.from('message_stars').delete().eq('message_id', m.id);
      } else {
        await _db.from('message_stars').insert({'message_id': m.id});
        if (mounted) _toast(context, 'انضافت للمفضلة ⭐');
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => on ? _stars.add(m.id) : _stars.remove(m.id));
      _toast(context, 'المفضلة غير متوفرة بالسيرفر بعد.');
    }
  }

  bool _canEdit(Msg m) =>
      m.mine &&
      m.kind == 'text' &&
      m.at != null &&
      DateTime.now().difference(m.at!) < const Duration(minutes: 15);

  Future<void> _editMsg(Msg m) async {
    final c = TextEditingController(text: m.text);
    final t = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تعديل الرسالة'),
        content: TextField(controller: c, maxLines: 5, minLines: 1, autofocus: true),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, c.text.trim()),
              child: const Text('حفظ')),
        ],
      ),
    );
    c.dispose();
    if (t == null || t.isEmpty || t == m.text || !mounted) return;
    try {
      await _db.rpc('edit_message', params: {'p_id': m.id, 'p_body': t});
    } on PostgrestException catch (e) {
      if (mounted) {
        _toast(context,
            e.message.contains('too_late') ? 'فات وقت التعديل (15 دقيقة).' : 'تعذر التعديل.');
      }
    } catch (_) {
      if (mounted) _toast(context, 'تعذر التعديل.');
    }
  }

  Future<void> _loadBirthday() async {
    try {
      final r = await _db.rpc('partner_birthday', params: {'p_chat': widget.chat.id});
      if (r == null || !mounted) return;
      final m = Map<String, dynamic>.from(r as Map);
      setState(() => _bday = m);
      if (m['today'] == true) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _showEffect(context, 'confetti');
        });
      }
    } catch (_) {}
  }

  /// مثل هذا اليوم: رسالة من قبل سنة أو شهر
  Future<void> _loadMemory() async {
    for (final back in const [365, 30]) {
      final mid = DateTime.now().subtract(Duration(days: back));
      try {
        final rows = await _db
            .from('messages')
            .select('body,kind,created_at')
            .eq('chat_id', widget.chat.id)
            .eq('kind', 'text')
            .gte('created_at',
                mid.subtract(const Duration(hours: 12)).toUtc().toIso8601String())
            .lte('created_at', mid.add(const Duration(hours: 12)).toUtc().toIso8601String())
            .limit(1);
        if (rows.isNotEmpty && mounted) {
          setState(() => _memory = {
                'label': back == 365 ? 'قبل سنة' : 'قبل شهر',
                'body': rows.first['body'],
              });
          return;
        }
      } catch (_) {
        return;
      }
    }
  }

  List<Widget> _extraBars() {
    final out = <Widget>[];
    Widget bar(String emoji, String text, VoidCallback onClose) => Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Glass(
            radius: 20,
            shadow: false,
            padding: const EdgeInsets.fromLTRB(14, 8, 4, 8),
            child: Row(children: [
              Text(emoji, style: const TextStyle(fontSize: _Fs.display)),
              const SizedBox(width: 10),
              Expanded(
                  child: Text(text,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: _Fs.meta))),
              IconButton(
                  tooltip: 'إغلاق',
                  onPressed: onClose,
                  icon: const Icon(Icons.close_rounded, size: 18)),
            ]),
          ),
        );
    final cd = _cdAt;
    if (cd != null && _cdTitle != null) {
      final days = DateTime(cd.year, cd.month, cd.day).difference(_today()).inDays;
      if (days >= 0) {
        out.add(bar('⏳', days == 0 ? 'اليوم: $_cdTitle 🎉' : 'باقي $days يوم: $_cdTitle',
            () => _setCountdown(context, widget.chat.id)));
      }
    }
    final b = _bday;
    if (b != null && !_bdayDismissed) {
      final name = _pName ?? widget.chat.partner;
      if (b['today'] == true) {
        out.add(bar('🎂', 'اليوم عيد ميلاد $name! هنّيه',
            () => setState(() => _bdayDismissed = true)));
      } else if (b['soon'] == true) {
        out.add(bar('🎁', 'عيد ميلاد $name بعد ${b['in_days']} يوم',
            () => setState(() => _bdayDismissed = true)));
      }
    }
    final season = _season();
    if (season != null && !_seasonDismissed) {
      out.add(bar(season.$1, season.$2, () => setState(() => _seasonDismissed = true)));
    }
    final ann = _annivYears;
    if (ann != null) {
      out.add(bar('🎉', 'اليوم ذكرى أول رسالة بينكم (${ann == 1 ? 'سنة' : '$ann سنين'})!',
          () => setState(() => _annivYears = null)));
    }
    if (_todayNotes.isNotEmpty && !_todayDismissed) {
      out.add(bar('📅', _todayNotes.join(' · '),
          () => setState(() => _todayDismissed = true)));
    }
    if (!_pushDismissed && Push.status.startsWith('مرفوضة')) {
      out.add(bar('🔕', 'الإشعارات مطفية، ما راح تعرف لما يرسل لك. فعّلها من إعدادات الجوال ثم التطبيقات ثم بيناتنا.',
          () => setState(() => _pushDismissed = true)));
    }
    final mem = _memory;
    if (mem != null && !_memoryDismissed) {
      out.add(bar('🕰️', 'مثل هذا اليوم ${mem['label']}: «${mem['body']}»',
          () => setState(() => _memoryDismissed = true)));
    }
    return out;
  }
}

// ========== الاهتمامات (لين 3) ==========

const _allInterests = [
  'سفر', 'رياضة', 'قراءة', 'أفلام', 'موسيقى', 'طبخ', 'ألعاب', 'تصوير',
  'فن', 'تقنية', 'طبيعة', 'قهوة', 'أزياء', 'لغات', 'حيوانات', 'كتابة',
];

class _InterestsPicker extends StatelessWidget {
  const _InterestsPicker({required this.selected, required this.onChanged});
  final List<String> selected;
  final ValueChanged<List<String>> onChanged;

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final i in _allInterests)
            FilterChip(
              label: Text(i),
              selected: selected.contains(i),
              showCheckmark: false,
              selectedColor: const Color(0x66FF5FA2),
              backgroundColor: const Color(0x1AFFFFFF),
              side: BorderSide(
                  color: selected.contains(i)
                      ? const Color(0xFFFF7EB6)
                      : const Color(0x33FFFFFF)),
              shape: const StadiumBorder(),
              onSelected: (on) {
                final next = [...selected];
                if (on) {
                  if (next.length >= 3) {
                    _toast(context, 'تقدر تختار 3 بس.');
                    return;
                  }
                  next.add(i);
                } else {
                  next.remove(i);
                }
                onChanged(next);
              },
            ),
        ],
      );
}

/// نافذة تعديل الاهتمامات (من الملف الشخصي)
Future<void> _editInterests(BuildContext context) async {
  final uid = _db.auth.currentUser?.id;
  if (uid == null) return;
  var cur = <String>[];
  try {
    final r = await _db.from('profiles').select('interests').eq('id', uid).maybeSingle();
    cur = ((r?['interests'] as List?) ?? const []).map((e) => '$e').toList();
  } catch (_) {
    if (context.mounted) _toast(context, 'الاهتمامات غير متوفرة بالسيرفر بعد.');
    return;
  }
  if (!context.mounted) return;
  final res = await showDialog<List<String>>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => AlertDialog(
        title: const Text('اهتماماتي (لين 3)'),
        content: SingleChildScrollView(
          child: _InterestsPicker(
              selected: cur, onChanged: (v) => set(() => cur = v)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, cur), child: const Text('حفظ')),
        ],
      ),
    ),
  );
  if (res == null) return;
  try {
    await _db.from('profiles').update({'interests': res}).eq('id', uid);
    if (context.mounted) _toast(context, 'انحفظت اهتماماتك.');
  } catch (_) {
    if (context.mounted) _toast(context, 'تعذر الحفظ.');
  }
}

/// تاريخ بداية العلاقة (لعدّاد الأيام والاحتفالات)
Future<void> _setStartDate(BuildContext context, String chatId) async {
  final now = DateTime.now();
  final d = await showDatePicker(
    context: context,
    initialDate: now,
    firstDate: DateTime(1950),
    lastDate: now,
    helpText: 'من متى بدأت قصتكم؟',
  );
  if (d == null) return;
  try {
    await _db.from('chats').update({'started_on': _dayStr(d)}).eq('id', chatId);
    if (context.mounted) _toast(context, 'انحفظ تاريخ البداية.');
  } catch (_) {
    if (context.mounted) _toast(context, 'تاريخ البداية غير متوفر بالسيرفر بعد.');
  }
}
