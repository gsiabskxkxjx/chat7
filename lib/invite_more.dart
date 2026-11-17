part of 'main.dart';

// ---------- رابط الدعوة و QR، نسمعها سوا، الملصقات ----------

const _joinBase = 'https://gsiabskxkxjx.github.io/bainatna/join.html?c=';
String _joinLink(String code) => '$_joinBase$code';

/// رمز دعوة وصل من رابط (يستخدمه شاشة الربط)
final _pendingInvite = ValueNotifier<String?>(null);

void _listenInvites() {
  final links = AppLinks();
  void take(Uri? u) {
    if (u == null) return;
    final c = (u.queryParameters['c'] ?? '').toUpperCase().replaceAll(RegExp('[^A-Z0-9]'), '');
    if (c.length == 6) _pendingInvite.value = c;
  }

  unawaited(links.getInitialLink().then(take).catchError((_) {}));
  links.uriLinkStream.listen(take, onError: (_) {});
}

Future<void> _showInviteQr(BuildContext context, String code) => showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('امسح الرمز', textAlign: TextAlign.center),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            padding: const EdgeInsets.all(_Sp.md),
            decoration: BoxDecoration(
                color: Colors.white, borderRadius: BorderRadius.circular(20)),
            child: SizedBox(
              width: 220,
              height: 220,
              child: QrImageView(data: _joinLink(code), size: 220, backgroundColor: Colors.white),
            ),
          ),
          const SizedBox(height: _Sp.md),
          Text(code,
              textDirection: TextDirection.ltr,
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: 6)),
          const SizedBox(height: 6),
          const Text('خلّه يمسحه بكاميرا جواله، ويفتح بيناتنا وينربطون لحالهم.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: _Fs.meta, color: Color(0xCCFFFFFF))),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إغلاق')),
        ],
      ),
    );

// ===== نسمعها سوا =====

final _musicRe = RegExp(
    r'(youtube\.com|youtu\.be|spotify\.com|anghami\.com|soundcloud\.com|music\.apple\.com|deezer\.com)',
    caseSensitive: false);

bool _isMusicLink(String text) {
  final u = _firstUrl(text);
  return u != null && _musicRe.hasMatch(u);
}

extension _ChatListen on _ChatState {
  Future<void> _listenTogether(Msg m) async {
    final url = _firstUrl(m.text);
    final ch = _typeCh;
    if (url == null || ch == null) return;
    final start = DateTime.now().add(const Duration(seconds: 6)).millisecondsSinceEpoch;
    try {
      await ch.sendBroadcastMessage(
          event: 'listen', payload: {'uid': _uid, 'url': url, 'start': start});
    } catch (_) {
      if (mounted) _toast(context, 'تعذر إرسال الدعوة.');
      return;
    }
    if (!mounted) return;
    await _countdownOpen(url, start, 'ننتظره يضغط «معاك»... ونبدأ سوا');
  }

  void _onListen(Map<String, dynamic> payload) {
    final inner = payload['payload'];
    final p = inner is Map ? inner : payload;
    if (p['uid'] == _uid || !mounted) return;
    final url = '${p['url'] ?? ''}';
    final start = (p['start'] as num?)?.toInt() ?? 0;
    if (url.isEmpty || !url.startsWith('http')) return;
    unawaited(showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Text('🎧', style: TextStyle(fontSize: 36)),
        title: const Text('يبي تسمعونها سوا'),
        content: Text(Uri.tryParse(url)?.host ?? url, textAlign: TextAlign.center),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('مو الحين')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('معاك 🎧')),
        ],
      ),
    ).then((ok) {
      if (ok == true && mounted) unawaited(_countdownOpen(url, start, 'نبدأ سوا'));
    }));
  }

  /// عدّ تنازلي لين وقت البداية، بعدها يفتح الرابط
  Future<void> _countdownOpen(String url, int startMs, String note) async {
    final wait = startMs - DateTime.now().millisecondsSinceEpoch;
    if (wait > 0) {
      final m = ScaffoldMessenger.of(context);
      m.showSnackBar(SnackBar(
        content: Text('🎧 $note (${(wait / 1000).ceil()} ثواني)'),
        duration: Duration(milliseconds: wait),
      ));
      await Future<void>.delayed(Duration(milliseconds: wait));
    }
    if (mounted) await _openUrl(context, url);
  }
}

// ===== ملصقات بيناتنا (تنرسم بالجوال وتنرسل كصورة) =====

const _stickers = [
  ('🥰', 'أحبك', [Color(0xFFFF5FA2), Color(0xFFFF9FC6)]),
  ('🥺', 'اشتقتلك', [Color(0xFF7B5CFA), Color(0xFFBF9BFF)]),
  ('☀️', 'صباح الورد', [Color(0xFFFFB340), Color(0xFFFFE08A)]),
  ('🌙', 'تصبح على خير', [Color(0xFF1C2A6B), Color(0xFF5E5CE6)]),
  ('😂', 'هههههه', [Color(0xFF34C759), Color(0xFF9BE7A8)]),
  ('🤗', 'حضن', [Color(0xFFFF7EB6), Color(0xFFFFC7DD)]),
  ('😘', 'بوسة', [Color(0xFFFF453A), Color(0xFFFF8A80)]),
  ('🙈', 'استحيت', [Color(0xFFFF9F0A), Color(0xFFFFD29A)]),
  ('😤', 'زعلان', [Color(0xFF8E8E93), Color(0xFFC7C7CC)]),
  ('🥳', 'مبروك', [Color(0xFF0A84FF), Color(0xFF30D5C8)]),
  ('🤍', 'آسف', [Color(0xFF6E6E73), Color(0xFFE5E5EA)]),
  ('💪', 'تقدر', [Color(0xFF30B0C7), Color(0xFF9EE7F5)]),
  ('🍽️', 'جوعان', [Color(0xFFFF6B3D), Color(0xFFFFB199)]),
  ('😴', 'نعسان', [Color(0xFF3A3A8C), Color(0xFF8D8DE8)]),
  ('👀', 'وينك؟', [Color(0xFF5856D6), Color(0xFFAF52DE)]),
  ('❤️‍🔥', 'تموت فيني', [Color(0xFFFF2D55), Color(0xFFFF9500)]),
];

class _Sticker extends StatelessWidget {
  const _Sticker(this.i);
  final int i;

  @override
  Widget build(BuildContext context) {
    final s = _stickers[i];
    return Container(
      width: 160,
      height: 160,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: s.$3),
        border: Border.all(color: Colors.white, width: 6),
      ),
      alignment: Alignment.center,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(s.$1, style: const TextStyle(fontSize: 64)),
        Text(s.$2,
            style: const TextStyle(
                fontSize: _Fs.display,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                shadows: [Shadow(color: Color(0x88000000), blurRadius: 4)])),
      ]),
    );
  }
}

Future<void> _showStickers(BuildContext context, String chatId) async {
  final keys = List.generate(_stickers.length, (_) => GlobalKey());
  final pick = await showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(ctx).height * 0.6,
        child: GridView.count(
          crossAxisCount: 3,
          padding: const EdgeInsets.all(_Sp.md),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          children: [
            for (var i = 0; i < _stickers.length; i++)
              GestureDetector(
                onTap: () => Navigator.pop(ctx, i),
                child: FittedBox(
                  child: RepaintBoundary(key: keys[i], child: _Sticker(i)),
                ),
              ),
          ],
        ),
      ),
    ),
  );
  if (pick == null || !context.mounted) return;
  // نرسم الملصق بحجم كامل بطبقة مخفية ونحوله لصورة
  final key = GlobalKey();
  final entry = OverlayEntry(
    builder: (_) => Positioned(
      left: -1000,
      top: -1000,
      child: RepaintBoundary(key: key, child: Material(type: MaterialType.transparency, child: _Sticker(pick))),
    ),
  );
  Overlay.of(context).insert(entry);
  try {
    await WidgetsBinding.instance.endOfFrame;
    final box = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final img = await box.toImage(pixelRatio: 2.5);
    final data = await img.toByteData(format: ImageByteFormat.png);
    img.dispose();
    final dir = await getTemporaryDirectory();
    final f = File('${dir.path}/sticker_${DateTime.now().millisecondsSinceEpoch}.png');
    await f.writeAsBytes(data!.buffer.asUint8List());
    await _sendMedia(chatId: chatId, file: f, kind: 'image', ext: 'png', mime: 'image/png');
  } on PostgrestException catch (e) {
    if (context.mounted) {
      _toast(context,
          e.message.contains('media_locked') ? 'الصور تنفتح لما الطرفين يضغطون «أثق فيه».' : 'تعذر الإرسال.');
    }
  } catch (_) {
    if (context.mounted) _toast(context, 'تعذر إرسال الملصق.');
  } finally {
    entry.remove();
  }
}
