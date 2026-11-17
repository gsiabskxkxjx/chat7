part of 'main.dart';

// ---------- الجولة الثانية: جسر أندرويد الأصلي ----------
// 281 منع لقطات الشاشة · 234/247 حساس القرب · 235 إبقاء الشاشة مضيئة
// 304 استقبال مشاركة من تطبيقات ثانية · 385 بلاطة «أفكر فيك»

class _R2Native {
  static const _ch = MethodChannel('bainatna/r2');

  static Future<void> _call(String m, [Object? a]) async {
    try {
      await _ch.invokeMethod<void>(m, a);
    } catch (_) {}
  }

  static bool get secureSaved => _R2Store.get<bool>('secure') == true;

  static Future<void> applySaved() async {
    if (secureSaved) await _call('secure', true);
  }

  static Future<void> setSecure(bool on) async {
    await _R2Store.set('secure', on);
    await _call('secure', on);
  }

  /// أثناء المكالمة: صوتية = حساس القرب، فيديو = الشاشة تبقى مضيئة
  static Future<void> callMode({required bool video}) async {
    await _call('keepOn', video);
    await _call('proximity', !video);
  }

  static Future<void> callEnd() async {
    await _call('keepOn', false);
    await _call('proximity', false);
  }

  static Future<Map<dynamic, dynamic>?> takeShare() async {
    try {
      final r = await _ch.invokeMethod<Object?>('takeShare');
      return r is Map ? r : null;
    } catch (_) {
      return null;
    }
  }
}

class _SecureTile extends StatefulWidget {
  const _SecureTile();

  @override
  State<_SecureTile> createState() => _SecureTileState();
}

class _SecureTileState extends State<_SecureTile> {
  bool _on = _R2Native.secureSaved;

  @override
  Widget build(BuildContext context) => SwitchListTile(
        secondary: const Icon(Icons.screenshot_monitor_rounded),
        title: const Text('منع لقطات الشاشة'),
        subtitle: const Text('يمنع التصوير ويخفي المحتوى بمعاينة التطبيقات الأخيرة'),
        value: _on,
        onChanged: (v) async {
          setState(() => _on = v);
          await _R2Native.setSecure(v);
        },
      );
}

extension _R2Incoming on _ChatState {
  /// مشاركة وصلت من تطبيق ثاني (نص أو صورة) أو بلاطة «أفكر فيك»
  Future<void> _checkIncomingShare() async {
    final s = await _R2Native.takeShare();
    if (s == null || !mounted) return;
    if (s['think'] == true) {
      await _thinkOfYou();
      if (mounted) unawaited(SystemNavigator.pop());
      return;
    }
    final text = (s['text'] as String?)?.trim();
    final file = s['file'] as String?;
    final hasText = text != null && text.isNotEmpty;
    if (!hasText && file == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('ترسل هذا إلى ${_title()}؟'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (file != null)
              ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.file(File(file), height: 180, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Text('صورة'))),
            if (hasText)
              Padding(
                  padding: EdgeInsets.only(top: file == null ? 0 : 8),
                  child: Text(text.length > 300 ? '${text.substring(0, 300)}…' : text)),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('أرسل')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      if (file != null) {
        final mime = (s['mime'] as String?) ?? 'image/jpeg';
        await _sendMedia(
            chatId: widget.chat.id,
            file: File(file),
            kind: 'image',
            ext: file.split('.').last.toLowerCase(),
            mime: mime);
      }
      if (hasText) {
        await _db.from('messages').insert({'chat_id': widget.chat.id, 'kind': 'text', 'body': text});
      }
      if (mounted) _toast(context, 'انرسل.');
    } catch (e) {
      if (mounted) _toast(context, _friendlyError(e));
    }
  }
}

// ===== نغمات المكالمة (231 نغمة الرنين عند المتصل، 239 نغمة الإنهاء) =====
// تتولّد كملف WAV صغير بالجوال، فما نحتاج ملفات صوت بالمشروع

Uint8List _wavBytes(int rate, List<int> pcm) {
  final d = ByteData(44 + pcm.length * 2);
  void tag(int o, String t) {
    for (var i = 0; i < t.length; i++) {
      d.setUint8(o + i, t.codeUnitAt(i));
    }
  }

  tag(0, 'RIFF');
  d.setUint32(4, 36 + pcm.length * 2, Endian.little);
  tag(8, 'WAVE');
  tag(12, 'fmt ');
  d.setUint32(16, 16, Endian.little);
  d.setUint16(20, 1, Endian.little);
  d.setUint16(22, 1, Endian.little);
  d.setUint32(24, rate, Endian.little);
  d.setUint32(28, rate * 2, Endian.little);
  d.setUint16(32, 2, Endian.little);
  d.setUint16(34, 16, Endian.little);
  tag(36, 'data');
  d.setUint32(40, pcm.length * 2, Endian.little);
  for (var i = 0; i < pcm.length; i++) {
    d.setInt16(44 + i * 2, pcm[i], Endian.little);
  }
  return d.buffer.asUint8List();
}

/// نغمة بتردد معيّن: from..to بالثواني ضمن مصفوفة
void _addTone(List<int> pcm, int rate, double from, double to, double hz, {double amp = 0.28}) {
  final a = (from * rate).round();
  final b = math.min(pcm.length, (to * rate).round());
  final fade = (0.02 * rate).round();
  for (var i = a; i < b; i++) {
    var g = amp;
    if (i - a < fade) g *= (i - a) / fade;
    if (b - i < fade) g *= (b - i) / fade;
    pcm[i] = (math.sin(2 * math.pi * hz * (i / rate)) * g * 32767).round();
  }
}

class _R2Tone {
  static VideoPlayerController? _c;
  static int _gen = 0;

  static Future<File> _file(String name, List<int> Function() make) async {
    final f = File('${(await getTemporaryDirectory()).path}/$name');
    if (!await f.exists() || await f.length() < 100) {
      await f.writeAsBytes(_wavBytes(8000, make()));
    }
    return f;
  }

  static Future<void> _play(String name, List<int> Function() make, {required bool loop, double vol = 0.6}) async {
    final my = ++_gen;
    try {
      await _stop(bump: false);
      final f = await _file(name, make);
      if (my != _gen) return;
      final c = VideoPlayerController.file(f);
      _c = c;
      await c.initialize();
      if (my != _gen) {
        await c.dispose();
        if (identical(_c, c)) _c = null;
        return;
      }
      await c.setLooping(loop);
      await c.setVolume(vol);
      await c.play();
      if (!loop) {
        unawaited(Future<void>.delayed(const Duration(seconds: 2), () {
          if (my == _gen) unawaited(_stop());
        }));
      }
    } catch (_) {}
  }

  static Future<void> _stop({bool bump = true}) async {
    if (bump) _gen++;
    final c = _c;
    _c = null;
    if (c != null) {
      try {
        await c.pause();
        await c.dispose();
      } catch (_) {}
    }
  }

  /// نغمة «يرن...» عند المتصل: ثانية نغمة وثلاث ثواني صمت
  static Future<void> ringback(bool on) async {
    if (!on) {
      await _stop();
      return;
    }
    if (_c != null) return;
    await _play('r2_ringback.wav', () {
      final p = List<int>.filled(8000 * 4, 0);
      _addTone(p, 8000, 0, 1.0, 425);
      return p;
    }, loop: true);
  }

  /// نغمة قصيرة لما تنتهي المكالمة
  static Future<void> ended() async {
    await _play('r2_end.wav', () {
      final p = List<int>.filled(8000 ~/ 2 + 400, 0);
      _addTone(p, 8000, 0, 0.16, 480);
      _addTone(p, 8000, 0.24, 0.40, 380);
      return p;
    }, loop: false, vol: 0.5);
  }
}

// ===== ويدجت «موعدنا القادم» (381) وحالة «شنو أحتاج» (383) =====

DateTime _nextOcc(DateTime on, String rep, DateTime from) {
  if (rep == 'none' || !on.isBefore(from)) return on;
  var d = on;
  for (var i = 1; i < 5000 && d.isBefore(from); i++) {
    d = switch (rep) {
      'weekly' => on.add(Duration(days: 7 * i)),
      'monthly' => DateTime(on.year, on.month + i, on.day),
      'yearly' => DateTime(on.year + i, on.month, on.day),
      _ => on,
    };
    if (rep != 'weekly' && rep != 'monthly' && rep != 'yearly') break;
  }
  return d;
}

extension _R2WidgetFeed on _ChatState {
  Future<void> _feedNextWidget() async {
    try {
      final today = _today();
      final rows = await _db
          .from('chat_events')
          .select('title,on_date,repeat_every')
          .eq('chat_id', widget.chat.id)
          .limit(200);
      DateTime? best;
      String? bestTitle;
      for (final r in rows) {
        final on = DateTime.tryParse('${r['on_date']}');
        if (on == null) continue;
        final d = _nextOcc(DateTime(on.year, on.month, on.day), '${r['repeat_every'] ?? 'none'}', today);
        if (d.isBefore(today)) continue;
        if (best == null || d.isBefore(best)) {
          best = d;
          bestTitle = '${r['title']}';
        }
      }
      await _HomeWidgets._save({
        'next_ms': best == null ? null : '${best.millisecondsSinceEpoch}',
        'next_title': bestTitle,
        'need': (_pNeed == null || _pNeed!.isEmpty) ? null : _pNeed,
      }, 'NextWidget');
      await _updateCountdown(best, bestTitle, today);
    } catch (_) {}
  }
}

// ===== إشعار ثابت بعدّ تنازلي لموعد قريب (386)، اختياري =====

const _countdownId = 9300;
String? _lastCountdown;

Future<void> _updateCountdown(DateTime? best, String? title, DateTime today) async {
  try {
    final on = _R2Store.get<bool>('ongoingNext') == true;
    final days = best?.difference(today).inDays;
    if (!on || best == null || days == null || days > 2) {
      if (_lastCountdown != null) {
        _lastCountdown = null;
        await _callNotifier.cancel(_countdownId);
      }
      return;
    }
    final body = days == 0 ? 'اليوم 🎉' : (days == 1 ? 'باجر' : 'بعد يومين');
    final key = '$title|$body';
    if (_lastCountdown == key) return;
    _lastCountdown = key;
    await _callNotifier.show(
      _countdownId,
      'موعدكم القادم: ${title ?? ''}',
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'countdown',
          'عدّ تنازلي للموعد',
          importance: Importance.low,
          priority: Priority.low,
          ongoing: true,
          autoCancel: false,
          onlyAlertOnce: true,
          silent: true,
          visibility: NotificationVisibility.private,
        ),
      ),
    );
  } catch (_) {}
}

class _CountdownTile extends StatefulWidget {
  const _CountdownTile();

  @override
  State<_CountdownTile> createState() => _CountdownTileState();
}

class _CountdownTileState extends State<_CountdownTile> {
  bool _on = _R2Store.get<bool>('ongoingNext') == true;

  @override
  Widget build(BuildContext context) => SwitchListTile(
        secondary: const Icon(Icons.hourglass_top_rounded),
        title: const Text('إشعار ثابت لموعد قريب'),
        subtitle: const Text('عدّ تنازلي بالإشعارات لما يبقى يومين أو أقل على موعدكم'),
        value: _on,
        onChanged: (v) async {
          setState(() => _on = v);
          await _R2Store.set('ongoingNext', v);
          if (!v) {
            _lastCountdown = null;
            try {
              await _callNotifier.cancel(_countdownId);
            } catch (_) {}
          }
        },
      );
}

// ===== قراءة الرسالة بصوت عالي (276) =====

class _R2Tts {
  static FlutterTts? _t;

  static Future<void> speak(String text) async {
    try {
      final t = _t ??= FlutterTts();
      await t.stop();
      final arabic = RegExp(r'[\u0600-\u06FF]').hasMatch(text);
      await t.setLanguage(arabic ? 'ar' : 'en-US');
      await t.speak(text);
    } catch (_) {}
  }

  static Future<void> stop() async {
    try {
      await _t?.stop();
    } catch (_) {}
  }
}
