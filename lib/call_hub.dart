part of 'main.dart';

// ---------- المكالمات: الإشارات (signaling) عبر Supabase ----------

/// إعدادات ICE: STUN مجاني من Google، و TURN اختياري من turn_config.dart
Map<String, dynamic> _rtcConfig() {
  final servers = <Map<String, dynamic>>[
    {
      'urls': [
        'stun:stun.l.google.com:19302',
        'stun:stun1.l.google.com:19302',
      ],
    },
  ];
  if (turnUrls.isNotEmpty &&
      turnUsername.isNotEmpty &&
      turnCredential.isNotEmpty) {
    servers.add({
      'urls': turnUrls,
      'username': turnUsername,
      'credential': turnCredential,
    });
  }
  return {'iceServers': servers, 'sdpSemantics': 'unified-plan'};
}

/// يربط محادثة واحدة بجدول call_signals ويوزّع الإشارات على المكالمة الحالية.
class CallHub {
  CallHub(this.chatId, this.myId, {required this.onIncoming});

  final String chatId;
  final String myId;
  final void Function(CallSession) onIncoming;

  RealtimeChannel? _ch;
  CallSession? current;
  bool ready = false;

  void start() {
    _ch = _db
        .channel('calls-$chatId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'call_signals',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'chat_id',
            value: chatId,
          ),
          callback: (p) => _onRow(p.newRecord),
        )
        .subscribe((status, [_]) {
      ready = status == RealtimeSubscribeStatus.subscribed;
    });
  }

  void _onRow(Map<String, dynamic> r) {
    if (r['sender_id'] == myId) return;
    final kind = r['kind'] as String;
    final id = r['call_id'] as String;
    final data = Map<String, dynamic>.from((r['data'] as Map?) ?? const {});

    if (kind == 'offer') {
      if (current != null) {
        // مشغول بمكالمة ثانية
        unawaited(send('decline', id, {'reason': 'busy'}));
        return;
      }
      final s = CallSession.incoming(this, id, data);
      current = s;
      onIncoming(s);
      return;
    }
    final cur = current;
    if (cur != null && cur.callId == id) {
      unawaited(cur.onSignal(kind, data));
    }
  }

  Future<void> send(String kind, String callId, Map<String, dynamic> data) =>
      _db.from('call_signals').insert({
        'chat_id': chatId,
        'kind': kind,
        'call_id': callId,
        'data': data,
      });

  /// ينظف إشارات المكالمة من السيرفر بعد ثواني من نهايتها.
  void clearSignals() {
    Future.delayed(const Duration(seconds: 5), () async {
      try {
        await _db.from('call_signals').delete().eq('chat_id', chatId);
      } catch (_) {}
    });
  }

  Future<void> dispose() async {
    final c = _ch;
    _ch = null;
    ready = false;
    await current?.hangup();
    if (c != null) {
      try {
        await _db.removeChannel(c);
      } catch (_) {}
    }
  }
}
