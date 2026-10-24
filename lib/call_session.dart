part of 'main.dart';

// ---------- جلسة مكالمة واحدة (WebRTC) ----------

enum CallPhase { calling, ringing, connecting, connected, ended }

class CallSession {
  CallSession._(this.hub, this.callId, this.video, this.outgoing, this._offer);

  factory CallSession.outgoing(CallHub hub, bool video) => CallSession._(
      hub, '${DateTime.now().microsecondsSinceEpoch}', video, true, null);

  factory CallSession.incoming(
          CallHub hub, String id, Map<String, dynamic> offer) =>
      CallSession._(hub, id, offer['video'] == true, false, offer);

  final CallHub hub;
  final String callId;
  final bool video;
  final bool outgoing;
  final Map<String, dynamic>? _offer;

  late final phase = ValueNotifier<CallPhase>(
      outgoing ? CallPhase.calling : CallPhase.ringing);
  final muted = ValueNotifier<bool>(false);
  final camOff = ValueNotifier<bool>(false);
  late final speaker = ValueNotifier<bool>(video);
  String? endReason;
  DateTime? connectedAt;

  RTCVideoRenderer? local;
  RTCVideoRenderer? remote;
  RTCPeerConnection? _pc;
  MediaStream? _stream;
  final _pending = <RTCIceCandidate>[];
  final _gate = Completer<void>();
  Future<void> _outbox = Future.value();
  bool _remoteSet = false;
  bool _accepted = false;
  bool _done = false;
  Timer? _timer;

  // ---------- تجهيز المايك والكاميرا والاتصال ----------

  Future<void> _prepare() async {
    local = RTCVideoRenderer();
    remote = RTCVideoRenderer();
    await local!.initialize();
    await remote!.initialize();

    _stream = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': video
          ? {
              'mandatory': {
                'minWidth': '640',
                'minHeight': '480',
                'minFrameRate': '24',
              },
              'facingMode': 'user',
              'optional': [],
            }
          : false,
    });
    local!.srcObject = _stream;

    final pc = await createPeerConnection(_rtcConfig());
    _pc = pc;
    for (final t in _stream!.getTracks()) {
      await pc.addTrack(t, _stream!);
    }
    pc.onIceCandidate = (c) {
      if (c.candidate == null) return;
      _queue(() => hub.send('candidate', callId, {
            'candidate': c.candidate,
            'sdpMid': c.sdpMid,
            'sdpMLineIndex': c.sdpMLineIndex,
          }));
    };
    pc.onTrack = (e) {
      if (_done || e.streams.isEmpty) return;
      remote?.srcObject = e.streams.first;
    };
    pc.onConnectionState = _onConnState;
  }

  /// يرسل الإشارات بالترتيب، وبعد ما ينرسل العرض (offer) أو الجواب (answer).
  void _queue(Future<void> Function() job) {
    _outbox = _outbox.then((_) async {
      await _gate.future;
      if (_done) return;
      try {
        await job();
      } catch (_) {}
    });
  }

  void _onConnState(RTCPeerConnectionState s) {
    if (_done) return;
    switch (s) {
      case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
        connectedAt ??= DateTime.now();
        phase.value = CallPhase.connected;
        unawaited(Helper.setSpeakerphoneOn(speaker.value));
        break;
      case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
        unawaited(end('انقطع الاتصال.', send: 'hangup'));
        break;
      default:
        break;
    }
  }

  Future<void> _flush() async {
    final pc = _pc;
    if (pc == null) return;
    final list = List<RTCIceCandidate>.of(_pending);
    _pending.clear();
    for (final c in list) {
      try {
        await pc.addCandidate(c);
      } catch (_) {}
    }
  }

  // ---------- المتصل ----------

  Future<void> startOutgoing() async {
    await _prepare();
    final pc = _pc!;
    final offer = await pc.createOffer();
    await pc.setLocalDescription(offer);
    await hub.send('offer', callId,
        {'sdp': offer.sdp, 'type': offer.type, 'video': video});
    _gate.complete();
    _timer = Timer(
      const Duration(seconds: 45),
      () => unawaited(end('ما رد على المكالمة. تأكد إن التطبيق مفتوح عنده.',
          send: 'hangup')),
    );
  }

  // ---------- المستقبِل ----------

  Future<void> accept() async {
    if (_accepted || _done) return;
    _accepted = true;
    _timer?.cancel();
    phase.value = CallPhase.connecting;
    try {
      await _prepare();
      final pc = _pc!;
      final offer = _offer!;
      await pc.setRemoteDescription(RTCSessionDescription(
          offer['sdp'] as String?, offer['type'] as String?));
      _remoteSet = true;
      await _flush();
      final answer = await pc.createAnswer();
      await pc.setLocalDescription(answer);
      await hub.send(
          'answer', callId, {'sdp': answer.sdp, 'type': answer.type});
      _gate.complete();
    } catch (_) {
      await end('تعذر بدء المكالمة. اسمح للتطبيق بالمايك والكاميرا من إعدادات الجوال.',
          send: 'hangup');
    }
  }

  // ---------- إشارات واردة ----------

  Future<void> onSignal(String kind, Map<String, dynamic> d) async {
    if (_done) return;
    try {
      switch (kind) {
        case 'answer':
          final pc = _pc;
          if (!outgoing || pc == null || _remoteSet) return;
          _timer?.cancel();
          phase.value = CallPhase.connecting;
          await pc.setRemoteDescription(RTCSessionDescription(
              d['sdp'] as String?, d['type'] as String?));
          _remoteSet = true;
          await _flush();
          break;
        case 'candidate':
          final c = RTCIceCandidate(
            d['candidate'] as String?,
            d['sdpMid'] as String?,
            (d['sdpMLineIndex'] as num?)?.toInt(),
          );
          if (_remoteSet && _pc != null) {
            try {
              await _pc!.addCandidate(c);
            } catch (_) {}
          } else {
            _pending.add(c);
          }
          break;
        case 'decline':
          await end(d['reason'] == 'busy'
              ? 'الطرف الثاني مشغول بمكالمة ثانية.'
              : 'رفض المكالمة.');
          break;
        case 'hangup':
          await end(
              outgoing || _accepted ? 'انتهت المكالمة.' : 'مكالمة فائتة.');
          break;
      }
    } catch (_) {}
  }

  // ---------- أزرار التحكم ----------

  void toggleMute() {
    muted.value = !muted.value;
    for (final t in _stream?.getAudioTracks() ?? <MediaStreamTrack>[]) {
      t.enabled = !muted.value;
    }
  }

  void toggleCam() {
    camOff.value = !camOff.value;
    for (final t in _stream?.getVideoTracks() ?? <MediaStreamTrack>[]) {
      t.enabled = !camOff.value;
    }
  }

  Future<void> flipCamera() async {
    final v = _stream?.getVideoTracks() ?? <MediaStreamTrack>[];
    if (v.isNotEmpty) await Helper.switchCamera(v.first);
  }

  void toggleSpeaker() {
    speaker.value = !speaker.value;
    unawaited(Helper.setSpeakerphoneOn(speaker.value));
  }

  // ---------- الإنهاء ----------

  /// زر الإنهاء أو الرفض.
  Future<void> hangup() => end(
        outgoing || _accepted ? 'انتهت المكالمة.' : 'رفضت المكالمة.',
        send: !outgoing && !_accepted ? 'decline' : 'hangup',
      );

  Future<void> end(String reason, {String? send}) async {
    if (_done) return;
    _done = true;
    endReason = reason;
    _timer?.cancel();
    if (!_gate.isCompleted) _gate.complete();
    if (send != null) {
      try {
        await hub.send(send, callId, const {});
      } catch (_) {}
    }
    try {
      for (final t in _stream?.getTracks() ?? <MediaStreamTrack>[]) {
        await t.stop();
      }
      await _stream?.dispose();
    } catch (_) {}
    try {
      await _pc?.close();
    } catch (_) {}
    _pc = null;
    _stream = null;
    if (identical(hub.current, this)) hub.current = null;
    hub.clearSignals();
    phase.value = CallPhase.ended;
    // نحرر شاشات الفيديو بعد ما تنسكر شاشة المكالمة
    Future.delayed(const Duration(seconds: 2), _release);
  }

  Future<void> _release() async {
    final l = local, r = remote;
    local = null;
    remote = null;
    try {
      l?.srcObject = null;
      await l?.dispose();
    } catch (_) {}
    try {
      r?.srcObject = null;
      await r?.dispose();
    } catch (_) {}
  }
}
