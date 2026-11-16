part of 'main.dart';

// ---------- إعدادات محلية على الجوال: حجم خط المحادثة، تذكير "ما رديت"، مدة القفل، الخط العربي ----------

class _Prefs {
  static final fontScale = ValueNotifier<double>(1.0);
  static final remindHours = ValueNotifier<int>(2); // 0 = مطفي
  static final lockAfterSec = ValueNotifier<int>(30);
  static final arabicFont = ValueNotifier<bool>(true);

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
