part of 'main.dart';

// ---------- الشاشة 3: المحادثة ----------

class Msg {
  const Msg(this.text, this.mine);
  final String text;
  final bool mine;
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.chat});
  final ChatInfo chat;

  @override
  State<ChatScreen> createState() => _ChatState();
}

class _ChatState extends State<ChatScreen> {
  final _c = TextEditingController();
  late final String _uid = _db.auth.currentUser!.id;
  late final Stream<List<Map<String, dynamic>>> _stream = _db
      .from('messages')
      .stream(primaryKey: ['id'])
      .eq('chat_id', widget.chat.id)
      .order('id', ascending: false)
      .limit(200);

  late final CallHub _hub;

  @override
  void initState() {
    super.initState();
    _hub = CallHub(widget.chat.id, _uid, onIncoming: _incoming)..start();
  }

  @override
  void dispose() {
    unawaited(_hub.dispose());
    _c.dispose();
    super.dispose();
  }

  void _incoming(CallSession s) {
    if (!mounted) {
      unawaited(s.end('مكالمة فائتة.', send: 'decline'));
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) =>
            IncomingCallScreen(session: s, partner: widget.chat.partner)));
  }

  Future<void> _call(bool video) async {
    if (_hub.current != null) return;
    if (!_hub.ready) {
      _toast(context, 'الاتصال بالسيرفر غير جاهز، جرّب بعد ثواني.');
      return;
    }
    final s = CallSession.outgoing(_hub, video);
    _hub.current = s;
    try {
      await s.startOutgoing();
    } catch (_) {
      await s.end(
          'تعذر بدء المكالمة. اسمح للتطبيق بالمايك والكاميرا من إعدادات الجوال.');
      if (mounted) _toast(context, s.endReason ?? 'تعذر بدء المكالمة.');
      return;
    }
    if (!mounted) return;
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => CallScreen(session: s, partner: widget.chat.partner)));
  }

  Future<void> _send() async {
    final t = _c.text.trim();
    if (t.isEmpty) return;
    _c.clear();
    setState(() {});
    try {
      await _db
          .from('messages')
          .insert({'chat_id': widget.chat.id, 'body': t});
    } catch (_) {
      if (!mounted) return;
      _c.text = t;
      setState(() {});
      _toast(context, 'تعذر الإرسال، حاول مرة ثانية.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final typing = _c.text.trim().isNotEmpty;
    return Scaffold(
      body: Backdrop(
        child: SafeArea(
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Glass(
                radius: 22,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(children: [
                  const CircleAvatar(
                      backgroundColor: _blue,
                      child: Icon(Icons.person, color: Colors.white)),
                  const SizedBox(width: 12),
                  Expanded(
                      child: Text('@${widget.chat.partner}',
                          style: const TextStyle(
                              fontSize: 17, fontWeight: FontWeight.w600))),
                  IconButton(
                      onPressed: () => _call(false),
                      icon: const Icon(Icons.call)),
                  IconButton(
                      onPressed: () => _call(true),
                      icon: const Icon(Icons.videocam)),
                ]),
              ),
            ),
            Expanded(
              child: StreamBuilder<List<Map<String, dynamic>>>(
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
                  if (rows.isEmpty) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: Text('ما في رسائل بعد. ابدأ المحادثة!',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Color(0xAAFFFFFF))),
                      ),
                    );
                  }
                  return ListView.builder(
                    reverse: true,
                    padding: const EdgeInsets.all(16),
                    itemCount: rows.length,
                    itemBuilder: (_, i) => _Bubble(Msg(
                      rows[i]['body'] as String,
                      rows[i]['sender_id'] == _uid,
                    )),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: Glass(
                radius: 28,
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                child: Row(children: [
                  IconButton(
                      onPressed: () => _soon(context, 'إرسال الصور والفيديو'),
                      icon: const Icon(Icons.add_circle_outline)),
                  Expanded(
                    child: TextField(
                      controller: _c,
                      onChanged: (_) => setState(() {}),
                      onSubmitted: (_) => _send(),
                      inputFormatters: [LengthLimitingTextInputFormatter(4000)],
                      decoration: const InputDecoration(
                          hintText: 'اكتب رسالة', border: InputBorder.none),
                    ),
                  ),
                  IconButton(
                    onPressed: typing
                        ? _send
                        : () => _soon(context, 'الرسائل الصوتية'),
                    icon: Icon(
                        typing ? Icons.arrow_upward_rounded : Icons.mic,
                        color: typing ? _blue : null),
                  ),
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble(this.m);
  final Msg m;

  @override
  Widget build(BuildContext context) => Align(
        alignment: m.mine
            ? AlignmentDirectional.centerStart
            : AlignmentDirectional.centerEnd,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          constraints:
              BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
                color: m.mine ? _blue : const Color(0x33FFFFFF),
                borderRadius: BorderRadius.circular(20)),
            child: Text(m.text, style: const TextStyle(fontSize: 16)),
          ),
        ),
      );
}
