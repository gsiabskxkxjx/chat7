part of 'main.dart';

// ---------- معاينة الروابط، صندوق الإرسال، نسخة محلية من الرسائل، شرح الصلاحيات، تلميحات، تنبيه التحديث ----------

// ===== فتح الروابط =====

Future<void> _openUrl(BuildContext? context, String url) async {
  var ok = false;
  try {
    ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  } catch (_) {}
  if (!ok && context != null && context.mounted) {
    await Clipboard.setData(ClipboardData(text: url));
    if (context.mounted) _toast(context, 'ما قدرنا نفتح الرابط، انسخ لك.');
  }
}

final _urlRe = RegExp(r'https?://[^\s<>"]+', caseSensitive: false);

String? _firstUrl(String text) {
  final m = _urlRe.firstMatch(text);
  if (m == null) return null;
  var u = m.group(0)!;
  // علامات الترقيم بآخر الجملة مو من الرابط
  while (u.isNotEmpty && '.,!?؟،)]}\''.contains(u[u.length - 1])) {
    u = u.substring(0, u.length - 1);
  }
  return Uri.tryParse(u)?.host.isNotEmpty == true ? u : null;
}

// ===== معاينة الروابط (عنوان وصورة) =====

class _LinkMeta {
  const _LinkMeta(this.host, this.title, this.image);
  final String host;
  final String? title;
  final String? image;
}

final _linkCache = <String, Future<_LinkMeta?>>{};

Future<_LinkMeta?> _linkMeta(String url) {
  if (_linkCache.length > 200) _linkCache.clear();
  return _linkCache[url] ??= _fetchLinkMeta(url);
}

String _unescapeHtml(String s) => s
    .replaceAll('&amp;', '&')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll('&#x27;', "'")
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&nbsp;', ' ');

Future<_LinkMeta?> _fetchLinkMeta(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null || uri.host.isEmpty) return null;
  final plain = _LinkMeta(uri.host, null, null);
  if (uri.scheme != 'https' || !_Prefs.linkPreviews.value) return plain;
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 5)
    ..userAgent = 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/124 Mobile Safari/537.36';
  try {
    final req = await client.getUrl(uri).timeout(const Duration(seconds: 6));
    req.headers.set('Accept', 'text/html');
    final res = await req.close().timeout(const Duration(seconds: 6));
    final type = res.headers.contentType?.mimeType ?? '';
    if (res.statusCode >= 400 || !type.contains('html')) return plain;
    final bytes = <int>[];
    await for (final chunk in res.timeout(const Duration(seconds: 6))) {
      bytes.addAll(chunk);
      if (bytes.length > 250000) break;
    }
    final html = utf8.decode(bytes, allowMalformed: true);
    String? meta(String p) {
      final a = RegExp(
              '<meta[^>]+(?:property|name)=["\']$p["\'][^>]*content=["\']([^"\']+)',
              caseSensitive: false)
          .firstMatch(html);
      final b = a ??
          RegExp('<meta[^>]+content=["\']([^"\']+)["\'][^>]*(?:property|name)=["\']$p["\']',
                  caseSensitive: false)
              .firstMatch(html);
      return b?.group(1);
    }

    var title = meta('og:title') ??
        meta('twitter:title') ??
        RegExp(r'<title[^>]*>([^<]+)</title>', caseSensitive: false)
            .firstMatch(html)
            ?.group(1);
    title = title == null ? null : _unescapeHtml(title.trim());
    if (title != null && title.length > 120) title = '${title.substring(0, 120)}…';
    var img = meta('og:image') ?? meta('twitter:image');
    if (img != null) {
      final r = uri.resolve(_unescapeHtml(img));
      img = r.scheme == 'https' ? r.toString() : null;
    }
    return _LinkMeta(uri.host, title, img);
  } catch (_) {
    return plain;
  } finally {
    client.close(force: true);
  }
}

class _LinkPreview extends StatelessWidget {
  const _LinkPreview({required this.url, required this.mine});
  final String url;
  final bool mine;

  @override
  Widget build(BuildContext context) => FutureBuilder<_LinkMeta?>(
        future: _linkMeta(url),
        builder: (context, snap) {
          final m = snap.data;
          final host = m?.host ?? Uri.tryParse(url)?.host ?? url;
          return _Press(
            onTap: () => _openUrl(context, url),
            scale: 0.98,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 260),
              decoration: BoxDecoration(
                color: const Color(0x26000000),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0x33FFFFFF)),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (m?.image != null)
                      AspectRatio(
                        aspectRatio: 1.91,
                        child: Image.network(m!.image!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                const SizedBox.shrink()),
                      ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (m?.title != null)
                              Text(m!.title!,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: _Fs.body,
                                      color: Colors.white)),
                            Row(mainAxisSize: MainAxisSize.min, children: [
                              const Icon(Icons.link_rounded,
                                  size: 14, color: Color(0xB3FFFFFF)),
                              const SizedBox(width: _Sp.xs),
                              Flexible(
                                child: Text(host,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontSize: _Fs.small,
                                        color: Color(0xB3FFFFFF))),
                              ),
                            ]),
                          ]),
                    ),
                  ]),
            ),
          );
        },
      );
}

// ===== صندوق الإرسال: رسائل ما وصلت بسبب الإنترنت تنعاد لحالها =====

class _Pending {
  _Pending(this.row);
  final Map<String, dynamic> row;
  bool sending = false;
}

/// لكل محادثة (تبقى لو طلعت من المحادثة ورجعت)
final _outboxes = <String, List<_Pending>>{};

class _PendingBubble extends StatelessWidget {
  const _PendingBubble({required this.p, required this.onRetry, required this.onDrop});
  final _Pending p;
  final VoidCallback onRetry;
  final VoidCallback onDrop;

  @override
  Widget build(BuildContext context) => Align(
        alignment: AlignmentDirectional.centerStart,
        child: GestureDetector(
          onTap: p.sending ? null : onRetry,
          onLongPress: onDrop,
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 3),
            padding: const EdgeInsets.fromLTRB(14, 9, 10, 9),
            constraints: BoxConstraints(
                maxWidth: MediaQuery.sizeOf(context).width * 0.75),
            decoration: BoxDecoration(
              color: const Color(0x400A84FF),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0x66FFFFFF)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Flexible(
                child: Text('${p.row['body'] ?? ''}',
                    style: const TextStyle(fontSize: _Fs.title, color: Colors.white)),
              ),
              const SizedBox(width: _Sp.sm),
              p.sending
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 1.6))
                  : const Icon(Icons.error_outline_rounded,
                      size: 18, color: Color(0xFFFFB340)),
            ]),
          ),
        ),
      );
}

class _PendingNote extends StatelessWidget {
  const _PendingNote();

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.only(bottom: 4),
        child: Text('ما وصلت بعد، راح نعيد إرسالها لحالها. اضغط عليها تعيدها الحين، ومطوّل تلغيها.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: _Fs.caption, color: Color(0xB3FFFFFF))),
      );
}

// ===== نسخة محلية من آخر الرسائل: المحادثة تفتح فوراً حتى بدون إنترنت =====

class _MsgCache {
  static Future<File> _file(String chatId) async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/msgs_$chatId.json');
  }

  static Future<List<Map<String, dynamic>>?> load(String chatId) async {
    try {
      final f = await _file(chatId);
      if (!await f.exists()) return null;
      return (jsonDecode(await f.readAsString()) as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    } catch (_) {
      return null;
    }
  }

  static Future<void> save(String chatId, List<Map<String, dynamic>> rows) async {
    try {
      await (await _file(chatId)).writeAsString(jsonEncode(rows.take(60).toList()));
    } catch (_) {}
  }

  static Future<void> clear(String chatId) async {
    try {
      final f = await _file(chatId);
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  /// عند الخروج أو حذف الحساب أو فك الارتباط: نمسح كل النسخ المحلية
  static Future<void> clearAll() async {
    _outboxes.clear();
    _drafts.clear();
    await _HomeWidgets.clear();
    await _MediaFiles.clearAll();
    try {
      final dir = await getApplicationSupportDirectory();
      await for (final e in dir.list()) {
        final name = e.uri.pathSegments.isEmpty ? '' : e.uri.pathSegments.last;
        if (e is File &&
            (name.startsWith('msgs_') || name.startsWith('hidden_'))) {
          await e.delete();
        }
      }
    } catch (_) {}
  }
}

extension _ChatNet on _ChatState {
  List<_Pending> get _outbox => _outboxes[widget.chat.id] ??= [];

  void _queueOutbox(Map<String, dynamic> row) {
    setState(() => _outbox.add(_Pending(row)));
    _scheduleOutbox();
  }

  void _scheduleOutbox() {
    _outboxTimer?.cancel();
    if (_outbox.isEmpty) return;
    _outboxTimer =
        Timer(const Duration(seconds: 12), () => unawaited(_flushOutbox()));
  }

  Future<void> _flushOutbox() async {
    final box = _outbox;
    for (final p in [...box]) {
      if (p.sending) continue;
      if (mounted) setState(() => p.sending = true);
      try {
        await _db.from('messages').insert(p.row);
        box.remove(p);
      } on PostgrestException catch (e) {
        box.remove(p); // السيرفر رفضها، ما نعيدها
        // 23505 = وصلت من قبل (الرسالة سليمة)، ما نعتبرها فشل
        if (e.code != '23505' && mounted) {
          _toast(context, _friendlyError(e, fallback: 'رسالة ما انقبلت من السيرفر وانلغت.'));
        }
      } catch (_) {
        p.sending = false;
        break; // بعده ما في إنترنت
      }
      if (mounted) setState(() {});
    }
    if (mounted) setState(() {});
    _scheduleOutbox();
  }

  void _dropPending(_Pending p) {
    setState(() => _outbox.remove(p));
    _c.text = '${p.row['body'] ?? ''}';
    _toast(context, 'انلغت، ورجّعنا النص لمربع الكتابة.');
  }

  /// يضيف الرسائل المعلّقة بأسفل المحادثة
  void _addPending(List<Object> entries) {
    final box = _outbox;
    if (box.isEmpty) return;
    entries.insert(0, const _PendingNote());
    for (final p in box) {
      entries.insert(0, p);
    }
  }

  Future<void> _loadMsgCache() async {
    final rows = await _MsgCache.load(widget.chat.id);
    if (rows != null && mounted) setState(() => _cachedRows = rows);
  }

  /// يحفظ آخر الرسائل بالجوال لما يتغير آخر رقم
  void _saveMsgCache(List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) {
      if (_cacheTop != -1) {
        _cacheTop = -1;
        unawaited(_MsgCache.clear(widget.chat.id));
      }
      return;
    }
    _cachedRows = rows; // آخر نسخة بالذاكرة (لو انعاد الاشتراك تطلع فوراً)
    final top = (rows.first['id'] as num?)?.toInt();
    if (top == null || top == _cacheTop) return;
    _cacheTop = top;
    unawaited(_MsgCache.save(widget.chat.id, rows));
  }
}

// ===== شرح الصلاحية قبل ما نطلبها (أول مرة بس) =====

Future<bool> _explainOnce(BuildContext context,
    {required String key,
    required IconData icon,
    required String title,
    required String text}) async {
  final File flag;
  try {
    final dir = await getApplicationSupportDirectory();
    flag = File('${dir.path}/explained_$key');
    if (await flag.exists()) return true;
  } catch (_) {
    return true;
  }
  if (!context.mounted) return false;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: Icon(icon, size: 40),
      title: Text(title, textAlign: TextAlign.center),
      content: Text(text, textAlign: TextAlign.center),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('مو الحين')),
        TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('تمام')),
      ],
    ),
  );
  if (ok == true) {
    try {
      await flag.writeAsString('1');
    } catch (_) {}
  }
  return ok == true;
}

// ===== تلميح أول مرة لكل ميزة =====

Future<void> _tipOnce(BuildContext context, String key, String text) async {
  try {
    final dir = await getApplicationSupportDirectory();
    final f = File('${dir.path}/tip_$key');
    if (await f.exists()) return;
    await f.writeAsString('1');
  } catch (_) {
    return;
  }
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Row(children: [
      const Text('💡 ', style: TextStyle(fontSize: _Fs.heading)),
      Expanded(child: Text(text)),
    ]),
    duration: const Duration(seconds: 7),
    action: SnackBarAction(label: 'تمام', onPressed: () {}),
  ));
}

// ===== تنبيه بالنسخة الجديدة (لنسخة APK اللي من GitHub بس، مو نسخة المتجر) =====

const _buildNo = int.fromEnvironment('BUILD_NO');
const _sideload = bool.fromEnvironment('SIDELOAD');
final _messengerKey = GlobalKey<ScaffoldMessengerState>();

Future<void> _checkForUpdate() async {
  if (!_sideload || _buildNo == 0) return;
  try {
    final dir = await getApplicationSupportDirectory();
    final f = File('${dir.path}/update_check');
    final today = _dayStr(DateTime.now());
    if (await f.exists() && (await f.readAsString()) == today) return;
    await f.writeAsString(today);
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
    try {
      final req = await client
          .getUrl(Uri.parse(
              'https://api.github.com/repos/gsiabskxkxjx/chat7/releases/latest'))
          .timeout(const Duration(seconds: 8));
      req.headers.set('Accept', 'application/vnd.github+json');
      final res = await req.close().timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return;
      final body = await res.transform(utf8.decoder).join();
      final j = jsonDecode(body) as Map<String, dynamic>;
      final tag = '${j['tag_name'] ?? ''}';
      final n = int.tryParse(tag.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
      if (n <= _buildNo) return;
      String? apk;
      for (final a in (j['assets'] as List? ?? const [])) {
        final name = '${(a as Map)['name']}';
        if (name.endsWith('.apk')) apk = '${a['browser_download_url']}';
      }
      final link = apk ?? '${j['html_url'] ?? ''}';
      if (link.isEmpty) return;
      _messengerKey.currentState?.showSnackBar(SnackBar(
        content: const Text('نسخة جديدة من بيناتنا متوفرة'),
        duration: const Duration(seconds: 12),
        action: SnackBarAction(
            label: 'تنزيل', onPressed: () => unawaited(_openUrl(null, link))),
      ));
    } finally {
      client.close(force: true);
    }
  } catch (_) {}
}


// ===== تنظيف ملفات الوسائط اليتيمة (مرة باليوم لكل محادثة) =====

/// الملفات اللي انرفعت وما انرسلت لها رسالة (رفع انقطع). السيرفر يحدد اليتيم (أقدم من يومين)،
/// والتطبيق يحذفه. أي خطأ نتجاهله، وما يأثر على المحادثة.
Future<void> _cleanOrphanMedia(String chatId) async {
  try {
    final dir = await getApplicationSupportDirectory();
    final flag = File('${dir.path}/orphan_clean_$chatId');
    final today = _dayStr(DateTime.now());
    if (await flag.exists() && (await flag.readAsString()).trim() == today) return;
    final r = await _db.rpc('orphan_media', params: {'p_chat': chatId});
    if (r is List && r.isNotEmpty) {
      final names = r.map((e) => '$e').where((n) => n.startsWith('$chatId/')).toList();
      for (var i = 0; i < names.length; i += 50) {
        await _db.storage
            .from('chat-media')
            .remove(names.sublist(i, i + 50 > names.length ? names.length : i + 50));
      }
    }
    await flag.writeAsString(today);
  } catch (_) {}
}
