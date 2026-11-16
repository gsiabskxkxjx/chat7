part of 'main.dart';

// ---------- قصتنا (أول رسالة، أول صورة، أول مكالمة...) + المفضلة بفلاتر وصوتيات تشتغل ----------

class StoryScreen extends StatefulWidget {
  const StoryScreen({super.key, required this.chatId, this.since});
  final String chatId;
  final DateTime? since;

  @override
  State<StoryScreen> createState() => _StoryState();
}

class _StoryState extends State<StoryScreen> {
  List<({String emoji, String title, DateTime at, String? text})>? _items;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<Map<String, dynamic>?> _first(String kind, {String? like}) async {
    var q = _db
        .from('messages')
        .select('body,created_at')
        .eq('chat_id', widget.chatId)
        .eq('kind', kind);
    if (like != null) q = q.ilike('body', like);
    final r = await q.order('id', ascending: true).limit(1);
    return r.isEmpty ? null : r.first;
  }

  Future<void> _load() async {
    try {
      final res = await Future.wait([
        _first('text'),
        _first('image'),
        _first('audio'),
        _first('video'),
        _first('call'),
        _first('call', like: '%فيديو%'),
        _first('text', like: '%أحبك%'),
      ]);
      const meta = [
        ('💬', 'أول رسالة'),
        ('📷', 'أول صورة'),
        ('🎙️', 'أول رسالة صوتية'),
        ('🎬', 'أول فيديو'),
        ('📞', 'أول مكالمة'),
        ('🎥', 'أول مكالمة فيديو'),
        ('❤️', 'أول «أحبك»'),
      ];
      final items = <({String emoji, String title, DateTime at, String? text})>[];
      var since = widget.since;
      if (since == null) {
        try {
          final c = await _db
              .from('chats')
              .select('started_on,created_at')
              .eq('id', widget.chatId)
              .maybeSingle();
          since = DateTime.tryParse('${c?['started_on']}') ??
              DateTime.tryParse('${c?['created_at']}')?.toLocal();
        } catch (_) {
          // السيرفر قديم: نجرب تاريخ الربط بس
          try {
            final c = await _db
                .from('chats')
                .select('created_at')
                .eq('id', widget.chatId)
                .maybeSingle();
            since = DateTime.tryParse('${c?['created_at']}')?.toLocal();
          } catch (_) {}
        }
      }
      if (since != null) {
        items.add((emoji: '🌱', title: 'بداية قصتكم', at: since, text: null));
      }
      for (var i = 0; i < res.length; i++) {
        final r = res[i];
        final at = DateTime.tryParse('${r?['created_at']}')?.toLocal();
        if (r == null || at == null) continue;
        final body = '${r['body'] ?? ''}'.trim();
        items.add((
          emoji: meta[i].$1,
          title: meta[i].$2,
          at: at,
          text: (i == 0 || i == 6) && body.isNotEmpty ? body : null,
        ));
      }
      items.sort((a, b) => a.at.compareTo(b.at));
      if (mounted) setState(() => _items = items);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  String _ago(DateTime at) {
    final d = _today().difference(DateTime(at.year, at.month, at.day)).inDays;
    if (d <= 0) return 'اليوم';
    if (d == 1) return 'أمس';
    if (d < 30) return 'قبل $d يوم';
    if (d < 365) return 'قبل ${d ~/ 30} شهر';
    return 'قبل ${(d / 365).toStringAsFixed(1)} سنة';
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return Scaffold(
      appBar: AppBar(
          title: const Text('قصتنا'), backgroundColor: Colors.transparent),
      extendBodyBehindAppBar: true,
      body: Backdrop(
        child: SafeArea(
          child: _failed
              ? const Center(child: Text('تعذر التحميل، تأكد من الإنترنت.'))
              : items == null
                  ? const Center(child: CircularProgressIndicator())
                  : items.isEmpty
                      ? const Center(child: Text('قصتكم تبدأ بأول رسالة 🌱'))
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                          itemCount: items.length,
                          itemBuilder: (_, i) {
                            final it = items[i];
                            return IntrinsicHeight(
                              child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    SizedBox(
                                      width: 44,
                                      child: Column(children: [
                                        Container(
                                          width: 40,
                                          height: 40,
                                          alignment: Alignment.center,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: const Color(0x33FFFFFF),
                                            border: Border.all(
                                                color: const Color(0x80FFFFFF)),
                                          ),
                                          child: Text(it.emoji,
                                              style:
                                                  const TextStyle(fontSize: 20)),
                                        ),
                                        if (i < items.length - 1)
                                          Expanded(
                                            child: Container(
                                                width: 2,
                                                color: const Color(0x4DFFFFFF)),
                                          ),
                                      ]),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Padding(
                                        padding:
                                            const EdgeInsets.only(bottom: 18),
                                        child: Glass(
                                          radius: 20,
                                          shadow: false,
                                          padding: const EdgeInsets.all(14),
                                          child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(it.title,
                                                    style: const TextStyle(
                                                        fontSize: 17,
                                                        fontWeight:
                                                            FontWeight.w700)),
                                                const SizedBox(height: 4),
                                                Text(
                                                    '${it.at.day} ${_months[it.at.month - 1]} ${it.at.year} · ${_ago(it.at)}',
                                                    style: const TextStyle(
                                                        fontSize: 12,
                                                        color:
                                                            Color(0xB3FFFFFF))),
                                                if (it.text != null) ...[
                                                  const SizedBox(height: 8),
                                                  Text('«${it.text}»',
                                                      maxLines: 3,
                                                      overflow:
                                                          TextOverflow.ellipsis),
                                                ],
                                              ]),
                                        ),
                                      ),
                                    ),
                                  ]),
                            );
                          },
                        ),
        ),
      ),
    );
  }
}

/// المفضلة: الكل، نصوص، صور، صوتيات (الصوتيات تشتغل من هنا)
class StarredScreen extends StatefulWidget {
  const StarredScreen({super.key, required this.chatId});
  final String chatId;

  @override
  State<StarredScreen> createState() => _StarredState();
}

class _StarredState extends State<StarredScreen> {
  late final Future<List<Map<String, dynamic>>> _f = _db
      .from('message_stars')
      .select(
          'created_at, messages(id, body, kind, created_at, chat_id, media_path, duration_ms)')
      .order('created_at', ascending: false)
      .limit(300);
  String _kind = 'all';

  Widget _item(Map m) {
    final at = DateTime.tryParse('${m['created_at']}')?.toLocal();
    final kind = m['kind'] as String? ?? 'text';
    final path = m['media_path'] as String?;
    Widget body;
    if (kind == 'audio' && path != null) {
      body = _VoiceBubble(
          key: ValueKey('star-voice-${m['id']}'),
          path: path,
          ms: (m['duration_ms'] as num?)?.toInt() ?? 0);
    } else if (kind == 'image' && path != null) {
      body = GestureDetector(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => ImageViewerScreen(path: path))),
        child: Hero(tag: 'img-$path', child: _NetImage(path: path)),
      );
    } else if (kind == 'video' && path != null) {
      body = GestureDetector(
        onTap: () => Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => VideoScreen(path: path))),
        child: _VideoTile(ms: (m['duration_ms'] as num?)?.toInt() ?? 0),
      );
    } else {
      body = SelectableText('${m['body'] ?? ''}',
          style: const TextStyle(fontSize: 16));
    }
    return Glass(
      radius: 20,
      shadow: false,
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        body,
        const SizedBox(height: 6),
        Text(at == null ? '' : '${at.day}/${at.month}/${at.year}',
            style: const TextStyle(fontSize: 12, color: Color(0x99FFFFFF))),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
            title: const Text('الرسائل المفضلة'),
            backgroundColor: Colors.transparent),
        extendBodyBehindAppBar: true,
        body: Backdrop(
          child: SafeArea(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _f,
              builder: (_, snap) {
                if (snap.hasError) {
                  return const Center(
                      child: Text('المفضلة غير متوفرة بالسيرفر بعد.'));
                }
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final all = snap.data!
                    .map((r) => r['messages'])
                    .whereType<Map>()
                    .where((m) => m['chat_id'] == widget.chatId)
                    .toList();
                final rows = _kind == 'all'
                    ? all
                    : all.where((m) => (m['kind'] ?? 'text') == _kind).toList();
                return Column(children: [
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                    child: Row(children: [
                      for (final k in const [
                        ('all', 'الكل'),
                        ('text', 'نصوص'),
                        ('image', 'صور'),
                        ('audio', 'صوتيات'),
                        ('video', 'فيديو'),
                      ])
                        Padding(
                          padding: const EdgeInsetsDirectional.only(end: 8),
                          child: ChoiceChip(
                            label: Text(k.$2),
                            selected: _kind == k.$1,
                            onSelected: (_) => setState(() => _kind = k.$1),
                          ),
                        ),
                    ]),
                  ),
                  Expanded(
                    child: rows.isEmpty
                        ? const Center(
                            child: Padding(
                              padding: EdgeInsets.all(32),
                              child: Text(
                                  'ما في شي هنا. اضغط مطوّل على أي رسالة واختر «نجمة».',
                                  textAlign: TextAlign.center),
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.all(16),
                            itemCount: rows.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 10),
                            itemBuilder: (_, i) => _item(rows[i]),
                          ),
                  ),
                ]);
              },
            ),
          ),
        ),
      );
}

// ---------- كسر الجليد بالمحادثة المطابقة الجديدة ----------

const _iceBreakers = [
  'شنو أكثر شي يضحكك؟',
  'لو تقدر تسافر بكرة، وين تروح؟',
  'شنو أكلتك المفضلة؟',
  'صباحي ولا ليلي؟',
  'شنو آخر شي تعلمته وعجبك؟',
  'وش تسوي بوقت فراغك؟',
  'فيلم أو مسلسل تنصح فيه؟',
  'شنو حلمك اللي تبي تحققه؟',
  'شاي ولا قهوة؟',
  'شنو أحلى ذكرى من طفولتك؟',
];

// ---------- تأكيد كلمة السر قبل العمليات الحساسة ----------

Future<bool> _confirmPassword(BuildContext context, String username) async {
  final c = TextEditingController();
  var busy = false;
  String? err;
  final ok = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => AlertDialog(
        title: const Text('أكّد كلمة السر'),
        content: TextField(
          controller: c,
          obscureText: true,
          autofocus: true,
          decoration: InputDecoration(
              labelText: 'كلمة السر', errorText: err),
        ),
        actions: [
          TextButton(
              onPressed: busy ? null : () => Navigator.pop(ctx, false),
              child: const Text('إلغاء')),
          TextButton(
            onPressed: busy
                ? null
                : () async {
                    set(() {
                      busy = true;
                      err = null;
                    });
                    try {
                      await _db.auth.signInWithPassword(
                          email: _authEmail(username), password: c.text);
                      if (ctx.mounted) Navigator.pop(ctx, true);
                    } on AuthException {
                      set(() {
                        busy = false;
                        err = 'كلمة السر غلط.';
                      });
                    } catch (_) {
                      set(() {
                        busy = false;
                        err = 'تعذر التحقق، تأكد من الإنترنت.';
                      });
                    }
                  },
            child: const Text('تأكيد'),
          ),
        ],
      ),
    ),
  );
  c.dispose();
  return ok == true;
}
