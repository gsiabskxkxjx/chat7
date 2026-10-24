part of 'main.dart';

// ---------- شاشات المكالمة ----------

String _two(int n) => n.toString().padLeft(2, '0');

class _CallBtn extends StatelessWidget {
  const _CallBtn({
    required this.icon,
    required this.onTap,
    this.bg = const Color(0x33FFFFFF),
    this.fg = Colors.white,
    this.label,
  });
  final IconData icon;
  final VoidCallback? onTap;
  final Color bg;
  final Color fg;
  final String? label;

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Material(
            color: bg,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Icon(icon, color: fg, size: 28),
              ),
            ),
          ),
          if (label != null) ...[
            const SizedBox(height: 6),
            Text(label!,
                style: const TextStyle(
                    fontSize: 12, color: Color(0xCCFFFFFF))),
          ],
        ],
      );
}

class _Who extends StatelessWidget {
  const _Who({required this.name, required this.status, this.big = true});
  final String name;
  final String status;
  final bool big;

  @override
  Widget build(BuildContext context) => Column(children: [
        CircleAvatar(
          radius: big ? 56 : 26,
          backgroundColor: _blue,
          child: Icon(Icons.person, size: big ? 64 : 30, color: Colors.white),
        ),
        const SizedBox(height: 14),
        Text('@$name',
            textDirection: TextDirection.ltr,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Text(status,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, color: Color(0xCCFFFFFF))),
      ]);
}

// ---------- مكالمة واردة ----------

class IncomingCallScreen extends StatefulWidget {
  const IncomingCallScreen(
      {super.key, required this.session, required this.partner});
  final CallSession session;
  final String partner;

  @override
  State<IncomingCallScreen> createState() => _IncomingState();
}

class _IncomingState extends State<IncomingCallScreen> {
  Timer? _ring;
  Timer? _timeout;
  bool _busy = false;
  bool _left = false;
  CallSession get s => widget.session;

  @override
  void initState() {
    super.initState();
    s.phase.addListener(_onPhase);
    _buzz();
    _ring = Timer.periodic(const Duration(seconds: 2), (_) => _buzz());
    _timeout = Timer(const Duration(seconds: 50),
        () => unawaited(s.end('مكالمة فائتة.')));
    WidgetsBinding.instance.addPostFrameCallback((_) => _onPhase());
  }

  @override
  void dispose() {
    _ring?.cancel();
    _timeout?.cancel();
    s.phase.removeListener(_onPhase);
    super.dispose();
  }

  void _buzz() {
    unawaited(SystemSound.play(SystemSoundType.alert));
    unawaited(HapticFeedback.heavyImpact());
  }

  void _onPhase() {
    if (_left || !mounted || s.phase.value != CallPhase.ended) return;
    _left = true;
    final msg = s.endReason;
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    if (msg != null) {
      messenger.showSnackBar(
          SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating));
    }
  }

  Future<void> _accept() async {
    if (_busy) return;
    setState(() => _busy = true);
    _ring?.cancel();
    _timeout?.cancel();
    await s.accept();
    if (!mounted || s.phase.value == CallPhase.ended) return;
    s.phase.removeListener(_onPhase);
    Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => CallScreen(session: s, partner: widget.partner)));
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: false,
        child: Scaffold(
          body: Backdrop(
            child: SafeArea(
              child: Column(children: [
                const Spacer(flex: 2),
                _Who(
                  name: widget.partner,
                  status: s.video ? 'مكالمة فيديو واردة' : 'مكالمة صوتية واردة',
                ),
                const Spacer(flex: 3),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 48),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _CallBtn(
                        icon: Icons.call_end,
                        bg: const Color(0xFFE5392E),
                        label: 'رفض',
                        onTap: _busy ? null : () => unawaited(s.hangup()),
                      ),
                      _CallBtn(
                        icon: s.video ? Icons.videocam : Icons.call,
                        bg: const Color(0xFF2FB344),
                        label: _busy ? 'لحظة...' : 'رد',
                        onTap: _busy ? null : _accept,
                      ),
                    ],
                  ),
                ),
              ]),
            ),
          ),
        ),
      );
}

// ---------- أثناء المكالمة ----------

class CallScreen extends StatefulWidget {
  const CallScreen({super.key, required this.session, required this.partner});
  final CallSession session;
  final String partner;

  @override
  State<CallScreen> createState() => _CallState();
}

class _CallState extends State<CallScreen> {
  Timer? _tick;
  bool _closing = false;
  CallSession get s => widget.session;

  @override
  void initState() {
    super.initState();
    s.phase.addListener(_onPhase);
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _onPhase());
  }

  @override
  void dispose() {
    _tick?.cancel();
    s.phase.removeListener(_onPhase);
    super.dispose();
  }

  void _onPhase() {
    if (!mounted) return;
    setState(() {});
    if (s.phase.value != CallPhase.ended || _closing) return;
    _closing = true;
    final msg = s.endReason;
    final messenger = ScaffoldMessenger.of(context);
    Future.delayed(const Duration(milliseconds: 900), () {
      if (!mounted) return;
      Navigator.of(context).pop();
      if (msg != null) {
        messenger.showSnackBar(
            SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating));
      }
    });
  }

  String _status() {
    switch (s.phase.value) {
      case CallPhase.calling:
        return 'يرن...';
      case CallPhase.ringing:
        return '';
      case CallPhase.connecting:
        return 'جاري الاتصال...';
      case CallPhase.connected:
        final d = DateTime.now().difference(s.connectedAt ?? DateTime.now());
        return '${_two(d.inMinutes)}:${_two(d.inSeconds % 60)}';
      case CallPhase.ended:
        return s.endReason ?? 'انتهت المكالمة.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final ended = s.phase.value == CallPhase.ended;
    final r = s.remote;
    final l = s.local;
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: Backdrop(
          child: Stack(fit: StackFit.expand, children: [
            if (s.video && r != null && !ended)
              Positioned.fill(
                child: RTCVideoView(r,
                    objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover),
              ),
            SafeArea(
              child: Column(children: [
                const SizedBox(height: 32),
                _Who(
                  name: widget.partner,
                  status: _status(),
                  big: !(s.video && r != null && !ended),
                ),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 20,
                    runSpacing: 16,
                    children: [
                      ValueListenableBuilder<bool>(
                        valueListenable: s.muted,
                        builder: (_, m, __) => _CallBtn(
                          icon: m ? Icons.mic_off : Icons.mic,
                          label: 'كتم',
                          bg: m ? Colors.white : const Color(0x33FFFFFF),
                          fg: m ? Colors.black : Colors.white,
                          onTap: s.toggleMute,
                        ),
                      ),
                      ValueListenableBuilder<bool>(
                        valueListenable: s.speaker,
                        builder: (_, on, __) => _CallBtn(
                          icon: on ? Icons.volume_up : Icons.volume_down,
                          label: 'السماعة',
                          bg: on ? Colors.white : const Color(0x33FFFFFF),
                          fg: on ? Colors.black : Colors.white,
                          onTap: s.toggleSpeaker,
                        ),
                      ),
                      if (s.video)
                        ValueListenableBuilder<bool>(
                          valueListenable: s.camOff,
                          builder: (_, off, __) => _CallBtn(
                            icon: off ? Icons.videocam_off : Icons.videocam,
                            label: 'الكاميرا',
                            bg: off ? Colors.white : const Color(0x33FFFFFF),
                            fg: off ? Colors.black : Colors.white,
                            onTap: s.toggleCam,
                          ),
                        ),
                      if (s.video)
                        _CallBtn(
                          icon: Icons.cameraswitch,
                          label: 'قلب',
                          onTap: () => unawaited(s.flipCamera()),
                        ),
                      _CallBtn(
                        icon: Icons.call_end,
                        bg: const Color(0xFFE5392E),
                        label: 'إنهاء',
                        onTap: () => unawaited(s.hangup()),
                      ),
                    ],
                  ),
                ),
              ]),
            ),
            if (s.video && l != null && !ended)
              Positioned(
                top: 64,
                left: 16,
                width: 104,
                height: 144,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: RTCVideoView(l,
                      mirror: true,
                      objectFit:
                          RTCVideoViewObjectFit.RTCVideoViewObjectFitCover),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}
