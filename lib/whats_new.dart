part of 'main.dart';

// ---------- "الجديد في بيناتنا" (مرة وحدة بعد كل تحديث كبير) ----------

const _whatsNewKey = 'whatsnew_0_12';

const _whatsNew = [
  ('🎮', 'ألعاب جديدة', 'مين فينا، صح أو غلط، 20 سؤال، الذاكرة، داما وشطرنج'),
  ('💞', 'سوا', 'جدار الحب، تحدي الصورة اليومي، تقويم، يوميات وميزانية'),
  ('📸', 'ذكرياتكم', 'قصتنا، ألبومات، وملخص الشهر كصورة'),
  ('⭕', 'رسائل أحلى', 'فيديو دائري، بطاقات ملوّنة، تصويت، ملصقات، ونبضة صوت'),
  ('🖼️', 'تعديل الصور', 'فلاتر وتدوير وقص قبل الإرسال'),
  ('📱', 'ويدجت', 'عدّاد أيامكم وصورة من ذكرياتكم على الشاشة الرئيسية'),
  ('🔗', 'ربط أسهل', 'رابط و QR للدعوة، وينربط الحساب لحاله'),
  ('⚙️', 'تخصيص', 'لون وشكل الفقاعات، خلفية متحركة، وضع النوم، نهار وليل تلقائي'),
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
          const SizedBox(height: 4),
          const Text('كلها من زر 🎮 بجنب مربع الكتابة، ومن ➕',
              textAlign: TextAlign.center, style: TextStyle(color: Color(0xB3FFFFFF))),
          const SizedBox(height: 14),
          for (final w in _whatsNew)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(w.$1, style: const TextStyle(fontSize: 26)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(w.$2, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                    Text(w.$3, style: const TextStyle(fontSize: 13, color: Color(0xCCFFFFFF))),
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
