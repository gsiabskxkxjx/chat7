part of 'main.dart';

// ---------- الشاشة 3: المحادثة ----------

class Msg {
  const Msg({
    required this.id,
    required this.text,
    required this.mine,
    required this.kind,
    required this.read,
    this.mediaPath,
    this.at,
  });

  final int id;
  final String text;
  final bool mine;
  final String kind; // text | image | video | audio
  final bool read;
  final String? mediaPath;
  final DateTime? at;

  factory Msg.fromRow(Map<String, dynamic> r, String uid) => Msg(
        id: (r['id'] as num).toInt(),
        text: (r['body'] as String?) ?? '',
        mine: r['sender_id'] == uid,
        kind: (r['kind'] as String?) ?? 'text',
        read: r['read_at'] != null,
        mediaPath: r['media_path'] as String?,
        at: DateTime.tryParse((r['created_at'] as String?) ?? '')?.toLocal(),
      );
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.chat});
  final ChatInfo chat;

  @override
  State<ChatScreen> createState() => _ChatState();
}

class _ChatState extends State<ChatScreen> {
  final _c = TextEditingController();
  final _picker = ImagePicker();
  late final String _uid = _db.auth.currentUser!.id;
  late final Stream<List<Map<String, dynamic>>> _stream = _db
      .from('messages')
      .stream(primaryKey: ['id'])
      .eq('chat_id', widget.chat.id)
      .order('id', ascending: false)
      .limit(200);

  late final CallHub _hub;
  late final ChatPulse _pulse;

  bool _online = false;
  double? _age;
  String? _pName;
  String? _pAvatar;
  bool _uploading = false;
  bool _markBusy = false;
  int _markedUpTo = -1;
  final _hidden = <int>{};

  @override
  void initState() {
    super.initState();
    _pName = widget.chat.partnerName;
    _pAvatar = widget.chat.partnerAvatar;
    _hub = CallHub(widget.chat.id, _uid, onIncoming: _incoming)..start();
    _pulse = ChatPulse(
      widget.chat.id,
      onPartner: _onPartner,
      onGone: _onGone,
      onResume: () => unawaited(_markRead()),
    )..start();
  }

  @override
  void dispose() {
    _pulse.stop();
    unawaited(_hub.dispose());
    _c.dispose();
    super.dispose();
  }

  // ---------- حالة الطرف الثاني ----------

  void _onPartner(bool online, double? age, String? name, String? avatar) {
    if (!mounted) return;
    setState(() {
      _online = online && (age ?? 999) < 45;
      _age = age;
      _pName = name;
      _pAvatar = avatar;
    });
  }

  void _onGone() {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => PairScreen(me: widget.chat.me)),
      (_) => false,
    );
    messenger.showSnackBar(const SnackBar(
        content: Text('الطرف الثاني ألغى الارتباط.'),
        behavior: SnackBarBehavior.floating));
  }

  String _title() {
    final n = _pName?.trim();
    return (n != null && n.isNotEmpty) ? n : '@${widget.chat.partner}';
  }

  String _status() {
    if (_online) return 'متصل الآن';
    final a = _age;
    if (a == null) return '';
    if (a < 90) return 'آخر ظهور قبل لحظات';
    final m = (a / 60).floor();
    if (m < 60) return 'آخر ظهور قبل $m د';
    final h = (m / 60).floor();
    if (h < 24) return 'آخر ظهور قبل $h س';
    return 'آخر ظهور قبل ${(h / 24).floor()} يوم';
  }

  void _partnerInfo() {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            _Avatar(path: _pAvatar, radius: 48),
            const SizedBox(height: 12),
            Text(_title(),
                style:
                    const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text('@${widget.chat.partner}',
                textDirection: TextDirection.ltr,
                style: const TextStyle(color: Color(0xAAFFFFFF))),
            const SizedBox(height: 8),
            Text(_status(),
                style: TextStyle(
                    color: _online
                        ? const Color(0xFF5BE584)
                        : const Color(0xAAFFFFFF))),
          ]),
        ),
      ),
    );
  }

  Future<void> _openProfile() => Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ProfileScreen(chat: widget.chat)));

  // ---------- علامات القراءة ----------

  Future<void> _markRead() async {
    if (_markBusy || !_pulse.foreground || !mounted) return;
    _markBusy = true;
    try {
      await _db.rpc('mark_read', params: {'p_chat': widget.chat.id});
    } catch (_) {}
    _markBusy = false;
  }

  void _checkUnread(List<Map<String, dynamic>> rows) {
    var newest = -1;
    for (final r in rows) {
      if (r['sender_id'] != _uid && r['read_at'] == null) {
        final id = (r['id'] as num).toInt();
        if (id > newest) newest = id;
      }
    }
    if (newest > _markedUpTo) {
      _markedUpTo = newest;
      WidgetsBinding.instance
          .addPostFrameCallback((_) => unawaited(_markRead()));
    }
  }

  // ---------- المكالمات ----------

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

  // ---------- الإرسال ----------

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

  Future<void> _attach() async {
    final act = await _photoSheet(context);
    if (!mounted || act == null) return;
    setState(() => _uploading = true);
    try {
      final x = await _picker.pickImage(
        source: act == 'camera' ? ImageSource.camera : ImageSource.gallery,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 82,
      );
      if (x != null) {
        final path =
            '${widget.chat.id}/${DateTime.now().microsecondsSinceEpoch}.${_extFor(x.path)}';
        await _db.storage.from('chat-media').upload(path, File(x.path),
            fileOptions: FileOptions(contentType: _mimeFor(x.path)));
        await _db.from('messages').insert({
          'chat_id': widget.chat.id,
          'kind': 'image',
          'media_path': path,
          'body': '',
        });
      }
    } catch (_) {
      if (mounted) _toast(context, 'تعذر إرسال الصورة. جرّب مرة ثانية.');
    }
    if (mounted) setState(() => _uploading = false);
  }

  // ---------- قائمة الرسالة (ضغطة مطولة) ----------

  Future<void> _msgMenu(Msg m) async {
    if (m.kind != 'text' && !m.mine) return;
    final act = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (m.kind == 'text')
            ListTile(
              leading: const Icon(Icons.copy),
              title: const Text('نسخ'),
              onTap: () => Navigator.pop(ctx, 'copy'),
            ),
          if (m.mine)
            ListTile(
              leading:
                  const Icon(Icons.delete_outline, color: Color(0xFFFF6B60)),
              title: const Text('حذف عند الطرفين'),
              onTap: () => Navigator.pop(ctx, 'del'),
            ),
        ]),
      ),
    );
    if (!mounted || act == null) return;
    if (act == 'copy') {
      await Clipboard.setData(ClipboardData(text: m.text));
      if (mounted) _toast(context, 'تم النسخ');
    } else if (act == 'del') {
      await _delete(m);
    }
  }

  Future<void> _delete(Msg m) async {
    setState(() => _hidden.add(m.id));
    try {
      final path = m.mediaPath;
      if (path != null) {
        try {
          await _db.storage.from('chat-media').remove([path]);
        } catch (_) {}
      }
      await _db.from('messages').delete().eq('id', m.id);
    } catch (_) {
      if (!mounted) return;
      setState(() => _hidden.remove(m.id));
      _toast(context, 'تعذر الحذف.');
    }
  }

  // ---------- الواجهة ----------

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
                  _Avatar(path: _pAvatar, radius: 20),
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
                                      : const Color(0x99FFFFFF))),
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
          return ListView.builder(
            reverse: true,
            padding: const EdgeInsets.all(16),
            itemCount: msgs.length,
            itemBuilder: (_, i) => _Bubble(
              key: ValueKey(msgs[i].id),
              m: msgs[i],
              onLongPress: () => _msgMenu(msgs[i]),
            ),
          );
        },
      );

  Widget _inputBar(bool typing) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
        child: Glass(
          radius: 28,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          child: Row(children: [
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
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _send(),
                inputFormatters: [LengthLimitingTextInputFormatter(4000)],
                decoration: const InputDecoration(
                    hintText: 'اكتب رسالة', border: InputBorder.none),
              ),
            ),
            IconButton(
              onPressed:
                  typing ? _send : () => _soon(context, 'الرسائل الصوتية'),
              icon: Icon(typing ? Icons.arrow_upward_rounded : Icons.mic,
                  color: typing ? _blue : null),
            ),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final typing = _c.text.trim().isNotEmpty;
    return Scaffold(
      body: Backdrop(
        child: SafeArea(
          child: Column(children: [
            _header(),
            Expanded(child: _messages()),
            _inputBar(typing),
          ]),
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({super.key, required this.m, required this.onLongPress});
  final Msg m;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final isImage = m.kind == 'image' && m.mediaPath != null;
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
          padding: isImage
              ? const EdgeInsets.all(4)
              : const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
              color: m.mine ? _blue : const Color(0x33FFFFFF),
              borderRadius: BorderRadius.circular(20)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (isImage)
                GestureDetector(
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => ImageViewerScreen(path: m.mediaPath!))),
                  child: _NetImage(path: m.mediaPath!),
                )
              else
                Text(m.text, style: const TextStyle(fontSize: 16)),
              const SizedBox(height: 2),
              Padding(
                padding: isImage
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
