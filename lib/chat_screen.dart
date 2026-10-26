part of 'main.dart';

// ---------- الشاشة 3: المحادثة ----------

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
  String? _pGender;
  final _rec = VoiceRecorder();
  Timer? _recTimer;
  bool _recording = false;
  int _recSecs = 0;

  @override
  void initState() {
    super.initState();
    unawaited(Push.start());
    _pName = widget.chat.partnerName;
    _pAvatar = widget.chat.partnerAvatar;
    _pGender = widget.chat.partnerGender;
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
    _recTimer?.cancel();
    unawaited(_rec.cancel().then((_) => _rec.dispose()));
    unawaited(_hub.dispose());
    _c.dispose();
    super.dispose();
  }

  // ---------- حالة الطرف الثاني ----------

  void _onPartner(
      bool online, double? age, String? name, String? avatar, String? gender) {
    if (!mounted) return;
    setState(() {
      _online = online && (age ?? 999) < 45;
      _age = age;
      _pName = name;
      _pAvatar = avatar;
      _pGender = gender;
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
            _Avatar(path: _pAvatar, radius: 48, gender: _pGender),
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

  Future<String?> _attachSheet() => showModalBottomSheet<String>(
        context: context,
        builder: (ctx) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('صورة من المعرض'),
              onTap: () => Navigator.pop(ctx, 'photo_gallery'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('تصوير صورة'),
              onTap: () => Navigator.pop(ctx, 'photo_camera'),
            ),
            ListTile(
              leading: const Icon(Icons.video_library_outlined),
              title: const Text('فيديو من المعرض'),
              onTap: () => Navigator.pop(ctx, 'video_gallery'),
            ),
            ListTile(
              leading: const Icon(Icons.videocam_outlined),
              title: const Text('تسجيل فيديو'),
              onTap: () => Navigator.pop(ctx, 'video_camera'),
            ),
          ]),
        ),
      );

  Future<void> _attach() async {
    final act = await _attachSheet();
    if (!mounted || act == null) return;
    setState(() => _uploading = true);
    try {
      final camera = act.endsWith('camera');
      final src = camera ? ImageSource.camera : ImageSource.gallery;
      if (act.startsWith('photo')) {
        final x = await _picker.pickImage(
            source: src, maxWidth: 1600, maxHeight: 1600, imageQuality: 82);
        if (x != null) {
          await _sendMedia(
              chatId: widget.chat.id,
              file: File(x.path),
              kind: 'image',
              ext: _extFor(x.path),
              mime: _mimeFor(x.path));
        }
      } else {
        final x = await _picker.pickVideo(
            source: src, maxDuration: const Duration(minutes: 2));
        if (x != null) {
          final file = File(x.path);
          if (await file.length() > 50 * 1024 * 1024) {
            if (mounted) _toast(context, 'الفيديو كبير، الحد الأقصى 50 ميجا.');
          } else {
            await _sendMedia(
                chatId: widget.chat.id,
                file: file,
                kind: 'video',
                ext: _extOf(x.path),
                mime: _mimeForVideo(x.path));
          }
        }
      }
    } catch (_) {
      if (mounted) _toast(context, 'تعذر الإرسال. جرّب مرة ثانية.');
    }
    if (mounted) setState(() => _uploading = false);
  }

  // ---------- الرسائل الصوتية ----------

  Future<void> _startRec() async {
    if (_recording || _uploading) return;
    try {
      final ok = await _rec.start();
      if (!ok) {
        if (mounted) _toast(context, 'اسمح للتطبيق بالمايك من إعدادات الجوال.');
        return;
      }
    } catch (_) {
      if (mounted) _toast(context, 'تعذر بدء التسجيل.');
      return;
    }
    if (!mounted) {
      await _rec.cancel();
      return;
    }
    _recSecs = 0;
    _recTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _recSecs++);
      if (_recSecs >= 300) unawaited(_finishRec(true));
    });
    setState(() => _recording = true);
  }

  Future<void> _finishRec(bool send) async {
    if (!_recording) return;
    _recTimer?.cancel();
    if (mounted) setState(() => _recording = false);
    if (!send) {
      await _rec.cancel();
      return;
    }
    final clip = await _rec.stop();
    if (clip == null || clip.ms < 800) {
      if (mounted) _toast(context, 'التسجيل قصير جداً.');
      return;
    }
    if (mounted) setState(() => _uploading = true);
    try {
      await _sendMedia(
          chatId: widget.chat.id,
          file: clip.file,
          kind: 'audio',
          ext: 'm4a',
          mime: 'audio/mp4',
          durationMs: clip.ms);
    } catch (_) {
      if (mounted) _toast(context, 'تعذر إرسال الرسالة الصوتية.');
    }
    try {
      await clip.file.delete();
    } catch (_) {}
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
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _send(),
            inputFormatters: [LengthLimitingTextInputFormatter(4000)],
            decoration: const InputDecoration(
                hintText: 'اكتب رسالة', border: InputBorder.none),
          ),
        ),
        IconButton(
          onPressed: typing ? _send : _startRec,
          icon: Icon(typing ? Icons.arrow_upward_rounded : Icons.mic,
              color: typing ? _blue : null),
        ),
      ]);

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
