part of 'main.dart';

// ---------- الجولة الثانية: موقع، "أحتاجك"، بطاقة مرجع، موقع مباشر ----------
// 305 بطاقة مرجع · 306 بطاقة موقع · 307 أحتاجك · 351 أنا بطريقي (موقع لحظي مؤقت)

Map<String, dynamic>? _jsonMap(String s) {
  try {
    final v = jsonDecode(s);
    return v is Map ? Map<String, dynamic>.from(v) : null;
  } catch (_) {
    return null;
  }
}

/// نص مختصر للأنواع الخاصة (يُستخدم بالاقتباس والتصدير)
String? _specialPreview(String kind, String body) {
  switch (kind) {
    case 'location':
      return '📍 موقع';
    case 'alert':
      return '🆘 أحتاجك';
    case 'ref':
      final m = _jsonMap(body);
      return '🔖 ${m?['t'] ?? 'مرجع'}';
  }
  return null;
}

// آخر موقع معروف لي (يُحدَّث عند الإرسال أو المشاركة)
({double lat, double lng})? _lastMyPos;

double _distKm(double la1, double ln1, double la2, double ln2) => pure.distKm(la1, ln1, la2, ln2);

String _distLabel(double km) {
  if (km < 1) return '${_Fmt.digits('${(km * 1000).round()}')} م';
  return '${_Fmt.digits(km.toStringAsFixed(km < 10 ? 1 : 0))} كم';
}

Future<void> _openMap(double lat, double lng, {String? label}) async {
  final q = Uri.encodeComponent(label == null ? '$lat,$lng' : '$lat,$lng($label)');
  var ok = false;
  try {
    ok = await launchUrl(Uri.parse('geo:$lat,$lng?q=$q'), mode: LaunchMode.externalApplication);
  } catch (_) {}
  if (!ok) {
    try {
      await launchUrl(Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng'),
          mode: LaunchMode.externalApplication);
    } catch (_) {}
  }
}

Future<Position?> _getPos(BuildContext context, {bool quiet = false}) async {
  void say(String s) {
    if (!quiet && context.mounted) _toast(context, s);
  }

  try {
    if (!await Geolocator.isLocationServiceEnabled()) {
      say('شغّل الموقع (GPS) من إعدادات الجوال.');
      return null;
    }
    var p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
    if (p == LocationPermission.denied || p == LocationPermission.deniedForever) {
      say('ما عندي صلاحية الموقع. فعّلها من إعدادات التطبيق.');
      return null;
    }
    final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 20)));
    _lastMyPos = (lat: pos.latitude, lng: pos.longitude);
    return pos;
  } catch (_) {
    say('تعذر تحديد موقعك. جرّب مرة ثانية.');
    return null;
  }
}

// ===== مشاركة الموقع المباشر (محلياً بالتطبيق وهو مفتوح) =====

class _LiveShare {
  static Timer? _t;
  static String? chat;
  static DateTime? until;
  static final ValueNotifier<int> tick = ValueNotifier(0);

  static bool activeFor(String id) =>
      chat == id && until != null && until!.isAfter(DateTime.now());

  static Future<void> _push(BuildContext context) async {
    final c = chat;
    final u = until;
    if (c == null || u == null) return;
    if (!u.isAfter(DateTime.now())) {
      await stop();
      return;
    }
    final pos = await _getPos(context, quiet: true);
    if (pos == null) return;
    try {
      await _db.from('live_locations').upsert({
        'chat_id': c,
        'lat': pos.latitude,
        'lng': pos.longitude,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
        'expires_at': u.toUtc().toIso8601String(),
      }, onConflict: 'chat_id,user_id');
    } catch (_) {}
  }

  static Future<void> start(BuildContext context, String chatId, Duration d) async {
    await stop();
    final pos = await _getPos(context);
    if (pos == null) return;
    chat = chatId;
    until = DateTime.now().add(d);
    tick.value++;
    await _push(context);
    _t = Timer.periodic(const Duration(seconds: 25), (_) {
      if (context.mounted) unawaited(_push(context));
    });
  }

  static Future<void> stop() async {
    _t?.cancel();
    _t = null;
    final c = chat;
    chat = null;
    until = null;
    tick.value++;
    if (c != null) {
      try {
        await _db.from('live_locations').delete().eq('chat_id', c);
      } catch (_) {}
    }
  }
}

DateTime _lastAlertSent = DateTime.fromMillisecondsSinceEpoch(0);

extension _R2Share on _ChatState {
  /// مؤشر نشاط مؤقت للطرف الثاني: rec (يسجّل صوت) أو photo (يرسل صورة)
  Future<void> _sendAct(String act) async {
    final ch = _typeCh;
    if (ch == null) return;
    try {
      await ch.sendBroadcastMessage(event: 'typing', payload: {'uid': _uid, 'act': act});
    } catch (_) {}
  }

  Future<void> _insertSpecial(String kind, String body) async {
    try {
      await _db.from('messages').insert({'chat_id': widget.chat.id, 'kind': kind, 'body': body});
    } catch (e) {
      if (mounted) _toast(context, _friendlyError(e));
    }
  }

  Future<void> _sendLocation({String? note}) async {
    final p = await _getPos(context);
    if (p == null || !mounted) return;
    await _insertSpecial(
        'location',
        jsonEncode({
          'lat': double.parse(p.latitude.toStringAsFixed(5)),
          'lng': double.parse(p.longitude.toStringAsFixed(5)),
          if (note != null && note.isNotEmpty) 'n': note,
        }));
  }

  Future<void> _sendNeedYou() async {
    final now = DateTime.now();
    if (now.difference(_lastAlertSent) < const Duration(seconds: 60)) {
      _toast(context, 'أرسلت «أحتاجك» قبل شوي. انتظر دقيقة.');
      return;
    }
    final c = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('🆘 أحتاجك'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('ترسل له تنبيه مهم. استخدمها للمواقف اللي تحتاجه فيها فعلاً.'),
          const SizedBox(height: 10),
          TextField(
              controller: c,
              maxLength: 80,
              decoration: const InputDecoration(hintText: 'سطر توضيح (اختياري)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('أرسل')),
        ],
      ),
    );
    final note = c.text.trim();
    c.dispose();
    if (ok != true || !mounted) return;
    _lastAlertSent = DateTime.now();
    unawaited(HapticFeedback.heavyImpact());
    await _insertSpecial('alert', note.isEmpty ? 'أحتاجك' : note);
  }

  Future<void> _sendRef() async {
    final t = TextEditingController();
    final n = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('🔖 بطاقة مرجع'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
              controller: t,
              maxLength: 60,
              decoration: const InputDecoration(labelText: 'العنوان (مثلاً: مطعم، فيلم، كود الباب)')),
          TextField(
              controller: n,
              maxLines: 3,
              minLines: 1,
              maxLength: 400,
              decoration: const InputDecoration(labelText: 'التفاصيل أو الرابط')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('أرسل')),
        ],
      ),
    );
    final title = t.text.trim();
    final note = n.text.trim();
    t.dispose();
    n.dispose();
    if (ok != true || title.isEmpty || !mounted) return;
    final url = _firstUrl(note);
    await _insertSpecial('ref', jsonEncode({'t': title, if (note.isNotEmpty) 'n': note, if (url != null) 'u': url}));
  }

  Future<void> _omw() async {
    final mins = await showModalBottomSheet<int>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(
              padding: EdgeInsets.all(14),
              child: Text('🚗 أنا بطريقي: شارك موقعك المباشر', style: TextStyle(fontWeight: FontWeight.bold))),
          for (final m in const [15, 30, 60, 120])
            ListTile(
              title: Text('${_Fmt.digits('$m')} دقيقة'),
              onTap: () => Navigator.pop(ctx, m),
            ),
          const Padding(
              padding: EdgeInsets.fromLTRB(16, 4, 16, 14),
              child: Text(
                  'الموقع يتحدّث وأنت فاتح التطبيق، وينوقف تلقائياً بنهاية المدة. تقدر توقفه بأي وقت.',
                  style: TextStyle(fontSize: 12))),
        ]),
      ),
    );
    if (mins == null || !mounted) return;
    await _LiveShare.start(context, widget.chat.id, Duration(minutes: mins));
    if (!mounted || !_LiveShare.activeFor(widget.chat.id)) return;
    await _insertSpecial('text', '🚗 أنا بطريقي لك، تقدر تشوف موقعي المباشر لـ ${_Fmt.digits('$mins')} دقيقة.');
    if (mounted) setState(() {});
  }

  Future<void> _loadPartnerLoc() async {
    try {
      final pid = await _R2.partnerId(widget.chat.id);
      if (pid == null) return;
      final r = await _db
          .from('live_locations')
          .select('lat,lng,updated_at,expires_at')
          .eq('chat_id', widget.chat.id)
          .eq('user_id', pid)
          .maybeSingle();
      if (!mounted) return;
      final until = r == null ? null : DateTime.tryParse('${r['expires_at']}');
      final ok = r != null && (until == null || until.isAfter(DateTime.now()));
      if (ok != (_pLoc != null) || (ok && _pLoc?['updated_at'] != r?['updated_at'])) {
        setState(() => _pLoc = ok ? r : null);
      }
    } catch (_) {}
  }

  List<Widget> _shareBars() {
    final out = <Widget>[];
    if (_LiveShare.activeFor(widget.chat.id)) {
      out.add(_r2Bar('📍', 'تشارك موقعك المباشر لين ${_Fmt.time(_LiveShare.until!.toLocal())}',
          onClose: () async {
        await _LiveShare.stop();
        if (mounted) setState(() {});
      }));
    }
    final pod = _R2Store.get<Map>('pod_${widget.chat.id}');
    final podPath = pod?['path'];
    if (podPath is String) {
      out.add(_r2Bar('📸', 'صورة اليوم من ألبومكم',
          onTap: () => Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => ImageViewerScreen(path: podPath))),
          onClose: () async {
            await _R2Store.set('pod_${widget.chat.id}', null);
            if (mounted) setState(() {});
          }));
    }
    final p = _pLoc;
    if (p != null) {
      final lat = (p['lat'] as num).toDouble();
      final lng = (p['lng'] as num).toDouble();
      final at = DateTime.tryParse('${p['updated_at']}')?.toLocal();
      final mp = _lastMyPos;
      final d = mp == null ? '' : ' · يبعد ${_distLabel(_distKm(mp.lat, mp.lng, lat, lng))}';
      final ago = at == null ? '' : ' · ${_Fmt.ago(at)}';
      out.add(_r2Bar('🚗', '${_title()} يشارك موقعه المباشر$d$ago',
          onTap: () => unawaited(_openMap(lat, lng))));
    }
    return out;
  }
}

// ===== فقاعات =====

class _LocationMsg extends StatelessWidget {
  const _LocationMsg({required this.body, required this.fg});
  final String body;
  final Color fg;

  @override
  Widget build(BuildContext context) {
    final m = _jsonMap(body);
    final lat = (m?['lat'] as num?)?.toDouble();
    final lng = (m?['lng'] as num?)?.toDouble();
    if (lat == null || lng == null) return Text(body, style: TextStyle(color: fg));
    final note = '${m?['n'] ?? ''}'.trim();
    final mp = _lastMyPos;
    final dist = mp == null ? null : _distLabel(_distKm(mp.lat, mp.lng, lat, lng));
    return InkWell(
      onTap: () => unawaited(_openMap(lat, lng)),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            const Text('📍', style: TextStyle(fontSize: 26)),
            const SizedBox(width: 8),
            Flexible(
                child: Text('موقع',
                    style: TextStyle(color: fg, fontWeight: FontWeight.bold, fontSize: _Fs.title))),
          ]),
          if (note.isNotEmpty) Text(note, style: TextStyle(color: fg)),
          Text(
              '${_Fmt.digits(lat.toStringAsFixed(4))}, ${_Fmt.digits(lng.toStringAsFixed(4))}${dist == null ? '' : ' · $dist منك'}',
              style: TextStyle(color: fg.withValues(alpha: 0.75), fontSize: _Fs.meta)),
          const SizedBox(height: 4),
          Text('اضغط لفتح الخريطة ↗', style: TextStyle(color: fg.withValues(alpha: 0.9), fontSize: _Fs.meta)),
        ]),
      ),
    );
  }
}

class _AlertMsg extends StatelessWidget {
  const _AlertMsg({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.85, end: 1),
        duration: const Duration(milliseconds: 500),
        curve: Curves.elasticOut,
        builder: (_, v, child) => Transform.scale(scale: v, child: child),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: const LinearGradient(colors: [Color(0xFFFF3B30), Color(0xFFFF7A59)]),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Text('🆘', style: TextStyle(fontSize: 28)),
            const SizedBox(width: 10),
            Flexible(
                child: Text(text.isEmpty ? 'أحتاجك' : text,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: _Fs.title))),
          ]),
        ),
      );
}

class _RefMsg extends StatelessWidget {
  const _RefMsg({required this.body, required this.fg});
  final String body;
  final Color fg;

  @override
  Widget build(BuildContext context) {
    final m = _jsonMap(body);
    if (m == null) return Text(body, style: TextStyle(color: fg));
    final title = '${m['t'] ?? ''}';
    final note = '${m['n'] ?? ''}'.trim();
    final url = m['u'] as String?;
    return InkWell(
      onTap: url == null ? null : () => unawaited(launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication)),
      borderRadius: BorderRadius.circular(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Row(mainAxisSize: MainAxisSize.min, children: [
          const Text('🔖', style: TextStyle(fontSize: 20)),
          const SizedBox(width: 6),
          Flexible(
              child: Text(title,
                  style: TextStyle(color: fg, fontWeight: FontWeight.bold, fontSize: _Fs.title))),
        ]),
        if (note.isNotEmpty)
          Padding(
              padding: const EdgeInsets.only(top: 4),
              child: SelectableText(note, style: TextStyle(color: fg, fontSize: _Fs.body))),
        if (url != null)
          Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('فتح الرابط ↗', style: TextStyle(color: fg.withValues(alpha: 0.9), fontSize: _Fs.meta))),
      ]),
    );
  }
}
