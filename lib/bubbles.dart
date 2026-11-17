part of 'main.dart';

// ---------- نموذج الرسالة وفقاعتها ----------

class Msg {
  const Msg({
    required this.id,
    required this.text,
    required this.mine,
    required this.kind,
    required this.read,
    this.mediaPath,
    this.durationMs = 0,
    this.at,
    this.replyToId,
    this.edited = false,
    this.readAt,
    this.replyQuote,
    this.alt,
    this.thumbPath,
  });

  final int id;
  final String text;
  final bool mine;
  final String kind; // text | image | video | audio
  final bool read;
  final String? mediaPath;
  final int durationMs;
  final DateTime? at;
  final int? replyToId; // رقم الرسالة اللي هذي رد عليها
  final bool edited; // انعدلت بعد الإرسال
  final DateTime? readAt; // متى قراها الطرف الثاني
  final String? replyQuote; // نص الأصلية وقت الرد (يبقى لو انحذفت)
  final String? alt; // وصف الصورة لقارئ الشاشة
  final String? thumbPath; // صورة مصغّرة للفيديو

  factory Msg.fromRow(Map<String, dynamic> r, String uid) => Msg(
        id: (r['id'] as num).toInt(),
        text: (r['body'] as String?) ?? '',
        mine: r['sender_id'] == uid,
        kind: (r['kind'] as String?) ?? 'text',
        read: r['read_at'] != null,
        mediaPath: r['media_path'] as String?,
        durationMs: (r['duration_ms'] as num?)?.toInt() ?? 0,
        at: DateTime.tryParse((r['created_at'] as String?) ?? '')?.toLocal(),
        replyToId: (r['reply_to_id'] as num?)?.toInt(),
        edited: r['edited_at'] != null,
        readAt: DateTime.tryParse((r['read_at'] as String?) ?? '')?.toLocal(),
        replyQuote: r['reply_quote'] as String?,
        alt: r['alt'] as String?,
        thumbPath: r['thumb_path'] as String?,
      );
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    super.key,
    required this.m,
    required this.onLongPress,
    required this.t,
    this.quote,
    this.reactions,
    this.joinPrev = false,
    this.joinNext = false,
    this.starred = false,
    this.onReply,
    this.rx,
    this.onReact,
    this.onQuoteTap,
  });

  final VoidCallback? onQuoteTap;

  /// تفاعلات الرسالة الخام (للتصويت)
  final Map<String, String>? rx;
  final void Function(String emoji)? onReact;

  /// سحب الفقاعة يمين أو يسار = رد عليها
  final VoidCallback? onReply;

  /// بالمفضلة عندي
  final bool starred;
  final ChatTheme t;

  /// رسالة قبلها (فوقها) من نفس الشخص خلال دقايق: نلصقهم بزوايا متصلة
  final bool joinPrev;

  /// رسالة بعدها (تحتها) من نفس الشخص
  final bool joinNext;
  final String? quote; // نص الرسالة الأصلية (إذا هذي رد)
  final List<String>? reactions; // التفاعلات مثل: 👍 2
  final Msg m;
  final VoidCallback onLongPress;

  Widget _content(BuildContext context) {
    final path = m.mediaPath;
    if (m.kind == 'card') return _CardMsg(text: m.text, color: m.durationMs);
    final fg = m.mine ? Colors.white : t.text;
    if (m.kind == 'location') return _LocationMsg(body: m.text, fg: fg);
    if (m.kind == 'alert') return _AlertMsg(text: m.text);
    if (m.kind == 'ref') return _RefMsg(body: m.text, fg: fg);
    if (m.kind == 'text') {
      final poll = _parsePoll(m.text);
      if (poll != null) {
        return _PollMsg(q: poll.q, opts: poll.opts, votes: rx ?? const {}, onVote: onReact);
      }
    }
    if (m.kind == 'vnote' && path != null) {
      return _VideoNote(key: ValueKey('vn-${m.id}'), path: path, ms: m.durationMs);
    }
    if (m.kind == 'file' && path != null) {
      return _FileTile(path: path, name: m.text, size: m.durationMs);
    }
    if (path != null) {
      if (m.kind == 'image') {
        return GestureDetector(
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => ImageViewerScreen(path: path))),
          child: Hero(tag: 'img-$path', child: _NetImage(path: path)),
        );
      }
      if (m.kind == 'video') {
        return GestureDetector(
          onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => VideoScreen(path: path))),
          child: _VideoTile(ms: m.durationMs),
        );
      }
      if (m.kind == 'audio') {
        return _VoiceBubble(
            key: ValueKey('voice-${m.id}'), path: path, ms: m.durationMs);
      }
    }
    final k = _Prefs.fontScale.value;
    if (_emojiOnly) return Text(m.text, style: TextStyle(fontSize: 44 * k));
    final txt = _RichMsgText(
        text: m.text,
        style: TextStyle(fontSize: _Fs.title * k, color: m.mine ? Colors.white : t.text),
        linkColor: m.mine ? const Color(0xFFD6ECFF) : t.accent);
    final url = _firstUrl(m.text);
    if (url == null) return txt;
    return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [txt, const SizedBox(height: 6), _LinkPreview(url: url, mine: m.mine)]);
  }

  BorderRadiusDirectional _corners() {
    final shape = _Prefs.bubbleShape.value;
    final big = Radius.circular(shape == 1 ? 10 : (shape == 2 ? 26 : 20));
    final small = Radius.circular(shape == 1 ? 3 : (shape == 2 ? 12 : 6));
    return m.mine
        ? BorderRadiusDirectional.only(
            topStart: joinPrev ? small : big,
            bottomStart: joinNext ? small : big,
            topEnd: big,
            bottomEnd: big)
        : BorderRadiusDirectional.only(
            topEnd: joinPrev ? small : big,
            bottomEnd: joinNext ? small : big,
            topStart: big,
            bottomStart: big);
  }

  /// رسالة كلها إيموجي (لين 6): تطلع كبيرة بدون فقاعة
  bool get _emojiOnly {
    if (m.kind != 'text' || m.replyToId != null) return false;
    final s = m.text.trim();
    if (s.isEmpty || s.runes.length > 12) return false;
    return !RegExp(r'[\p{L}\p{N}]', unicode: true).hasMatch(s);
  }

  @override
  Widget build(BuildContext context) {
    final big = m.mediaPath != null && m.kind != 'audio' && m.kind != 'file';
    final custom = m.mine ? _Prefs.myBubble.value : _Prefs.theirBubble.value;
    final base = custom >= 0
        ? _bubblePalette[custom % _bubblePalette.length].withValues(alpha: 0.85)
        : (m.mine ? t.mine : t.theirs);
    // بدون فقاعة: إيموجي لحاله، بطاقة ملوّنة، فيديو دائري
    final emoji = _emojiOnly || m.kind == 'card' || m.kind == 'vnote';
    // رسالة وصلت توها: تدخل بانزلاق وتلاشي
    final fresh =
        m.at != null && DateTime.now().difference(m.at!).inSeconds.abs() < 8;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: fresh ? 0 : 1, end: 1),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      builder: (_, v, child) => Opacity(
        opacity: v,
        child: Transform.translate(offset: Offset(0, 14 * (1 - v)), child: child),
      ),
      child: _SwipeReply(
      onReply: onReply,
      child: Align(
      alignment: m.mine
          ? AlignmentDirectional.centerStart
          : AlignmentDirectional.centerEnd,
      child: GestureDetector(
        onLongPress: onLongPress,
        onDoubleTap: (onReact != null && m.kind != 'call' && !(m.kind == 'text' && _parsePoll(m.text) != null))
            ? () => onReact!('❤️')
            : null,
        child: Container(
          margin: EdgeInsets.only(
              top: joinPrev ? 1.5 : 4, bottom: joinNext ? 1.5 : 4),
          constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.75),
          padding: big
              ? const EdgeInsets.all(_Sp.xs)
              : const EdgeInsets.symmetric(horizontal: 14, vertical: _Sp.sm),
          // زجاج خفيف بدون تمويه حقيقي، حتى يبقى التمرير ناعم
          decoration: emoji
              ? null
              : BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color.lerp(base, Colors.white, m.mine ? 0.18 : 0.10)!, base],
            ),
            borderRadius: _corners(),
            border: Border.all(
                color: Color(m.mine ? 0x40FFFFFF : 0x2EFFFFFF), width: 0.8),
            boxShadow: m.mine
                ? [
                    BoxShadow(
                        color: base.withValues(alpha: 0.25),
                        blurRadius: 10,
                        offset: const Offset(0, 3)),
                  ]
                : null,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (m.replyToId != null)
                GestureDetector(
                  onTap: onQuoteTap,
                  child: Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
                  decoration: BoxDecoration(
                    color: const Color(0x33000000),
                    borderRadius: BorderRadius.circular(8),
                    border: Border(
                        right: BorderSide(
                            color: m.mine ? Colors.white : t.accent, width: 3)),
                  ),
                  child: Text(quote ?? 'رسالة',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: _Fs.small, color: Colors.white70)),
                )),
              _content(context),
              if (reactions != null && reactions!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Wrap(spacing: 4, runSpacing: 4, children: [
                    for (final r in reactions!)
                      // التفاعل ينبض لما ينضاف أو يتغير عدده
                      TweenAnimationBuilder<double>(
                        key: ValueKey<String>(r),
                        tween: Tween<double>(begin: 0.4, end: 1),
                        duration: const Duration(milliseconds: 550),
                        curve: Curves.elasticOut,
                        builder: (_, v, child) =>
                            Transform.scale(scale: v, child: child),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0x55000000),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0x33FFFFFF)),
                          ),
                          child: Text(r, style: const TextStyle(fontSize: _Fs.meta)),
                        ),
                      ),
                  ]),
                ),
              const SizedBox(height: 2),
              Padding(
                padding: big
                    ? const EdgeInsets.symmetric(horizontal: _Sp.sm, vertical: 2)
                    : EdgeInsets.zero,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (starred) ...[
                    const Icon(Icons.star_rounded,
                        size: 13, color: Color(0xFFFFD60A)),
                    const SizedBox(width: 3),
                  ],
                  if (m.edited)
                    Text('معدّلة · ',
                        style: TextStyle(
                            fontSize: _Fs.caption,
                            color: m.mine
                                ? const Color(0xB3FFFFFF)
                                : t.text.withValues(alpha: 0.7))),
                  Text(_hhmm(m.at),
                      style: TextStyle(fontSize: _Fs.caption, color: m.mine ? const Color(0xB3FFFFFF) : t.text.withValues(alpha: 0.7))),
                  if (m.mine) ...[
                    const SizedBox(width: _Sp.xs),
                    Icon(m.read ? Icons.done_all_rounded : Icons.done_rounded,
                        size: 15,
                        color: m.read
                            ? const Color(0xFF7CFFB2)
                            : const Color(0xB3FFFFFF)),
                  ],
                ]),
              ),
            ],
          ),
        ),
      ),
      ),
      ),
    );
  }
}

class _SwipeReply extends StatefulWidget {
  const _SwipeReply({required this.child, this.onReply});
  final Widget child;
  final VoidCallback? onReply;

  @override
  State<_SwipeReply> createState() => _SwipeReplyState();
}

class _SwipeReplyState extends State<_SwipeReply> {
  double _dx = 0;
  bool _armed = false;

  @override
  Widget build(BuildContext context) {
    if (widget.onReply == null) return widget.child;
    final p = (_dx.abs() / 64).clamp(0.0, 1.0);
    return GestureDetector(
      onHorizontalDragUpdate: (d) {
        setState(() => _dx = (_dx + d.delta.dx).clamp(-80.0, 80.0));
        final armed = _dx.abs() >= 64;
        if (armed && !_armed) unawaited(HapticFeedback.selectionClick());
        _armed = armed;
      },
      onHorizontalDragEnd: (_) {
        if (_armed) widget.onReply!();
        setState(() {
          _dx = 0;
          _armed = false;
        });
      },
      onHorizontalDragCancel: () => setState(() {
        _dx = 0;
        _armed = false;
      }),
      child: Stack(alignment: Alignment.center, children: [
        if (p > 0)
          Positioned.fill(
            child: Align(
              alignment:
                  _dx > 0 ? Alignment.centerLeft : Alignment.centerRight,
              child: Opacity(
                opacity: p,
                child: Transform.scale(
                  scale: 0.6 + 0.4 * p,
                  child: const Icon(Icons.reply_rounded, size: 22),
                ),
              ),
            ),
          ),
        AnimatedContainer(
          duration: Duration(milliseconds: _dx == 0 ? 180 : 0),
          curve: Curves.easeOut,
          transform: Matrix4.translationValues(_dx, 0, 0),
          child: widget.child,
        ),
      ]),
    );
  }
}
