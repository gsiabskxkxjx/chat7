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
  });

  final int id;
  final String text;
  final bool mine;
  final String kind; // text | image | video | audio
  final bool read;
  final String? mediaPath;
  final int durationMs;
  final DateTime? at;

  factory Msg.fromRow(Map<String, dynamic> r, String uid) => Msg(
        id: (r['id'] as num).toInt(),
        text: (r['body'] as String?) ?? '',
        mine: r['sender_id'] == uid,
        kind: (r['kind'] as String?) ?? 'text',
        read: r['read_at'] != null,
        mediaPath: r['media_path'] as String?,
        durationMs: (r['duration_ms'] as num?)?.toInt() ?? 0,
        at: DateTime.tryParse((r['created_at'] as String?) ?? '')?.toLocal(),
      );
}

class _Bubble extends StatelessWidget {
  const _Bubble({super.key, required this.m, required this.onLongPress});
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
    return Text(m.text, style: const TextStyle(fontSize: 16));
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
              color: m.mine ? _blue : const Color(0x33FFFFFF),
              borderRadius: BorderRadius.circular(20)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _content(context),
              const SizedBox(height: 2),
              Padding(
                padding: big
                    ? const EdgeInsets.symmetric(horizontal: 8, vertical: 2)
                    : EdgeInsets.zero,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(_hhmm(m.at),
                      style: const TextStyle(
                          fontSize: 11, color: Color(0xB3FFFFFF))),
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
