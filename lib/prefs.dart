part of 'main.dart';

// ---------- إعدادات محلية على الجوال: حجم خط المحادثة، تذكير "ما رديت"، مدة القفل، الخط العربي ----------

class _Prefs {
  static final fontScale = ValueNotifier<double>(1.0);
  static final remindHours = ValueNotifier<int>(2); // 0 = مطفي
  static final lockAfterSec = ValueNotifier<int>(30);
  static final arabicFont = ValueNotifier<bool>(true);
  static final lowFx = ValueNotifier<bool>(false); // تخفيف التمويه والحركات
  static const defaultReactions = ['👍', '😂', '😮', '😢', '🙏', '🔥'];
  static final reactions = ValueNotifier<List<String>>(defaultReactions);

  static Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/prefs.json');
  }

  static Future<void> load() async {
    try {
      final f = await _file();
      if (!await f.exists()) return;
      final m = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      fontScale.value = (m['fontScale'] as num?)?.toDouble() ?? 1.0;
      remindHours.value = (m['remindHours'] as num?)?.toInt() ?? 2;
      lockAfterSec.value = (m['lockAfterSec'] as num?)?.toInt() ?? 30;
      arabicFont.value = m['arabicFont'] as bool? ?? true;
      lowFx.value = m['lowFx'] as bool? ?? false;
      final r = (m['reactions'] as List?)?.map((e) => '$e').toList();
      if (r != null && r.length >= 3 && r.length <= 6) reactions.value = r;
    } catch (_) {}
  }

  static Future<void> save() async {
    try {
      final f = await _file();
      await f.writeAsString(jsonEncode({
        'fontScale': fontScale.value,
        'remindHours': remindHours.value,
        'lockAfterSec': lockAfterSec.value,
        'arabicFont': arabicFont.value,
        'lowFx': lowFx.value,
        'reactions': reactions.value,
      }));
    } catch (_) {}
  }
}

/// قسم "تخصيص" بشاشة الملف الشخصي
class _PrefsCard extends StatefulWidget {
  const _PrefsCard();

  @override
  State<_PrefsCard> createState() => _PrefsCardState();
}

class _PrefsCardState extends State<_PrefsCard> {
  Widget _choice<T>(String title, IconData icon, ValueNotifier<T> v,
          List<(T, String)> options) =>
      ListTile(
        leading: Icon(icon),
        title: Text(title),
        trailing: DropdownButton<T>(
          value: v.value,
          underline: const SizedBox.shrink(),
          borderRadius: BorderRadius.circular(16),
          items: [
            for (final o in options)
              DropdownMenuItem<T>(value: o.$1, child: Text(o.$2)),
          ],
          onChanged: (x) {
            if (x == null) return;
            setState(() => v.value = x);
            unawaited(_Prefs.save());
          },
        ),
      );

  @override
  Widget build(BuildContext context) => Glass(
        radius: 28,
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(children: [
          _choice<double>('حجم خط المحادثة', Icons.format_size_rounded,
              _Prefs.fontScale, const [
            (0.9, 'صغير'),
            (1.0, 'عادي'),
            (1.15, 'كبير'),
            (1.3, 'أكبر'),
          ]),
          _choice<int>('تذكير «ما رديت»', Icons.notifications_active_rounded,
              _Prefs.remindHours, const [
            (0, 'مطفي'),
            (1, 'بعد ساعة'),
            (2, 'بعد ساعتين'),
            (6, 'بعد 6 ساعات'),
          ]),
          _choice<int>('القفل بعد الخروج', Icons.lock_clock_rounded,
              _Prefs.lockAfterSec, const [
            (0, 'فوراً'),
            (30, '30 ثانية'),
            (60, 'دقيقة'),
            (300, '5 دقايق'),
            (900, '15 دقيقة'),
          ]),
          SwitchListTile(
            secondary: const Icon(Icons.speed_rounded),
            title: const Text('تخفيف المؤثرات'),
            subtitle: const Text('أسرع وأوفر للبطارية بالأجهزة القديمة'),
            value: _Prefs.lowFx.value,
            onChanged: (x) {
              setState(() => _Prefs.lowFx.value = x);
              unawaited(_Prefs.save());
            },
          ),
          ListTile(
            leading: const Icon(Icons.add_reaction_rounded),
            title: const Text('التفاعلات السريعة'),
            subtitle: Text(_Prefs.reactions.value.join('  '),
                style: const TextStyle(fontSize: 18)),
            onTap: () async {
              await _pickReactions(context);
              if (mounted) setState(() {});
            },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.font_download_rounded),
            title: const Text('الخط العربي الحديث'),
            subtitle: const Text('يتحمّل من الإنترنت أول مرة'),
            value: _Prefs.arabicFont.value,
            onChanged: (x) {
              setState(() => _Prefs.arabicFont.value = x);
              unawaited(_Prefs.save());
            },
          ),
        ]),
      );
}

const _reactionPool = [
  '👍', '❤️', '😂', '😮', '😢', '🙏', '🔥', '😍', '🥰', '😘', '🤍', '💔',
  '😡', '😴', '🤔', '👏', '🎉', '💯', '😎', '🙈', '🤣', '😭', '🥺', '😅',
  '👀', '✨', '🌹', '☕', '🤝', '👌',
];

/// اختيار التفاعلات اللي تطلع بالضغط المطوّل (3 إلى 6)
Future<void> _pickReactions(BuildContext context) async {
  var cur = [..._Prefs.reactions.value];
  final res = await showDialog<List<String>>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => AlertDialog(
        title: const Text('التفاعلات السريعة'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('اختر من 3 إلى 6 (${cur.length}/6)',
                style: const TextStyle(color: Color(0xAAFFFFFF))),
            const SizedBox(height: 12),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final e in _reactionPool)
                _Press(
                  onTap: () => set(() {
                    if (cur.contains(e)) {
                      cur = [...cur]..remove(e);
                    } else if (cur.length < 6) {
                      cur = [...cur, e];
                    }
                  }),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 46,
                    height: 46,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: cur.contains(e)
                          ? const Color(0x660A84FF)
                          : const Color(0x14FFFFFF),
                      border: Border.all(
                          color: cur.contains(e)
                              ? const Color(0xFF7CC0FF)
                              : const Color(0x33FFFFFF)),
                    ),
                    child: Text(e, style: const TextStyle(fontSize: 24)),
                  ),
                ),
            ]),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () =>
                  set(() => cur = [..._Prefs.defaultReactions]),
              child: const Text('الافتراضي')),
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          TextButton(
              onPressed: cur.length < 3 ? null : () => Navigator.pop(ctx, cur),
              child: const Text('حفظ')),
        ],
      ),
    ),
  );
  if (res == null) return;
  _Prefs.reactions.value = res;
  await _Prefs.save();
}
