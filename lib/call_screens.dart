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
  Widget build(BuildContext context) {
    // ثلاث حالات: زجاج عادي، زر مفعّل (أبيض صلب)، أو زجاج ملوّن متوهّج (إنهاء/رد)
    final plain = bg.a < 0.5;
    final solidWhite = bg == Colors.white;
    final glow = !plain && !solidWhite;
    return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            button: true,
            label: label,
            child: _Press(
              onTap: onTap,
              scale: 0.9,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: solidWhite
                      ? null
                      : LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: plain
                              ? const [Color(0x40FFFFFF), Color(0x14FFFFFF)]
                              : [
                                  Color.lerp(bg, Colors.white, 0.25)!,
                                  bg,
                                ],
                        ),
                  color: solidWhite ? Colors.white : null,
                  border: Border.all(
                      color: const Color(0x66FFFFFF), width: plain ? 1 : 0.8),
                  boxShadow: glow
                      ? [
                          BoxShadow(
                              color: bg.withValues(alpha: 0.55),
                              blurRadius: 26,
                              spreadRadius: 1),
                        ]
                      : null,
                ),
                child: Icon(icon, color: fg, size: 30),
              ),
            ),
          ),
          if (label != null) ...[
            const SizedBox(height: 6),
            Text(label!,
                style: const TextStyle(
                    fontSize: _Fs.small, color: Color(0xCCFFFFFF))),
          ],
        ],
      );
  }
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
          child: Icon(Icons.person_rounded, size: big ? 64 : 30, color: Colors.white),
        ),
        const SizedBox(height: 14),
        Text('@$name',
            textDirection: TextDirection.ltr,
            style: const TextStyle(fontSize: _Fs.big, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Text(status,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: _Fs.title, color: Color(0xCCFFFFFF))),
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
                        icon: Icons.call_end_rounded,
                        bg: const Color(0xFFE5392E),
                        label: 'رفض',
                        onTap: _busy ? null : () => unawaited(s.hangup()),
                      ),
                      _CallBtn(
                        icon: s.video ? Icons.videocam_rounded : Icons.call_rounded,
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
  bool _lastVideo = false;
  CallSession get s => widget.session;

  @override
  void initState() {
    super.initState();
    s.phase.addListener(_onPhase);
    unawaited(_R2Native.callMode(video: s.video));
    _lastVideo = s.video;
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (s.video != _lastVideo) {
        _lastVideo = s.video;
        unawaited(_R2Native.callMode(video: s.video));
      }
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _onPhase());
  }

  @override
  void dispose() {
    _tick?.cancel();
    unawaited(_R2Native.callEnd());
    unawaited(_R2Tone.ringback(false));
    s.phase.removeListener(_onPhase);
    super.dispose();
  }

  void _onPhase() {
    if (!mounted) return;
    setState(() {});
    final ph = s.phase.value;
    unawaited(_R2Tone.ringback(ph == CallPhase.calling && s.outgoing));
    if (ph != CallPhase.ended || _closing) return;
    _closing = true;
    unawaited(_R2Tone.ended());
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
        final h = s.hint;
        return h == null ? 'يرن...' : 'يرن...\n$h';
      case CallPhase.ringing:
        return '';
      case CallPhase.connecting:
        return 'جاري الاتصال...';
      case CallPhase.connected:
        final d = DateTime.now().difference(s.connectedAt ?? DateTime.now());
        final t = '${_two(d.inMinutes)}:${_two(d.inSeconds % 60)}';
        if (s.video && !s.remoteVideoReady) {
          return d.inSeconds < 4
              ? t
              : (s.gotRemoteVideo
                  ? '$t\nبانتظار ظهور صورة الطرف الثاني...'
                  : '$t\nالطرف الثاني ما يرسل فيديو (تأكد من إذن الكاميرا عنده)');
        }
        if (s.reconnecting.value) return '$t\nانقطع الإنترنت، نرجّع المكالمة...';
        final q = s.quality.value;
        return q == null ? t : '$t   $q';
      case CallPhase.ended:
        return s.endReason ?? 'انتهت المكالمة.';
    }
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
        valueListenable: _inPip,
        builder: (_, pip, __) {
          final r = s.remote;
          // بالنافذة العائمة: صورة الطرف الثاني بس
          if (pip && s.video && r != null) {
            return ColoredBox(
              color: Colors.black,
              child: RTCVideoView(r,
                  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover),
            );
          }
          return _full(context);
        },
      );

  Widget _full(BuildContext context) {
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
                          icon: m ? Icons.mic_off_rounded : Icons.mic_rounded,
                          label: 'كتم',
                          bg: m ? Colors.white : const Color(0x33FFFFFF),
                          fg: m ? Colors.black : Colors.white,
                          onTap: s.toggleMute,
                        ),
                      ),
                      ValueListenableBuilder<bool>(
                        valueListenable: s.speaker,
                        builder: (_, on, __) => _CallBtn(
                          icon: on ? Icons.volume_up_rounded : Icons.volume_down_rounded,
                          label: 'السماعة',
                          bg: on ? Colors.white : const Color(0x33FFFFFF),
                          fg: on ? Colors.black : Colors.white,
                          onTap: s.toggleSpeaker,
                        ),
                      ),
                      if (!s.sendingVideo && !ended && s.phase.value == CallPhase.connected)
                        _CallBtn(
                          icon: Icons.videocam_rounded,
                          label: s.video ? 'كاميرتي' : 'فيديو',
                          onTap: () => unawaited(s.upgradeToVideo()),
                        ),
                      if (s.sendingVideo)
                        ValueListenableBuilder<bool>(
                          valueListenable: s.camOff,
                          builder: (_, off, __) => _CallBtn(
                            icon: off ? Icons.videocam_off_rounded : Icons.videocam_rounded,
                            label: 'الكاميرا',
                            bg: off ? Colors.white : const Color(0x33FFFFFF),
                            fg: off ? Colors.black : Colors.white,
                            onTap: s.toggleCam,
                          ),
                        ),
                      if (s.sendingVideo)
                        _CallBtn(
                          icon: Icons.cameraswitch_rounded,
                          label: 'قلب',
                          onTap: () => unawaited(s.flipCamera()),
                        ),
                      _CallBtn(
                        icon: Icons.call_end_rounded,
                        bg: const Color(0xFFE5392E),
                        label: 'إنهاء',
                        onTap: () => unawaited(s.hangup()),
                      ),
                    ],
                  ),
                ),
              ]),
            ),
            if (s.sendingVideo && l != null && !ended)
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
