part of 'main.dart';

// واجهة المحادثة: الهيدر والرسائل وشريط الإدخال
extension _ChatUi on _ChatState {
  Widget _header() => Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: Glass(
          radius: 22,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(children: [
            Expanded(
              child: InkWell(
                onTap: _partnerInfo,
                child: Row(children: [
                  Stack(clipBehavior: Clip.none, children: [
                    Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [_t.accent, const Color(0xFFFF7EB6)],
                        ),
                      ),
                      child: _Avatar(path: _pAvatar, radius: 19, gender: _pGender),
                    ),
                    if (_online)
                      PositionedDirectional(
                        bottom: 0,
                        end: 0,
                        child: Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xFF34C759),
                            border: Border.all(color: Colors.white, width: 2),
                            boxShadow: const [
                              BoxShadow(color: Color(0x9934C759), blurRadius: 8),
                            ],
                          ),
                        ),
                      ),
                  ]),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Flexible(
                            child: Text(_title(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 17, fontWeight: FontWeight.w600)),
                          ),
                          if (_streak >= 2) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 1),
                              decoration: BoxDecoration(
                                color: const Color(0x33FF9F0A),
                                borderRadius: BorderRadius.circular(10),
                                border:
                                    Border.all(color: const Color(0x66FF9F0A)),
                              ),
                              child: Text('🔥 $_streak',
                                  style: const TextStyle(fontSize: 12)),
                            ),
                          ],
                        ]),
                        if (_isTyping)
                          Row(mainAxisSize: MainAxisSize.min, children: [
                            const Text('يكتب',
                                style: TextStyle(
                                    fontSize: 12, color: Color(0xFF5BE584))),
                            const SizedBox(width: 4),
                            const _TypingDots(),
                          ])
                        else if (_status().isNotEmpty)
                          Text(_status(),
                              style: TextStyle(
                                  fontSize: 12,
                                  color: _online
                                      ? const Color(0xFF5BE584)
                                      : _t.text.withValues(alpha: 0.6))),
                      ],
                    ),
                  ),
                ]),
              ),
            ),
            const SizedBox(width: 4),
            _GlassIcon(
                label: 'مكالمة صوتية',
                onTap: () => _call(false),
                icon: Icons.call_rounded),
            const SizedBox(width: 6),
            _GlassIcon(
                label: 'مكالمة فيديو',
                onTap: () => _call(true),
                icon: Icons.videocam_rounded),
            const SizedBox(width: 6),
            _GlassIcon(
                label: 'مظهر التطبيق',
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => ThemeSettingsScreen(chatId: widget.chat.id))),
                icon: Icons.palette_rounded),
            const SizedBox(width: 6),
            _GlassIcon(
                label: 'الإعدادات',
                onTap: _openProfile,
                icon: Icons.settings_rounded),
          ]),
        ),
      );

  Widget _messages() => StreamBuilder<List<Map<String, dynamic>>>(
        stream: _stream,
        builder: (context, snap) {
          if (snap.hasError) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text('تعذر تحميل الرسائل. تأكد من الإنترنت.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Color(0xAAFFFFFF))),
              ),
            );
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final rows = snap.data!;
          _hasMore = rows.length >= _limit;
          _checkUnread(rows);
          _fxCheck(rows);
          final msgs = rows
              .map((r) => Msg.fromRow(r, _uid))
              .where((m) => !_hidden.contains(m.id))
              .toList();
          if (msgs.isEmpty) return _emptyChat();
          final entries = _withDayHeaders(msgs);
          // أول شي بالمحادثة (أقدم شي): عداد الأيام، يظهر لما نكون وصلنا لأول الرسائل
          if (!_hasMore && _linkedAt != null) entries.add(_SinceMarker(_linkedAt!));
          // تذكير: الرسالة الأخيرة من الطرف الثاني، وما رديت عليها من مدة
          final newest = msgs.isEmpty ? null : msgs.first;
          if (newest != null &&
              !newest.mine &&
              newest.at != null &&
              newest.id != _dismissedRemindId &&
              DateTime.now().difference(newest.at!) >= _remindAfter) {
            entries.insert(0, _RemindMarker(newest.id, newest.at!));
          }
          return ListView.builder(
            controller: _scroll,
            reverse: true,
            padding: const EdgeInsets.all(16),
            itemCount: entries.length,
            itemBuilder: (_, i) {
              final e = entries[i];
              if (e is DateTime) return _DayPill(day: e);
              if (e is _SinceMarker) return _SincePill(since: e.at);
              if (e is _RemindMarker) {
                return _RemindBanner(
                  since: e.since,
                  onClose: () => setState(() => _dismissedRemindId = e.msgId),
                );
              }
              final m = e as Msg;
              if (m.kind == 'call') return _CallPill(text: m.text);
              bool same(Object? o) =>
                  o is Msg &&
                  o.kind != 'call' &&
                  o.mine == m.mine &&
                  o.at != null &&
                  m.at != null &&
                  o.at!.difference(m.at!).inMinutes.abs() < 3;
              return _Bubble(
                key: ValueKey(m.id),
                joinPrev: i + 1 < entries.length && same(entries[i + 1]),
                joinNext: i > 0 && same(entries[i - 1]),
                m: m,
                onLongPress: () => _msgMenu(m),
                t: _t,
                quote: _quoteOf(msgs, m.replyToId),
                reactions: _reactionChips(_reactions, m.id),
              );
            },
          );
        },
      );

  Widget _inputBar(bool typing) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (_replyTo != null) _replyBar(),
          Glass(
            radius: 28,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            child: _recording ? _recordingRow() : _typingRow(typing),
          ),
        ]),
      );

  Widget _replyBar() {
    final r = _replyTo!;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
      decoration: BoxDecoration(
        color: const Color(0x66000000),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(children: [
        Expanded(
          child: Text('رد على: ${_quoteOf([r], r.id) ?? ''}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, color: Colors.white70)),
        ),
        IconButton(
          onPressed: () => setState(() => _replyTo = null),
          icon: const Icon(Icons.close_rounded, size: 18),
        ),
      ]),
    );
  }

  Widget _recordingRow() => Row(children: [
        IconButton(
          onPressed: () => unawaited(_finishRec(false)),
          icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFFF6B60)),
        ),
        const SizedBox(width: 4),
        const Icon(Icons.fiber_manual_record_rounded, color: Color(0xFFFF3B30), size: 14),
        const SizedBox(width: 8),
        Expanded(
          child: Text('جاري التسجيل... ${_mmss(_recSecs * 1000)}',
              style: const TextStyle(fontSize: 15)),
        ),
        IconButton(
          onPressed: () => unawaited(_finishRec(true)),
          icon: const Icon(Icons.arrow_upward_rounded, color: _blue),
        ),
      ]);

  Widget _typingRow(bool typing) => Row(children: [
        IconButton(
          onPressed: _uploading ? null : _attach,
          icon: _uploading
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.add_circle_outline_rounded),
        ),
        Expanded(
          child: TextField(
            controller: _c,
            style: TextStyle(color: _t.text),
            onChanged: (_) {
              setState(() {});
              _notifyTyping();
            },
            onSubmitted: (_) => _send(),
            inputFormatters: [LengthLimitingTextInputFormatter(4000)],
            decoration: const InputDecoration(
                hintText: 'اكتب رسالة', border: InputBorder.none),
          ),
        ),
        if (!typing)
          IconButton(
            onPressed: () => showGamesMenu(context, widget.chat.id),
            icon: Icon(Icons.sports_esports_rounded, color: _t.accent),
          ),
        if (!typing)
          GestureDetector(
            onLongPress: _sendNudge,
            child: IconButton(
              tooltip: 'أفكر فيك (ضغطة مطوّلة: هزّة)',
              onPressed: _thinkOfYou,
              icon: Icon(Icons.favorite_border_rounded, color: _t.accent),
            ),
          ),
        // زر الإرسال: يتحول من المايك للسهم بحركة دوران
        Semantics(
          button: true,
          label: typing ? 'إرسال' : 'تسجيل صوتي',
          child: _Press(
            onTap: typing ? _send : _startRec,
            onLongPress: typing ? _sendWithEffect : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              width: 42,
              height: 42,
              margin: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: typing ? _t.accent : const Color(0x1FFFFFFF),
                border: Border.all(color: const Color(0x4DFFFFFF), width: 0.8),
                boxShadow: typing
                    ? [
                        BoxShadow(
                            color: _t.accent.withValues(alpha: 0.45),
                            blurRadius: 14),
                      ]
                    : null,
              ),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                transitionBuilder: (child, a) => RotationTransition(
                  turns: Tween<double>(begin: 0.75, end: 1).animate(a),
                  child: ScaleTransition(scale: a, child: child),
                ),
                child: Icon(
                  typing ? Icons.arrow_upward_rounded : Icons.mic_rounded,
                  key: ValueKey<bool>(typing),
                  size: 22,
                  color: typing ? Colors.white : null,
                ),
              ),
            ),
          ),
        ),
      ]);
}

// ---------- مظهر المحادثة: الثيم والخلفية ----------

extension _ChatLook on _ChatState {
  void _watchLook() {
    _lookSub = _db
        .from('chats')
        .stream(primaryKey: ['id'])
        .eq('id', widget.chat.id)
        .listen((rows) {
      if (rows.isNotEmpty) _applyLook(rows.first);
    });
  }

  void _applyLook(Map<String, dynamic> r) {
    if (!mounted) return;
    final path = r['bg_path'] as String?;
    final pathChanged = path != _bgPath;
    setState(() {
      _t = chatThemeById((r['theme_id'] as num?)?.toInt() ?? 1);
      _bgKind = (r['bg_kind'] as String?) ?? 'gradient';
      _bgStrength = (r['bg_strength'] as num?)?.toInt() ?? 10;
      _bgPath = path;
      _linkedAt = DateTime.tryParse((r['created_at'] as String?) ?? '')?.toLocal();
      final iAmA = r['user_a'] == _uid;
      _matched = r['matched'] == true;
      _trustMine = (iAmA ? r['trust_a'] : r['trust_b']) == true;
      _trustTheirs = (iAmA ? r['trust_b'] : r['trust_a']) == true;
      if (pathChanged) _bgUrl = null;
    });
    if (pathChanged && path != null) unawaited(_loadBgUrl(path));
    if (_linkedAt != null) unawaited(_checkMilestone());
  }

  Future<void> _loadBgUrl(String path) async {
    final url = await MediaUrls.get('chat-bg', path);
    if (!mounted || _bgPath != path) return;
    setState(() => _bgUrl = url);
  }

  Widget _chatBackground() {
    final t = _t;
    final gradient = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [t.top, t.bottom],
        ),
      ),
    );
    final url = _bgUrl;
    if (_bgKind == 'gradient' || url == null) return gradient;
    final img = Image.network(
      url,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      errorBuilder: (_, __, ___) => gradient,
    );
    if (_bgKind == 'plain') return img;
    final s = _bgStrength.toDouble();
    final blurred = ImageFiltered(
      imageFilter: ImageFilter.blur(sigmaX: s, sigmaY: s),
      child: img,
    );
    if (_bgKind == 'blur') return blurred;
    // زجاجية: ضبابية + طبقة شفافة بلون الثيم
    return Stack(fit: StackFit.expand, children: [
      blurred,
      ColoredBox(color: t.top.withValues(alpha: 0.45)),
    ]);
  }
}

// ---------- فواصل الأيام بين الرسائل ----------

const _months = [
  'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
  'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر',
];

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// يضيف فاصل يوم فوق أول رسالة في كل يوم.
/// القائمة معكوسة (الأحدث أول)، فالفاصل يتحط بعد الرسالة بالقائمة = فوقها بالشاشة.
List<Object> _withDayHeaders(List<Msg> msgs) {
  final out = <Object>[];
  for (var i = 0; i < msgs.length; i++) {
    out.add(msgs[i]);
    final d = msgs[i].at;
    if (d == null) continue;
    final next = i + 1 < msgs.length ? msgs[i + 1].at : null;
    if (next == null || !_sameDay(d, next)) out.add(d);
  }
  return out;
}

String _dayLabel(DateTime d) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(d.year, d.month, d.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return 'اليوم';
  if (diff == 1) return 'أمس';
  return '${d.day} ${_months[d.month - 1]} ${d.year}';
}

class _DayPill extends StatelessWidget {
  const _DayPill({required this.day});
  final DateTime day;

  @override
  Widget build(BuildContext context) => Center(
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 10),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0x66000000),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(_dayLabel(day),
              style: const TextStyle(fontSize: 12, color: Colors.white)),
        ),
      );
}

// ---------- سطر المكالمة بالمحادثة ----------

class _CallPill extends StatelessWidget {
  const _CallPill({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final missed = text.contains('فائتة');
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: const Color(0x66000000),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(missed ? Icons.call_missed_rounded : Icons.call_rounded,
              size: 14,
              color: missed ? const Color(0xFFFF6B60) : Colors.white),
          const SizedBox(width: 6),
          Text(text, style: const TextStyle(fontSize: 12, color: Colors.white)),
        ]),
      ),
    );
  }
}

// ---------- زر "أفكر فيك" ----------

DateTime _lastThinkSent = DateTime.fromMillisecondsSinceEpoch(0);

extension _ChatThink on _ChatState {
  Future<void> _thinkOfYou() async {
    final now = DateTime.now();
    if (now.difference(_lastThinkSent) < const Duration(seconds: 3)) return;
    _lastThinkSent = now;
    unawaited(HapticFeedback.lightImpact());
    try {
      await _db.from('messages').insert({
        'chat_id': widget.chat.id,
        'kind': 'think',
        'body': '❤️ أفكر فيك',
      });
    } catch (_) {
      if (mounted) _toast(context, 'تعذر الإرسال.');
    }
  }
}

// ---------- عداد الأيام: أنتم مرتبطين من ... ----------

class _SinceMarker {
  const _SinceMarker(this.at);
  final DateTime at;
}

class _SincePill extends StatelessWidget {
  const _SincePill({required this.since});
  final DateTime since;

  @override
  Widget build(BuildContext context) {
    final days = DateTime.now().difference(since).inDays;
    final text = days <= 0
        ? 'بدأتوا اليوم'
        : 'أنتم مرتبطين من ${_countAr(days, 'يوم', 'يومين', 'أيام', 'يوم')}';
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0x66000000),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.favorite_rounded, size: 14, color: Color(0xFFFF6B9D)),
          const SizedBox(width: 6),
          Text(text, style: const TextStyle(fontSize: 12, color: Colors.white)),
        ]),
      ),
    );
  }
}

// ---------- الرد على رسالة: نص الأصلية للاقتباس ----------

String? _quoteOf(List<Msg> msgs, int? id) {
  if (id == null) return null;
  final found = msgs.where((x) => x.id == id).toList();
  if (found.isEmpty) return 'رسالة';
  final x = found.first;
  switch (x.kind) {
    case 'image':
      return '📷 صورة';
    case 'video':
      return '🎬 فيديو';
    case 'audio':
      return '🎤 رسالة صوتية';
    default:
      return x.text;
  }
}

// ---------- تفاعلات الإيموجي ----------

const _reactEmojis = ['👍', '😂', '😮', '😢', '🙏', '🔥'];

/// يحوّل التفاعلات لقائمة عرض: إيموجي، ومعه العدد إذا أكثر من واحد
List<String>? _reactionChips(Map<int, Map<String, String>> all, int id) {
  final byUser = all[id];
  if (byUser == null || byUser.isEmpty) return null;
  final counts = <String, int>{};
  for (final e in byUser.values) {
    counts[e] = (counts[e] ?? 0) + 1;
  }
  return [
    for (final e in counts.entries) e.value > 1 ? '${e.key} ${e.value}' : e.key
  ];
}

extension _ChatReact on _ChatState {
  /// نفس الإيموجي مرة ثانية = يلغي، وإيموجي ثاني = يغيّر
  Future<void> _react(int msgId, String emoji) async {
    final mine = _reactions[msgId]?[_uid];
    try {
      if (mine == emoji) {
        await _db
            .from('reactions')
            .delete()
            .eq('message_id', msgId)
            .eq('user_id', _uid);
      } else {
        await _db.from('reactions').upsert({
          'message_id': msgId,
          'user_id': _uid,
          'emoji': emoji,
        });
      }
    } catch (_) {
      if (mounted) _toast(context, 'تعذر حفظ التفاعل.');
    }
  }
}

// ---------- شريط انقطاع الإنترنت ----------

extension _ChatOffline on _ChatState {
  Widget _offlineBar() => Container(
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xCCB45309),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.wifi_off_rounded, size: 16, color: Colors.white),
          SizedBox(width: 8),
          Flexible(
            child: Text('لا يوجد اتصال، ننتظر الشبكة...',
                style: TextStyle(fontSize: 13, color: Colors.white)),
          ),
        ]),
      );
}

// ---------- تنبيه: ما رديت على الطرف الثاني ----------

const _remindAfter = Duration(hours: 2);

class _RemindMarker {
  const _RemindMarker(this.msgId, this.since);
  final int msgId;
  final DateTime since;
}

class _RemindBanner extends StatelessWidget {
  const _RemindBanner({required this.since, required this.onClose});
  final DateTime since;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final h = DateTime.now().difference(since).inHours;
    final text =
        'ما رديت على الطرف الثاني من ${_countAr(h, 'ساعة', 'ساعتين', 'ساعات', 'ساعة')}';
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
        decoration: BoxDecoration(
          color: const Color(0x66B45309),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.schedule_rounded, size: 14, color: Colors.white),
          const SizedBox(width: 6),
          Text(text, style: const TextStyle(fontSize: 12, color: Colors.white)),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: onClose,
            icon: const Icon(Icons.close_rounded, size: 16, color: Colors.white),
          ),
        ]),
      ),
    );
  }
}

// ---------- مطابقة جديدة: شريط "أثق فيه" ----------

extension _ChatTrust on _ChatState {
  Widget _trustBar() => Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: Glass(
          radius: 20,
          padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
          tint: _t.accent,
          child: Row(children: [
            const Icon(Icons.shield_rounded, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _trustMine
                    ? 'بانتظار الطرف الثاني يضغط «أثق فيه» حتى تنفتح الصور والمكالمات.'
                    : 'مطابقة جديدة: الصور والمكالمات تنفتح لما الطرفين يضغطون «أثق فيه».',
                style: const TextStyle(fontSize: 13),
              ),
            ),
            if (!_trustMine) ...[
              const SizedBox(width: 8),
              _Press(
                onTap: _trust,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  decoration: BoxDecoration(
                    color: _t.accent,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0x66FFFFFF)),
                  ),
                  child: const Text('أثق فيه',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ]),
        ),
      );

  Future<void> _trust() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تثق بهذا الشخص؟'),
        content: const Text(
            'لما الطرفين يوافقون، تقدرون ترسلون صور وفيديو ورسائل صوتية وتتصلون. ما تقدر تلغي الموافقة، بس تقدر تحظره بأي وقت من الإعدادات.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('مو الحين')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('أثق فيه')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      final rows = await _db
          .from('chats')
          .select('user_a')
          .eq('id', widget.chat.id)
          .limit(1);
      final iAmA = rows.isNotEmpty && rows.first['user_a'] == _uid;
      await _db
          .from('chats')
          .update({iAmA ? 'trust_a' : 'trust_b': true}).eq('id', widget.chat.id);
      if (mounted) setState(() => _trustMine = true);
    } catch (_) {
      if (mounted) _toast(context, 'تعذر الحفظ، جرّب مرة ثانية.');
    }
  }

  /// يرجع true إذا الوسائط مقفلة (ويعرض السبب)
  bool _blockedByTrust() {
    if (!_mediaLocked) return false;
    _toast(context, 'الصور والمكالمات تنفتح لما الطرفين يضغطون «أثق فيه».');
    return true;
  }
}

// ---------- محادثة فاضية: اقتراحات بدل مساحة فاضية ----------

extension _ChatEmpty on _ChatState {
  Widget _emptyChat() {
    Widget chip(String label, VoidCallback onTap) => _Press(
          onTap: onTap,
          scale: 0.95,
          child: Glass(
            radius: 18,
            shadow: false,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            child: Text(label, style: const TextStyle(fontSize: 15)),
          ),
        );
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('🌱', style: TextStyle(fontSize: 46)),
          const SizedBox(height: 10),
          const Text('بداية حلوة',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text('اختر شي تبدأ فيه',
              style: TextStyle(color: _t.text.withValues(alpha: 0.7))),
          const SizedBox(height: 18),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 10,
            runSpacing: 10,
            children: [
              chip('قل مرحبا 👋', () {
                _c.text = 'مرحبا 👋';
                unawaited(_send());
              }),
              chip('أفكر فيك ❤️', () => unawaited(_thinkOfYou())),
              chip('سؤال اليوم 💬', () => unawaited(_openDaily())),
              chip('العبوا لعبة 🎮', () => showGamesMenu(context, widget.chat.id)),
            ],
          ),
        ]),
      ),
    );
  }
}

// ---------- "يكتب" بنقاط متموجة ----------

class _TypingDots extends StatefulWidget {
  const _TypingDots();

  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 900))
    ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (_, __) => Row(mainAxisSize: MainAxisSize.min, children: [
          for (var i = 0; i < 3; i++)
            Transform.translate(
              offset: Offset(
                  0, -3 * math.max(0, math.sin((_c.value - i * 0.18) * 2 * math.pi))),
              child: Container(
                width: 5,
                height: 5,
                margin: const EdgeInsets.symmetric(horizontal: 1.5),
                decoration: const BoxDecoration(
                    shape: BoxShape.circle, color: Color(0xFF5BE584)),
              ),
            ),
        ]),
      );
}

// ---------- هزّة: تهزّ جوال الطرف الثاني ----------

DateTime _lastNudge = DateTime.fromMillisecondsSinceEpoch(0);

extension _ChatNudge on _ChatState {
  bool get _isTyping =>
      DateTime.now().difference(_typingSeen) < const Duration(seconds: 4);

  Future<void> _sendNudge() async {
    final now = DateTime.now();
    if (now.difference(_lastNudge) < const Duration(seconds: 5)) {
      _toast(context, 'استنى شوي قبل الهزّة الثانية.');
      return;
    }
    _lastNudge = now;
    unawaited(HapticFeedback.heavyImpact());
    final ch = _typeCh;
    if (ch == null) return;
    try {
      await ch.sendBroadcastMessage(event: 'nudge', payload: {'uid': _uid});
      if (mounted) _toast(context, 'أرسلت هزّة 👋');
    } catch (_) {
      if (mounted) _toast(context, 'تعذر الإرسال.');
    }
  }

  void _onNudge(Map<String, dynamic> payload) {
    final inner = payload['payload'];
    final uid = inner is Map ? inner['uid'] : payload['uid'];
    if (uid == _uid || !mounted) return;
    setState(() => _nudgeN++);
    unawaited(() async {
      for (var i = 0; i < 3; i++) {
        await HapticFeedback.heavyImpact();
        await Future<void>.delayed(const Duration(milliseconds: 140));
      }
    }());
    _toast(context, 'الطرف الثاني هزّك 👋');
  }

  /// يهزّ الشاشة لما توصل هزّة
  Widget _shake(Widget child) => TweenAnimationBuilder<double>(
        key: ValueKey<int>(_nudgeN),
        tween: Tween<double>(begin: _nudgeN == 0 ? 1 : 0, end: 1),
        duration: const Duration(milliseconds: 650),
        builder: (_, v, c) => Transform.translate(
          offset: Offset(math.sin(v * math.pi * 8) * 12 * (1 - v), 0),
          child: c,
        ),
        child: child,
      );
}

