part of 'main.dart';

// ---------- "الجديد في بيناتنا" (مرة وحدة بعد كل تحديث كبير) ----------

const _whatsNewKey = 'whatsnew_234';

const _whatsNew = [
  ('⚙️', 'إعدادات مرتبة', 'أقسام قابلة للطي مع بحث، والإجراءات الخطرة بقسم لحاله'),
  ('➕', 'صفحة «المزيد»', 'كل الميزات (ألعاب، ميزانية، يوميات، ألبومات...) بمكان واحد من زر ⋯'),
  ('🌿', 'الوضع البسيط', 'محادثة نظيفة بدون أزرار وتنبيهات إضافية، تفعّله من الإعدادات'),
  ('🔒', 'تشفير أوضح', 'علامة «مشفّرة» بالمحادثة، وشاشة بثلاث إشارات، ونسخ رمز الاسترجاع'),
  ('⬆️', 'تحديث وتشخيص', 'نافذة واضحة للنسخة الجديدة، وشاشة تفحص الاتصال والتشفير وترسل تقرير بدون رسائل'),
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
          const Text('كلها من زر ⋯ بجنب مربع الكتابة، ومن الإعدادات',
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
