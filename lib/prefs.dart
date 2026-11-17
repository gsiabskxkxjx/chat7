part of 'main.dart';

// ---------- إعدادات محلية على الجوال: حجم خط المحادثة، تذكير "ما رديت"، مدة القفل، الخط العربي ----------

class _Prefs {
  static final fontScale = ValueNotifier<double>(1.0);
  static final remindHours = ValueNotifier<int>(2); // 0 = مطفي
  static final lockAfterSec = ValueNotifier<int>(30);
  static final arabicFont = ValueNotifier<bool>(true);
  static final lowFx = ValueNotifier<bool>(false); // تخفيف التمويه والحركات
  static final linkPreviews = ValueNotifier<bool>(true);
  static final autoSave = ValueNotifier<bool>(false); // حفظ صور الطرف الثاني بالمعرض
  static final quiet = ValueNotifier<int>(-1); // وضع النوم: البداية*100+النهاية، -1 مطفي
  static final buzz = ValueNotifier<bool>(false); // اهتزاز مميز لرسائل الطرف الثاني
  static final bubbleShape = ValueNotifier<int>(0); // 0 مدوّرة، 1 حادة، 2 كبسولة
  static final myBubble = ValueNotifier<int>(-1); // -1 لون الثيم
  static final theirBubble = ValueNotifier<int>(-1);
  static final ring = ValueNotifier<int>(0); // إطار صورة الطرف الثاني
  static final crashReports = ValueNotifier<bool>(true);
  static final animBg = ValueNotifier<int>(0); // خلفية متحركة بالمحادثة
  static final autoDayNight = ValueNotifier<bool>(false); // ثيم فاتح بالنهار وغامق بالليل
  static final dailyReminder = ValueNotifier<int>(-1); // ساعة تذكير سؤال اليوم، -1 مطفي

  /// داخل ساعات وضع النوم؟
  static bool inQuiet([DateTime? at]) {
    final v = quiet.value;
    if (v < 0) return false;
    final s = v ~/ 100, e = v % 100, h = (at ?? DateTime.now()).hour;
    return s < e ? (h >= s && h < e) : (h >= s || h < e);
  }
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
      linkPreviews.value = m['linkPreviews'] as bool? ?? true;
      autoSave.value = m['autoSave'] as bool? ?? false;
      quiet.value = (m['quiet'] as num?)?.toInt() ?? -1;
      buzz.value = m['buzz'] as bool? ?? false;
      bubbleShape.value = (m['bubbleShape'] as num?)?.toInt() ?? 0;
      myBubble.value = (m['myBubble'] as num?)?.toInt() ?? -1;
      theirBubble.value = (m['theirBubble'] as num?)?.toInt() ?? -1;
      ring.value = (m['ring'] as num?)?.toInt() ?? 0;
      crashReports.value = m['crashReports'] as bool? ?? true;
      animBg.value = (m['animBg'] as num?)?.toInt() ?? 0;
      autoDayNight.value = m['autoDayNight'] as bool? ?? false;
      dailyReminder.value = (m['dailyReminder'] as num?)?.toInt() ?? -1;
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
        'linkPreviews': linkPreviews.value,
        'autoSave': autoSave.value,
        'quiet': quiet.value,
        'buzz': buzz.value,
        'bubbleShape': bubbleShape.value,
        'myBubble': myBubble.value,
        'theirBubble': theirBubble.value,
        'ring': ring.value,
        'crashReports': crashReports.value,
        'animBg': animBg.value,
        'autoDayNight': autoDayNight.value,
        'dailyReminder': dailyReminder.value,
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
        padding: const EdgeInsets.symmetric(vertical: _Sp.xs),
        child: Column(children: [
          _choice<double>('حجم خط المحادثة', Icons.format_size_rounded,
              _Prefs.fontScale, const [
            (0.9, 'صغير'),
            (1.0, 'عادي'),
            (1.15, 'كبير'),
            (1.3, 'أكبر'),
          ]),
          _choice<int>('شكل الفقاعات', Icons.chat_bubble_outline_rounded,
              _Prefs.bubbleShape, const [
            (0, 'مدوّرة'),
            (1, 'حادة'),
            (2, 'كبسولة'),
          ]),
          ListTile(
            leading: const Icon(Icons.format_color_fill_rounded),
            title: const Text('لون فقاعاتي وفقاعاته'),
            subtitle: const Text('يتغير عندك بس'),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              _dot(_Prefs.myBubble.value),
              const SizedBox(width: _Sp.xs),
              _dot(_Prefs.theirBubble.value),
            ]),
            onTap: () async {
              await _pickBubbleColors(context);
              if (mounted) setState(() {});
            },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.brightness_6_rounded),
            title: const Text('نهار وليل تلقائي'),
            subtitle: const Text('ثيم فاتح بالنهار وغامق بالليل (عندك بس)'),
            value: _Prefs.autoDayNight.value,
            onChanged: (x) {
              setState(() => _Prefs.autoDayNight.value = x);
              unawaited(_Prefs.save());
              _startAppLook();
            },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.phone_android_rounded),
            title: const Text('يتبع وضع الجوال'),
            subtitle: const Text('فاتح أو غامق حسب إعداد أندرويد (يتفوق على النهار والليل)'),
            value: _R2Store.get<bool>('followSystem') == true,
            onChanged: (x) async {
              await _R2Store.set('followSystem', x);
              if (mounted) setState(() {});
              _startAppLook();
            },
          ),
          ListTile(
            leading: const Icon(Icons.alarm_rounded),
            title: const Text('تذكير سؤال اليوم'),
            trailing: DropdownButton<int>(
              value: _Prefs.dailyReminder.value,
              underline: const SizedBox.shrink(),
              borderRadius: BorderRadius.circular(16),
              items: const [
                DropdownMenuItem(value: -1, child: Text('مطفي')),
                DropdownMenuItem(value: 10, child: Text('10 الصبح')),
                DropdownMenuItem(value: 14, child: Text('2 الظهر')),
                DropdownMenuItem(value: 20, child: Text('8 بالليل')),
                DropdownMenuItem(value: 22, child: Text('10 بالليل')),
              ],
              onChanged: (x) async {
                if (x == null) return;
                setState(() => _Prefs.dailyReminder.value = x);
                await _Prefs.save();
                await _scheduleDailyReminder();
              },
            ),
          ),
          _choice<int>('خلفية متحركة بالمحادثة', Icons.auto_awesome_rounded,
              _Prefs.animBg, [
            for (var i = 0; i < _particleNames.length; i++) (i, _particleNames[i]),
          ]),
          _choice<int>('إطار صورته بالمحادثة', Icons.account_circle_rounded,
              _Prefs.ring, [
            for (var i = 0; i < _ringStyles.length; i++) (i, _ringStyles[i]),
          ]),
          _choice<int>('تذكير «ما رديت»', Icons.notifications_active_rounded,
              _Prefs.remindHours, const [
            (0, 'مطفي'),
            (1, 'بعد ساعة'),
            (2, 'بعد ساعتين'),
            (6, 'بعد 6 ساعات'),
          ]),
          _choice<int>('وضع النوم (إشعارات بدون صوت)', Icons.bedtime_rounded,
              _Prefs.quiet, const [
            (-1, 'مطفي'),
            (2207, '10م إلى 7ص'),
            (2308, '11م إلى 8ص'),
            (8, '12ص إلى 8ص'),
            (109, '1ص إلى 9ص'),
          ]),
          SwitchListTile(
            secondary: const Icon(Icons.vibration_rounded),
            title: const Text('اهتزاز مميز لرسائله'),
            subtitle: const Text('تعرف إنها منه بدون ما تشوف الجوال'),
            value: _Prefs.buzz.value,
            onChanged: (x) {
              setState(() => _Prefs.buzz.value = x);
              unawaited(_Prefs.save());
            },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.save_alt_rounded),
            title: const Text('حفظ صوره بالمعرض تلقائياً'),
            subtitle: const Text('الصور اللي توصلك وأنت فاتح المحادثة'),
            value: _Prefs.autoSave.value,
            onChanged: (x) {
              setState(() => _Prefs.autoSave.value = x);
              unawaited(_Prefs.save());
            },
          ),
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
          SwitchListTile(
            secondary: const Icon(Icons.link_rounded),
            title: const Text('معاينة الروابط'),
            subtitle: const Text('يجيب عنوان وصورة الرابط من موقعه'),
            value: _Prefs.linkPreviews.value,
            onChanged: (x) {
              setState(() => _Prefs.linkPreviews.value = x);
              _linkCache.clear();
              unawaited(_Prefs.save());
            },
          ),
          ListTile(
            leading: const Icon(Icons.add_reaction_rounded),
            title: const Text('التفاعلات السريعة'),
            subtitle: Text(_Prefs.reactions.value.join('  '),
                style: const TextStyle(fontSize: _Fs.heading)),
            onTap: () async {
              await _pickReactions(context);
              if (mounted) setState(() {});
            },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.bug_report_rounded),
            title: const Text('إرسال تقارير الأعطال'),
            subtitle: const Text('نوع الخطأ بس، بدون رسائلك'),
            value: _Prefs.crashReports.value,
            onChanged: (x) {
              setState(() => _Prefs.crashReports.value = x);
              unawaited(_Prefs.save());
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
          const _AppIconTile(),
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
            const SizedBox(height: _Sp.md),
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
                    child: Text(e, style: const TextStyle(fontSize: _Fs.big)),
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

Widget _dot(int i) => Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: i < 0 ? null : _bubblePalette[i % _bubblePalette.length],
        gradient: i < 0
            ? const LinearGradient(colors: [Color(0xFF0A84FF), Color(0xFFFF5FA2)])
            : null,
        border: Border.all(color: Colors.white54),
      ),
    );

Future<void> _pickBubbleColors(BuildContext context) => showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) {
          Widget row(String title, ValueNotifier<int> v) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: _Sp.sm),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    for (var i = -1; i < _bubblePalette.length; i++)
                      GestureDetector(
                        onTap: () {
                          set(() => v.value = i);
                          unawaited(_Prefs.save());
                        },
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: v.value == i ? Colors.white : Colors.transparent,
                                width: 2),
                          ),
                          child: Transform.scale(scale: 1.5, child: _dot(i)),
                        ),
                      ),
                  ]),
                ],
              );
          return AlertDialog(
            title: const Text('ألوان الفقاعات'),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              row('فقاعاتي (أول دائرة = لون الثيم)', _Prefs.myBubble),
              const SizedBox(height: _Sp.lg),
              row('فقاعاته', _Prefs.theirBubble),
            ]),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('تم')),
            ],
          );
        },
      ),
    );

const _dailyReminderId = 9100;

/// تذكير يومي محلي: "سؤال اليوم بانتظارك" بالساعة اللي تختارها
Future<void> _scheduleDailyReminder() async {
  try {
    await _callNotifier.cancel(_dailyReminderId);
    final h = _Prefs.dailyReminder.value;
    if (h < 0) return;
    tz_data.initializeTimeZones();
    final now = DateTime.now();
    var at = DateTime(now.year, now.month, now.day, h);
    if (!at.isAfter(now)) at = at.add(const Duration(days: 1));
    await _callNotifier.zonedSchedule(
      _dailyReminderId,
      'سؤال اليوم بانتظارك 💬',
      'جاوب وشوف جوابه، ولا تقطع سلسلتكم 🔥',
      tz.TZDateTime.from(at.toUtc(), tz.UTC),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'daily',
          'تذكير سؤال اليوم',
          channelDescription: 'تذكير مرة باليوم',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  } catch (_) {}
}
