part of 'main.dart';

// ---------- ردود سريعة: تضغط وتنرسل مباشرة ----------

const _quickTexts = <String>[
  'تمام 👍',
  'وينك؟',
  'أحبك ❤️',
  'اشتقتلك',
  'صباح الخير ☀️',
  'تصبح على خير 🌙',
  'انتظرني',
  'ضحكتني 😂',
  'شكراً',
  'لا تنسى!',
];

Future<void> _sendQuick(BuildContext context, String chatId, String text) async {
  try {
    await _db.from('messages').insert({'chat_id': chatId, 'body': text});
  } catch (_) {
    if (context.mounted) _toast(context, 'تعذر الإرسال، جرّب مرة ثانية.');
  }
}

void showQuickReplies(BuildContext context, String chatId) {
  showModalBottomSheet<void>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: [
            for (final t in _quickTexts)
              ActionChip(
                label: Text(t, style: const TextStyle(fontSize: 15)),
                onPressed: () {
                  Navigator.pop(ctx);
                  _sendQuick(context, chatId, t);
                },
              ),
          ],
        ),
      ),
    ),
  );
}
