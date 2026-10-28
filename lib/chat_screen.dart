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
  int _limit = 100;
  bool _hasMore = false;
  bool _loadingMore = false;
  final _scroll = ScrollController();
  late Stream<List<Map<String, dynamic>>> _stream = _makeStream();

  Stream<List<Map<String, dynamic>>> _makeStream() => _db
      .from('messages')
      .stream(primaryKey: ['id'])
      .eq('chat_id', widget.chat.id)
      .order('id', ascending: false)
      .limit(_limit);

  /// لما توصل لآخر الرسائل المعروضة، نحمّل 100 رسالة أقدم.
  void _onScroll() {
    if (!_scroll.hasClients || !_hasMore || _loadingMore) return;
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 300) {
      _loadingMore = true;
      setState(() {
        _limit += 100;
        _stream = _makeStream();
      });
      Future.delayed(const Duration(seconds: 2), () => _loadingMore = false);
    }
  }

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
  // مظهر المحادثة (الثيم والخلفية) - يتحدث لحاله من قاعدة البيانات
  ChatTheme _t = chatThemes.first;
  String _bgKind = 'gradient';
  String? _bgPath;
  String? _bgUrl;
  int _bgStrength = 10;
  StreamSubscription<List<Map<String, dynamic>>>? _lookSub;
  int _statusIdx = 0; // رقم الجملة الحالية (تتبدل كل 4 ثواني)
  Timer? _statusTimer;
  // "يكتب الآن..." - قناة بث خفيفة بين الطرفين (ما تحفظ شي بقاعدة البيانات)
  RealtimeChannel? _typeCh;
  DateTime _typingSeen = DateTime.fromMillisecondsSinceEpoch(0); // آخر مرة شفنا الطرف الثاني يكتب
  DateTime _typingSent = DateTime.fromMillisecondsSinceEpoch(0); // آخر مرة أرسلنا إشارة
  Timer? _typingTimer;
  DateTime? _linkedAt; // تاريخ ارتباطكم (لعداد الأيام)
  Msg? _replyTo; // الرسالة اللي تبي ترد عليها

  @override
  void initState() {
    super.initState();
    unawaited(Push.start());
    _scroll.addListener(_onScroll);
    _watchLook();
    _typeCh = _db.channel('typing-${widget.chat.id}')
      ..onBroadcast(event: 'typing', callback: _onTypingEvent)
      ..subscribe();
    _statusTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted) return;
      // ما نبدل والتطبيق بالخلفية
      final st = WidgetsBinding.instance.lifecycleState;
      if (st != null && st != AppLifecycleState.resumed) return;
      final n = statusLines(
        online: _online,
        age: _age,
        readerGender: widget.chat.myGender,
        partnerGender: _pGender,
      ).length;
      if (n > 1) setState(() => _statusIdx++);
    });
    _pName = widget.chat.partnerName;
    _pAvatar = widget.chat.partnerAvatar;
    _pGender = widget.chat.partnerGender;
    _hub = CallHub(widget.chat.id, _uid, onIncoming: _incoming)..start();
    unawaited(_hub.checkPending());
    _pulse = ChatPulse(
      widget.chat.id,
      onPartner: _onPartner,
      onGone: _onGone,
      onResume: () {
        unawaited(_markRead());
        unawaited(_hub.checkPending());
      },
    )..start();
  }

  @override
  void dispose() {
    _pulse.stop();
    _recTimer?.cancel();
    _lookSub?.cancel();
    _statusTimer?.cancel();
    _typingTimer?.cancel();
    final tc = _typeCh;
    if (tc != null) unawaited(_db.removeChannel(tc).then((_) {}));
    _scroll.dispose();
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

  void _onTypingEvent(Map<String, dynamic> payload) {
    final inner = payload['payload'];
    final uid = inner is Map ? inner['uid'] : payload['uid'];
    if (uid == _uid || !mounted) return;
    setState(() => _typingSeen = DateTime.now());
    _typingTimer?.cancel();
    _typingTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() {});
    });
  }

  // نرسل إشارة "يكتب" كل ثانيتين تقريباً وأنت تكتب
  void _notifyTyping() {
    if (_c.text.trim().isEmpty) return;
    final now = DateTime.now();
    if (now.difference(_typingSent) < const Duration(seconds: 2)) return;
    _typingSent = now;
    final ch = _typeCh;
    if (ch != null) unawaited(_sendTyping(ch));
  }

  Future<void> _sendTyping(RealtimeChannel ch) async {
    try {
      await ch.sendBroadcastMessage(event: 'typing', payload: {'uid': _uid});
    } catch (_) {}
  }

  String _status() {
    if (DateTime.now().difference(_typingSeen) < const Duration(seconds: 4)) {
      return 'يكتب الآن...';
    }
    final lines = statusLines(
      online: _online,
      age: _age,
      readerGender: widget.chat.myGender,
      partnerGender: _pGender,
    );
    return lines[_statusIdx % lines.length];
  }

  // ---------- علامات القراءة ----------

  // ---------- المكالمات ----------

  // ---------- الإرسال ----------

  // ---------- الرسائل الصوتية ----------

  // ---------- قائمة الرسالة (ضغطة مطولة) ----------

  // ---------- الواجهة ----------

  @override
  Widget build(BuildContext context) {
    final typing = _c.text.trim().isNotEmpty;
    return Scaffold(
      body: Stack(fit: StackFit.expand, children: [
        _chatBackground(),
        SafeArea(
          child: IconTheme(
            data: IconThemeData(color: _t.text),
            child: DefaultTextStyle.merge(
              style: TextStyle(color: _t.text),
              child: Column(children: [
                _header(),
                Expanded(child: _messages()),
                _inputBar(typing),
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}
