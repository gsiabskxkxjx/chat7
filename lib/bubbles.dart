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
      );
}

class _Bubble extends StatelessWidget {
  const _Bubble({super.key, required this.m, required this.onLongPress, required this.t, this.quote, this.reactions});
  final ChatTheme t;
  final String? quote; // نص الرسالة الأصلية (إذا هذي رد)
  final List<String>? reactions; // التفاعلات مثل: 👍 2
  final Msg m;
  final VoidCallback onLongPress;

  Widget _content(BuildContext context) {
    final path = m.mediaPath;
    if (path != null) {
      if (m.kind == 'image') {
        return GestureDetector(
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => ImageViewerScreen(path: path))),
          child: _NetImage(path: path),
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
    return Text(m.text, style: TextStyle(fontSize: 16, color: m.mine ? Colors.white : t.text));
  }

  @override
  Widget build(BuildContext context) {
    final big = m.mediaPath != null && m.kind != 'audio';
    return Align(
      alignment: m.mine
          ? AlignmentDirectional.centerStart
          : AlignmentDirectional.centerEnd,
      child: GestureDetector(
        onLongPress: onLongPress,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.75),
          padding: big
              ? const EdgeInsets.all(4)
              : const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
              color: m.mine ? t.mine : t.theirs,
              borderRadius: BorderRadius.circular(20)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (m.replyToId != null)
                Container(
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
                      style: const TextStyle(fontSize: 12, color: Colors.white70)),
                ),
              _content(context),
              if (reactions != null && reactions!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Wrap(spacing: 4, runSpacing: 4, children: [
                    for (final r in reactions!)
                      Container(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0x55000000),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(r, style: const TextStyle(fontSize: 13)),
                      ),
                  ]),
                ),
              const SizedBox(height: 2),
              Padding(
                padding: big
                    ? const EdgeInsets.symmetric(horizontal: 8, vertical: 2)
                    : EdgeInsets.zero,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(_hhmm(m.at),
                      style: TextStyle(fontSize: 11, color: m.mine ? const Color(0xB3FFFFFF) : t.text.withValues(alpha: 0.7))),
                  if (m.mine) ...[
                    const SizedBox(width: 4),
                    Icon(m.read ? Icons.done_all : Icons.done,
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
    );
  }
}
