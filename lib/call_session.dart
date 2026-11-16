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
  bool video; // يصير true لو حوّلتوا المكالمة لفيديو
  final bool outgoing;
  final Map<String, dynamic>? _offer;

  late final phase = ValueNotifier<CallPhase>(
      outgoing ? CallPhase.calling : CallPhase.ringing);
  final muted = ValueNotifier<bool>(false);
  final camOff = ValueNotifier<bool>(false);
  late final speaker = ValueNotifier<bool>(video);
  String? endReason;
  DateTime? connectedAt;

  /// ملاحظة تظهر للمتصل (مثلاً: الطرف الثاني غير متصل).
  String? hint;

  /// وصل مسار فيديو من الطرف الثاني؟
  bool gotRemoteVideo = false;

  /// جودة الاتصال (ممتاز/متوسط/ضعيف)
  final quality = ValueNotifier<String?>(null);
  Timer? _stats;

  /// أنا أرسل فيديو؟
  bool get sendingVideo => _stream?.getVideoTracks().isNotEmpty ?? false;

  /// تحويل مكالمة صوتية لفيديو (أو تشغيل كاميرتي بمكالمة صار فيها فيديو)
  Future<void> upgradeToVideo() async {
    final pc = _pc;
    final st = _stream;
    if (pc == null || st == null || _done || sendingVideo) return;
    try {
      final cam = await navigator.mediaDevices.getUserMedia({
        'audio': false,
        'video': {
          'mandatory': {'minWidth': '640', 'minHeight': '480', 'minFrameRate': '24'},
          'facingMode': 'user',
          'optional': [],
        },
      });
      final track = cam.getVideoTracks().first;
      await st.addTrack(track);
      await pc.addTrack(track, st);
      local?.srcObject = st;
      if (!video) {
        video = true;
        speaker.value = true;
        unawaited(Helper.setSpeakerphoneOn(true));
        unawaited(_allowPip(true));
      }
      final offer = await pc.createOffer();
      await pc.setLocalDescription(offer);
      await hub.send('candidate', callId, {'renego': 'offer', 'sdp': offer.sdp, 'type': offer.type});
    } catch (_) {}
  }

  /// انقطع الإنترنت وقت المكالمة ونحاول نرجّعها (مثلاً تبدّل من واي فاي لبيانات)
  final reconnecting = ValueNotifier<bool>(false);
  int _restarts = 0;
  Timer? _restartTimer;
  bool _restarting = false;

  /// ظهرت فعلاً صورة الطرف الثاني؟
  bool get remoteVideoReady => (remote?.videoWidth ?? 0) > 0;

  RTCVideoRenderer? local;
  RTCVideoRenderer? remote;
  RTCPeerConnection? _pc;
  MediaStream? _stream;
  MediaStream? _remoteStream;
  final _pending = <RTCIceCandidate>[];
  final _gate = Completer<void>();
  Future<void> _outbox = Future.value();
  bool _remoteSet = false;
  bool _accepted = false;
  bool _done = false;
  Timer? _timer;
  Timer? _watch;
  int _watchTries = 0;

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
      if (_done) return;
      if (e.streams.isNotEmpty) _remoteStream = e.streams.first;
      // نربط الفيديو لما يوصل مسار الفيديو نفسه. لو ربطناه مع مسار الصوت
      // (اللي ممكن يوصل قبل) ما يتعلق بالفيديو وتبقى شاشة الطرف الثاني فاضية.
      if (e.track.kind == 'video') {
        gotRemoteVideo = true;
        if (_remoteStream != null) remote?.srcObject = _remoteStream;
        _watchRemote();
      }
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

  /// يراقب أول 15 ثانية: إذا وصل مسار الفيديو بس الصورة ما ظهرت، يعيد الربط.
  void _watchRemote() {
    if (!video || _watch != null) return;
    _watch = Timer.periodic(const Duration(seconds: 1), (t) {
      _watchTries++;
      if (_done || _watchTries > 15 || remoteVideoReady) {
        t.cancel();
        _watch = null;
        return;
      }
      final rs = _remoteStream;
      final r = remote;
      if (rs != null && r != null && _watchTries % 2 == 0) {
        r.srcObject = null;
        r.srcObject = rs;
      }
    });
  }

  void _onConnState(RTCPeerConnectionState s) {
    if (_done) return;
    switch (s) {
      case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
        _timer?.cancel();
        _restartTimer?.cancel();
        _restarting = false;
        reconnecting.value = false;
        connectedAt ??= DateTime.now();
        phase.value = CallPhase.connected;
        if (video && _remoteStream != null) {
          remote?.srcObject = _remoteStream;
          _watchRemote();
        }
        unawaited(Helper.setSpeakerphoneOn(speaker.value));
        _liveCall = this;
        unawaited(_showOngoing(this));
        if (video) unawaited(_allowPip(true));
        _stats ??= Timer.periodic(const Duration(seconds: 3), (_) => unawaited(_readStats()));
        break;
      case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
        // ممكن يرجع لحاله خلال ثواني، وإذا ما رجع نعيد الاتصال
        if (connectedAt != null) {
          reconnecting.value = true;
          _restartTimer?.cancel();
          _restartTimer = Timer(const Duration(seconds: 3), () => unawaited(_iceRestart()));
        }
        break;
      case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
        if (connectedAt != null && _restarts < 3) {
          reconnecting.value = true;
          unawaited(_iceRestart());
        } else {
          unawaited(end('انقطع الاتصال.', send: 'hangup'));
        }
        break;
      default:
        break;
    }
  }

  /// إعادة الاتصال بدون ما تنقطع المكالمة: المتصل يرسل عرض جديد بعناوين جديدة
  Future<void> _iceRestart() async {
    final pc = _pc;
    if (pc == null || _done || _restarting) return;
    if (pc.connectionState == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
      reconnecting.value = false;
      return;
    }
    if (_restarts >= 3) {
      await end('انقطع الاتصال.', send: 'hangup');
      return;
    }
    _restarts++;
    // لو ما رجعت خلال 20 ثانية ننهيها
    _restartTimer?.cancel();
    _restartTimer = Timer(const Duration(seconds: 20), () {
      if (!_done &&
          _pc?.connectionState != RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        _restarting = false;
        unawaited(_iceRestart());
      }
    });
    if (!outgoing) return; // المستقبل ينتظر العرض الجديد من المتصل
    _restarting = true;
    try {
      await pc.restartIce();
      final offer = await pc.createOffer();
      await pc.setLocalDescription(offer);
      await hub.send('candidate', callId,
          {'restart': 'offer', 'sdp': offer.sdp, 'type': offer.type});
    } catch (_) {
      _restarting = false;
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
    _timer = Timer(const Duration(seconds: 30), () {
      if (phase.value != CallPhase.connected) {
        unawaited(end(
            'تعذر توصيل المكالمة. إذا عندك VPN، استثنِ بيناتنا منه وجرّب مرة ثانية.',
            send: 'hangup'));
      }
    });
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
          _timer = Timer(const Duration(seconds: 30), () {
            if (phase.value != CallPhase.connected) {
              unawaited(end(
                  'تعذر توصيل المكالمة. إذا عندك VPN، استثنِ بيناتنا منه وجرّب مرة ثانية.',
                  send: 'hangup'));
            }
          });
          await pc.setRemoteDescription(RTCSessionDescription(
              d['sdp'] as String?, d['type'] as String?));
          _remoteSet = true;
          await _flush();
          break;
        case 'candidate':
          // الطرف الثاني شغّل كاميرته (تحويل لفيديو): نرد بجواب جديد
          final renego = d['renego'];
          if (renego != null) {
            final pc = _pc;
            if (pc == null) return;
            if (renego == 'offer') {
              await pc.setRemoteDescription(
                  RTCSessionDescription(d['sdp'] as String?, d['type'] as String?));
              if (!video && '${d['sdp']}'.contains('m=video')) {
                video = true;
                speaker.value = true;
                unawaited(Helper.setSpeakerphoneOn(true));
                unawaited(_allowPip(true));
              }
              final answer = await pc.createAnswer();
              await pc.setLocalDescription(answer);
              await hub.send('candidate', callId,
                  {'renego': 'answer', 'sdp': answer.sdp, 'type': answer.type});
            } else if (renego == 'answer') {
              await pc.setRemoteDescription(
                  RTCSessionDescription(d['sdp'] as String?, d['type'] as String?));
            }
            return;
          }
          final restart = d['restart'];
          if (restart != null) {
            final pc = _pc;
            if (pc == null) return;
            if (restart == 'offer' && !outgoing) {
              reconnecting.value = true;
              await pc.setRemoteDescription(
                  RTCSessionDescription(d['sdp'] as String?, d['type'] as String?));
              final answer = await pc.createAnswer();
              await pc.setLocalDescription(answer);
              await hub.send('candidate', callId,
                  {'restart': 'answer', 'sdp': answer.sdp, 'type': answer.type});
            } else if (restart == 'answer' && outgoing) {
              await pc.setRemoteDescription(
                  RTCSessionDescription(d['sdp'] as String?, d['type'] as String?));
              _restarting = false;
            }
            return;
          }
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

  Future<void> _readStats() async {
    final pc = _pc;
    if (pc == null || _done) return;
    try {
      double? rtt;
      var lost = 0.0, got = 0.0;
      for (final r in await pc.getStats()) {
        final v = r.values;
        if (r.type == 'candidate-pair' && (v['state'] == 'succeeded' || v['nominated'] == true)) {
          final x = v['currentRoundTripTime'];
          if (x is num) rtt = x.toDouble();
        } else if (r.type == 'inbound-rtp') {
          final l = v['packetsLost'], g = v['packetsReceived'];
          if (l is num) lost += l.toDouble();
          if (g is num) got += g.toDouble();
        }
      }
      if (rtt == null) return;
      final loss = got + lost > 0 ? lost / (got + lost) : 0.0;
      quality.value = _qualityLabel(rtt, loss);
    } catch (_) {}
  }

  Future<void> end(String reason, {String? send}) async {
    if (_done) return;
    _done = true;
    _stats?.cancel();
    _restartTimer?.cancel();
    if (identical(_liveCall, this)) {
      _liveCall = null;
      unawaited(_hideOngoing());
      unawaited(_allowPip(false));
    }
    endReason = reason;
    if (outgoing) unawaited(_logCall()); // المتصل يسجّل المكالمة بالمحادثة
    _timer?.cancel();
    _watch?.cancel();
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

  /// يكتب سطر بالمحادثة: مكالمة صوتية/فيديو مع المدة، أو فائتة إذا ما انردت
  Future<void> _logCall() async {
    try {
      final kind = video ? 'فيديو' : 'صوتية';
      final c = connectedAt;
      final text = c == null
          ? 'مكالمة $kind فائتة'
          : 'مكالمة $kind ${_two(DateTime.now().difference(c).inMinutes)}:${_two(DateTime.now().difference(c).inSeconds % 60)}';
      await _db.from('messages').insert({
        'chat_id': hub.chatId,
        'kind': 'call',
        'body': text,
      });
    } catch (_) {}
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
