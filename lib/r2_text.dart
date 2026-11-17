part of 'main.dart';

// ---------- الجولة الثانية: نص الفقاعة ----------
// روابط وأرقام وبريد قابلة للضغط (223)، تنسيق خفيف (228)، اتجاه صحيح للنص المختلط (272)

/// اتجاه النص حسب أول حرف: لاتيني = يسار لليمين
TextDirection _dirOf(String s) {
  for (final r in s.runes) {
    if ((r >= 0x41 && r <= 0x5A) || (r >= 0x61 && r <= 0x7A)) return TextDirection.ltr;
    if ((r >= 0x0600 && r <= 0x06FF) || (r >= 0x0750 && r <= 0x077F)) return TextDirection.rtl;
  }
  return TextDirection.rtl;
}

final _fmtRe = RegExp(
    r'(\*[^*\n]{1,300}\*)|(?<![A-Za-z0-9])(_[^_\n]{1,300}_)(?![A-Za-z0-9])|(~[^~\n]{1,300}~)|(https?://[^\s]+)|([\w.+-]+@[\w-]+\.[\w.-]+)|(\+\d[\d \-]{8,14}\d|(?<![\d-])0\d[\d \-]{8,12}\d)');

class _RichMsgText extends StatefulWidget {
  const _RichMsgText({required this.text, required this.style, required this.linkColor});
  final String text;
  final TextStyle style;
  final Color linkColor;

  @override
  State<_RichMsgText> createState() => _RichMsgTextState();
}

class _RichMsgTextState extends State<_RichMsgText> {
  final _recs = <TapGestureRecognizer>[];

  @override
  void dispose() {
    for (final r in _recs) {
      r.dispose();
    }
    super.dispose();
  }

  Future<void> _open(String raw, int kind) async {
    final Uri u;
    if (kind == 4) {
      u = Uri.parse(raw);
    } else if (kind == 5) {
      u = Uri(scheme: 'mailto', path: raw);
    } else {
      u = Uri(scheme: 'tel', path: raw.replaceAll(RegExp(r'[ \-]'), ''));
    }
    try {
      await launchUrl(u, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    for (final r in _recs) {
      r.dispose();
    }
    _recs.clear();
    final spans = <InlineSpan>[];
    var last = 0;
    final t = widget.text;
    for (final m in _fmtRe.allMatches(t)) {
      if (m.start > last) spans.add(TextSpan(text: t.substring(last, m.start)));
      final s = m.group(0)!;
      if (m.group(1) != null) {
        spans.add(TextSpan(text: s.substring(1, s.length - 1), style: const TextStyle(fontWeight: FontWeight.w800)));
      } else if (m.group(2) != null) {
        spans.add(TextSpan(text: s.substring(1, s.length - 1), style: const TextStyle(fontStyle: FontStyle.italic)));
      } else if (m.group(3) != null) {
        spans.add(TextSpan(text: s.substring(1, s.length - 1), style: const TextStyle(decoration: TextDecoration.lineThrough)));
      } else {
        final kind = m.group(4) != null ? 4 : (m.group(5) != null ? 5 : 6);
        final rec = TapGestureRecognizer()..onTap = () => unawaited(_open(s, kind));
        _recs.add(rec);
        spans.add(TextSpan(
            text: s,
            recognizer: rec,
            style: TextStyle(color: widget.linkColor, decoration: TextDecoration.underline, decorationColor: widget.linkColor)));
      }
      last = m.end;
    }
    if (last < t.length) spans.add(TextSpan(text: t.substring(last)));
    return Text.rich(TextSpan(style: widget.style, children: spans), textDirection: _dirOf(t));
  }
}
