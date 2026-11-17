part of 'main.dart';

// ---------- ويدجت الشاشة الرئيسية، اختصارات الأيقونة، إشعار المكالمة الجارية ----------

// ===== ويدجت: عدّاد الأيام + آخر «أفكر فيك»، وصورة من ذكرياتكم =====

/// البيانات تنكتب بملف widget.json (نفس مجلد التطبيق)، والويدجت (كود أندرويد) يقراها.
class _HomeWidgets {
  static const _ch = MethodChannel('bainatna/widgets');
  static Map<String, dynamic>? _cache;

  static Future<File> _file() async =>
      File('${(await getApplicationSupportDirectory()).path}/widget.json');

  static Future<void> _save(Map<String, String?> data, String widget) async {
    try {
      final f = await _file();
      final cur = _cache ??= await f.exists()
          ? Map<String, dynamic>.from(jsonDecode(await f.readAsString()) as Map)
          : <String, dynamic>{};
      var changed = false;
      for (final e in data.entries) {
        if (cur[e.key] != e.value) {
          cur[e.key] = e.value;
          changed = true;
        }
      }
      if (!changed) return;
      await f.writeAsString(jsonEncode(cur));
      await _ch.invokeMethod<void>('refresh', {'widget': widget});
    } catch (_) {}
  }

  static Future<void> days(DateTime start, String partner) => _save({
        'start_ms': '${DateTime(start.year, start.month, start.day).millisecondsSinceEpoch}',
        'partner': partner,
      }, 'DaysWidget');

  static Future<void> think(DateTime at) =>
      _save({'think': '❤️ آخر «أفكر فيك» ${_clockOf(at)}'}, 'DaysWidget');

  static DateTime? _photoDay;

  /// صورة عشوائية من آخر 60 صورة (مرة باليوم)
  static Future<void> photo(String chatId) async {
    final today = _today();
    if (_photoDay == today) return;
    _photoDay = today;
    try {
      final rows = await _db
          .from('messages')
          .select('media_path')
          .eq('chat_id', chatId)
          .eq('kind', 'image')
          .order('id', ascending: false)
          .limit(60);
      final paths = [for (final r in rows) if (r['media_path'] != null) '${r['media_path']}'];
      if (paths.isEmpty) return;
      final f = await _MediaFiles.get(paths[Random().nextInt(paths.length)]);
      if (f == null) return;
      final dir = await getApplicationSupportDirectory();
      final out = await f.copy('${dir.path}/widget_photo.img');
      await _save({'photo': out.path, 'photo_v': '${DateTime.now().millisecondsSinceEpoch}'}, 'PhotoWidget');
    } catch (_) {}
  }

  static Future<void> clear() async {
    await _save({'start_ms': null, 'partner': null, 'think': null}, 'DaysWidget');
    await _save({'photo': null}, 'PhotoWidget');
    await _save({'next_ms': null, 'next_title': null, 'need': null}, 'NextWidget');
  }
}

// ===== اختصارات الضغط المطوّل على أيقونة التطبيق =====

void _setupShortcuts() {
  try {
    const qa = QuickActions();
    unawaited(qa.initialize((type) {
      if (type == 'think') unawaited(_shortcutThink());
    }));
    unawaited(qa.setShortcutItems(const [
      ShortcutItem(type: 'think', localizedTitle: 'أفكر فيك ❤️'),
      ShortcutItem(type: 'open', localizedTitle: 'افتح المحادثة'),
    ]));
  } catch (_) {}
}

/// يرسل «أفكر فيك» بدون ما تدخل المحادثة
Future<void> _shortcutThink() async {
  for (var i = 0; i < 20 && _db.auth.currentUser == null; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }
  final uid = _db.auth.currentUser?.id;
  if (uid == null) return;
  try {
    final c = await _db
        .from('chats')
        .select('id')
        .or('user_a.eq.$uid,user_b.eq.$uid')
        .limit(1)
        .maybeSingle();
    if (c == null) return;
    await _db.from('messages').insert({'chat_id': c['id'], 'kind': 'think', 'body': '❤️ أفكر فيك'});
    _messengerKey.currentState?.showSnackBar(const SnackBar(content: Text('وصله «أفكر فيك» ❤️')));
  } catch (_) {}
}

// ===== إشعار المكالمة الجارية (إنهاء وكتم من الإشعار) =====

const _ongoingId = 9002;
CallSession? _liveCall;

Future<void> _showOngoing(CallSession s) async {
  try {
    await _callNotifier.show(
      _ongoingId,
      s.video ? 'مكالمة فيديو جارية' : 'مكالمة جارية',
      s.muted.value ? 'المايك مكتوم' : 'اضغط ترجع للمكالمة',
      NotificationDetails(
        android: AndroidNotificationDetails(
          'call_ongoing',
          'المكالمة الجارية',
          channelDescription: 'يظهر وقت المكالمة حتى ترجع لها أو تنهيها',
          importance: Importance.low,
          priority: Priority.low,
          ongoing: true,
          autoCancel: false,
          onlyAlertOnce: true,
          usesChronometer: true,
          when: (s.connectedAt ?? DateTime.now()).millisecondsSinceEpoch,
          category: AndroidNotificationCategory.call,
          actions: <AndroidNotificationAction>[
            AndroidNotificationAction('call_mute', s.muted.value ? 'إلغاء الكتم' : 'كتم',
                showsUserInterface: true, cancelNotification: false),
            AndroidNotificationAction('call_end', 'إنهاء',
                showsUserInterface: true, cancelNotification: true),
          ],
        ),
      ),
    );
  } catch (_) {}
}

Future<void> _hideOngoing() async {
  try {
    await _callNotifier.cancel(_ongoingId);
  } catch (_) {}
}

/// أزرار الإشعارات لما التطبيق شغّال
void _fgNotifResponse(NotificationResponse r) {
  final s = _liveCall;
  if (s == null) return;
  if (r.actionId == 'call_end') {
    unawaited(s.hangup());
  } else if (r.actionId == 'call_mute') {
    s.toggleMute();
    unawaited(_showOngoing(s));
  }
}

String _qualityLabel(double rtt, double loss) {
  if (rtt < 0.25 && loss < 0.02) return '📶 ممتاز';
  if (rtt < 0.6 && loss < 0.08) return '📶 متوسط';
  return '📶 ضعيف';
}

// ===== نافذة عائمة لمكالمة الفيديو (Picture in Picture) =====

final _inPip = ValueNotifier<bool>(false);
const _pipCh = MethodChannel('bainatna/pip');
bool _pipListening = false;

/// يسمح للتطبيق يصغر لنافذة عائمة لما تطلع منه وقت مكالمة فيديو
Future<void> _allowPip(bool on) async {
  if (!_pipListening) {
    _pipListening = true;
    _pipCh.setMethodCallHandler((call) async {
      if (call.method == 'pip') _inPip.value = call.arguments == true;
    });
  }
  try {
    await _pipCh.invokeMethod<void>('enable', on);
  } catch (_) {}
  if (!on) _inPip.value = false;
}

// ===== عدد الرسائل غير المقروءة على الإشعار =====

Future<File> _unreadFile() async =>
    File('${(await getApplicationSupportDirectory()).path}/unread_count');

Future<int> _bumpUnread() async {
  try {
    final f = await _unreadFile();
    var n = 0;
    if (await f.exists()) n = int.tryParse(await f.readAsString()) ?? 0;
    n++;
    await f.writeAsString('$n');
    return n;
  } catch (_) {
    return 1;
  }
}

/// لما تفتح المحادثة: نصفّر العداد ونشيل إشعارات الرسائل
Future<void> _clearUnread(String chatId) async {
  try {
    final f = await _unreadFile();
    if (await f.exists()) await f.delete();
  } catch (_) {}
  try {
    if (chatId.length >= 7) await _callNotifier.cancel(_msgNotifId(chatId));
  } catch (_) {}
}

// ===== «صار متصل» =====

/// نخبر الطرف الثاني إني فتحت التطبيق (السيرفر يقرر: لو هو مفعّلها، ومرة كل 3 ساعات)
Future<void> _pingOnline() async {
  try {
    await _db.rpc('ping_online');
  } catch (_) {}
}

class _OnlineAlertTile extends StatefulWidget {
  const _OnlineAlertTile();

  @override
  State<_OnlineAlertTile> createState() => _OnlineAlertTileState();
}

class _OnlineAlertTileState extends State<_OnlineAlertTile> {
  bool? _on; // null = السيرفر ما فيه الإعداد بعد

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) return;
    try {
      final r = await _db.from('profiles').select('notify_online').eq('id', uid).maybeSingle();
      if (mounted) setState(() => _on = r?['notify_online'] == true);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final on = _on;
    if (on == null) return const SizedBox.shrink();
    return SwitchListTile(
      value: on,
      title: const Text('نبّهني لما يصير متصل'),
      subtitle: const Text('إشعار لما يفتح التطبيق، مرة كل 3 ساعات بالكثير'),
      onChanged: (v) async {
        setState(() => _on = v);
        try {
          await _db
              .from('profiles')
              .update({'notify_online': v}).eq('id', _db.auth.currentUser!.id);
        } catch (_) {
          if (!mounted) return;
          setState(() => _on = !v);
          _toast(context, 'تعذر حفظ الإعداد.');
        }
      },
    );
  }
}
