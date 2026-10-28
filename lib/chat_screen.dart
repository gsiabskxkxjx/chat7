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

  @override
  void initState() {
    super.initState();
    unawaited(Push.start());
    _scroll.addListener(_onScroll);
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
