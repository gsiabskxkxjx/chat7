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
                  _Avatar(path: _pAvatar, radius: 20, gender: _pGender),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_title(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 17, fontWeight: FontWeight.w600)),
                        if (_status().isNotEmpty)
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
            IconButton(
                onPressed: () => _call(false), icon: const Icon(Icons.call)),
            IconButton(
                onPressed: () => _call(true), icon: const Icon(Icons.videocam)),
            IconButton(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => ThemeSettingsScreen(chatId: widget.chat.id))),
                icon: const Icon(Icons.palette_outlined)),
            IconButton(
                onPressed: _openProfile,
                icon: const Icon(Icons.settings_outlined)),
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
          final msgs = rows
              .map((r) => Msg.fromRow(r, _uid))
              .where((m) => !_hidden.contains(m.id))
              .toList();
          if (msgs.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text('ما في رسائل بعد. ابدأ المحادثة!',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Color(0xAAFFFFFF))),
              ),
            );
          }
          final entries = _withDayHeaders(msgs);
          return ListView.builder(
            controller: _scroll,
            reverse: true,
            padding: const EdgeInsets.all(16),
            itemCount: entries.length,
            itemBuilder: (_, i) {
              final e = entries[i];
              if (e is DateTime) return _DayPill(day: e);
              final m = e as Msg;
              if (m.kind == 'call') return _CallPill(text: m.text);
              return _Bubble(
                key: ValueKey(m.id),
                m: m,
                onLongPress: () => _msgMenu(m),
                t: _t,
              );
            },
          );
        },
      );

  Widget _inputBar(bool typing) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
        child: Glass(
          radius: 28,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          child: _recording ? _recordingRow() : _typingRow(typing),
        ),
      );

  Widget _recordingRow() => Row(children: [
        IconButton(
          onPressed: () => unawaited(_finishRec(false)),
          icon: const Icon(Icons.delete_outline, color: Color(0xFFFF6B60)),
        ),
        const SizedBox(width: 4),
        const Icon(Icons.fiber_manual_record, color: Color(0xFFFF3B30), size: 14),
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
              : const Icon(Icons.add_circle_outline),
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
        IconButton(
          onPressed: typing ? _send : _startRec,
          icon: Icon(typing ? Icons.arrow_upward_rounded : Icons.mic,
              color: typing ? _t.accent : null),
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
      if (pathChanged) _bgUrl = null;
    });
    if (pathChanged && path != null) unawaited(_loadBgUrl(path));
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
          Icon(missed ? Icons.call_missed : Icons.call,
              size: 14,
              color: missed ? const Color(0xFFFF6B60) : Colors.white),
          const SizedBox(width: 6),
          Text(text, style: const TextStyle(fontSize: 12, color: Colors.white)),
        ]),
      ),
    );
  }
}
