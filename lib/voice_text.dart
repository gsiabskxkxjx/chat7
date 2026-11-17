part of 'main.dart';

// ---------- تحويل الرسالة الصوتية لنص ----------
// الصوت يروح لدالة سيرفر (transcribe) تحوّله بخدمة Groq Whisper. النتيجة تنحفظ عندك بس.

Future<File> _trFile() async =>
    File('${(await getApplicationSupportDirectory()).path}/transcripts.json');

Future<Map<String, dynamic>> _readTranscripts() async {
  try {
    final f = await _trFile();
    if (await f.exists()) {
      final d = jsonDecode(await f.readAsString());
      if (d is Map<String, dynamic>) return d;
    }
  } catch (_) {}
  return <String, dynamic>{};
}

Future<void> _saveTranscript(int id, String text) async {
  try {
    final m = await _readTranscripts();
    m['$id'] = text;
    if (m.length > 200) {
      // نحتفظ بآخر 200 بس
      final keys = m.keys.toList()..sort((a, b) => int.parse(a).compareTo(int.parse(b)));
      for (final k in keys.take(m.length - 200)) {
        m.remove(k);
      }
    }
    await (await _trFile()).writeAsString(jsonEncode(m));
  } catch (_) {}
}

/// لوحة Supabase تسمّي الدالة أحياناً smart-transcribe: نجرّب الاسمين
Future<dynamic> _callTranscribe(Map<String, dynamic> body) async {
  for (final name in const ['smart-transcribe', 'transcribe']) {
    try {
      final r = await _db.functions.invoke(name, body: body);
      return r.data;
    } on FunctionException catch (e) {
      if (e.status != 404) rethrow;
    }
  }
  throw FunctionException(status: 404);
}

extension _ChatVoiceText on _ChatState {
  Future<void> _transcribe(Msg m) async {
    final path = m.mediaPath;
    if (path == null) return;
    final cached = (await _readTranscripts())['${m.id}'];
    if (cached is String) {
      if (mounted) await _showTranscript(cached);
      return;
    }
    if (!mounted) return;
    final ok = await _explainOnce(context,
        key: 'transcribe',
        icon: Icons.subtitles_rounded,
        title: 'تحويل الصوت لنص',
        text:
            'الرسالة الصوتية تنرسل لخدمة تحويل خارجية (Groq) حتى تتحول لنص، ولا تنحفظ عندهم. النتيجة تنحفظ بجوالك بس. تحب نكمل؟');
    if (!ok || !mounted) return;
    unawaited(showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    ));
    String? text;
    String? err;
    try {
      final d = await _callTranscribe(
          {'chat_id': widget.chat.id, 'path': path, 'language': 'ar'});
      if (d is Map && d['text'] is String) {
        text = d['text'] as String;
      } else {
        err = 'تعذر التحويل.';
      }
    } on FunctionException catch (e) {
      err = e.status == 404
          ? 'الخدمة غير مفعّلة بعد على السيرفر.'
          : e.status == 501
              ? 'الخدمة تحتاج مفتاح، وما انضاف بعد.'
              : e.status == 429
                  ? 'كثرت الطلبات، جرّب بعد شوي.'
                  : e.status == 413
                      ? 'الرسالة طويلة كثير.'
                      : 'تعذر التحويل.';
    } catch (_) {
      err = 'تعذر التحويل، تأكد من الإنترنت.';
    }
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop(); // نغلق دائرة الانتظار
    if (text == null) {
      _toast(context, err ?? 'تعذر التحويل.');
      return;
    }
    if (text.isNotEmpty) await _saveTranscript(m.id, text);
    if (mounted) {
      await _showTranscript(text.isEmpty ? 'ما قدرنا نسمع كلام واضح.' : text);
    }
  }

  Future<void> _showTranscript(String text) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('نص الرسالة'),
        content: SingleChildScrollView(child: SelectableText(text)),
        actions: [
          if (text.length > 60)
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                unawaited(_aiSummarizeText(text));
              },
              child: const Text('لخّص'),
            ),
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: text));
              if (ctx.mounted) Navigator.pop(ctx);
              if (mounted) _toast(context, 'تم النسخ');
            },
            child: const Text('نسخ'),
          ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إغلاق')),
        ],
      ),
    );
  }
}
