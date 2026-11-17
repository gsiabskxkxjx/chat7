part of 'main.dart';

// ---------- "الجديد في بيناتنا" (مرة وحدة بعد كل تحديث كبير) ----------

const _whatsNewKey = 'whatsnew_0_13';

const _whatsNew = [
  ('📞', 'مكالمات أقوى', 'ترجع لحالها لو تغيّرت الشبكة، تحوّلها لفيديو، ونافذة عائمة'),
  ('🪟', 'رأس زجاجي', 'الرسائل تنزل تحت رأس المحادثة وهو يغبّشها'),
  ('🎞️', 'ضغط الفيديو', 'الفيديو الكبير ينضغط قبل الإرسال، أسرع وأوفر للإنترنت'),
  ('📝', 'صوت إلى نص', 'اضغط مطولاً على رسالة صوتية ثم «حوّلها لنص»'),
  ('✅', 'توثيق الرقم', 'عبر تلغرام من إعدادات الحساب، وتظهر علامة التوثيق للطرف الثاني'),
  ('🎨', 'أيقونة التطبيق', 'خمس ألوان تختارها من التخصيص'),
  ('🔔', 'إشعارات أوضح', 'عدد الرسائل الجديدة، ونبّهني لما يصير متصل'),
  ('☀️', 'ثيمات فاتحة', 'صارت النصوص واضحة بالثيمات الفاتحة'),
];

Future<void> _maybeWhatsNew(BuildContext context) async {
  try {
    final dir = await getApplicationSupportDirectory();
    final f = File('${dir.path}/$_whatsNewKey');
    if (await f.exists()) return;
    await f.writeAsString('1');
    // أول تثبيت (ما شاف التعريف قبل)؟ ما نعرض "الجديد"
    if (!await File('${dir.path}/onboarding_seen').exists()) return;
  } catch (_) {
    return;
  }
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.8),
        child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(20, 0, 20, 20), children: [
          const Text('الجديد في بيناتنا ✨',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: _Sp.xs),
          const Text('كلها من زر 🎮 بجنب مربع الكتابة، ومن ➕',
              textAlign: TextAlign.center, style: TextStyle(color: Color(0xB3FFFFFF))),
          const SizedBox(height: 14),
          for (final w in _whatsNew)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(w.$1, style: const TextStyle(fontSize: 26)),
                const SizedBox(width: _Sp.md),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(w.$2, style: const TextStyle(fontSize: _Fs.title, fontWeight: FontWeight.w700)),
                    Text(w.$3, style: const TextStyle(fontSize: _Fs.meta, color: Color(0xCCFFFFFF))),
                  ]),
                ),
              ]),
            ),
          const SizedBox(height: 6),
          _Btn(label: 'يلا نجرّب', onTap: () => Navigator.pop(ctx)),
        ]),
      ),
    ),
  );
}
