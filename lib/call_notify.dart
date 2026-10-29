part of 'main.dart';

// ---------- الإشعارات: مكالمات بشاشة كاملة، ورسائل فيها زر رد ----------

const _callNotifId = 9001;

final FlutterLocalNotificationsPlugin _callNotifier =
    FlutterLocalNotificationsPlugin();

/// لازم يتسجل بدء التطبيق، ويتسجل بالخلفية (عشان زر الرد يشتغل والتطبيق مسكّر)
Future<void> _initCallNotifier() async {
  await _callNotifier.initialize(
    const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    ),
    onDidReceiveBackgroundNotificationResponse: _bgNotifResponse,
  );
}

/// رقم إشعار ثابت لكل محادثة (من أول 7 خانات من رقم المحادثة)
int _msgNotifId(String chat) =>
    int.parse(chat.replaceAll('-', '').substring(0, 7), radix: 16);

/// يُستدعى بالخلفية لما توصل رسالة أو مكالمة (حتى لو التطبيق مسكّر)
@pragma('vm:entry-point')
Future<void> _bgCallMessage(RemoteMessage message) async {
  final type = message.data['type'];
  if (type != 'call' && type != 'message') return;
  try {
    if (Firebase.apps.isEmpty) await Firebase.initializeApp();
    await _initCallNotifier();
    if (type == 'call') {
      await _showCall(message.data);
    } else {
      await _showMessage(message.data);
    }
  } catch (_) {}
}

Future<void> _showCall(Map<String, dynamic> data) async {
  await _callNotifier.show(
    _callNotifId,
    (data['title'] ?? 'بيناتنا').toString(),
    (data['body'] ?? 'مكالمة واردة').toString(),
    NotificationDetails(
      android: AndroidNotificationDetails(
        'calls',
        'المكالمات',
        channelDescription: 'إشعارات المكالمات الواردة',
        importance: Importance.max,
        priority: Priority.max,
        category: AndroidNotificationCategory.call,
        fullScreenIntent: true,
        ongoing: true,
        autoCancel: false,
        timeoutAfter: 45000,
        visibility: NotificationVisibility.public,
      ),
    ),
    payload: (data['chat'] ?? '').toString(),
  );
}

Future<void> _showMessage(Map<String, dynamic> data) async {
  final chat = (data['chat'] ?? '').toString();
  if (chat.length < 7) return;
  await _callNotifier.show(
    _msgNotifId(chat),
    (data['title'] ?? 'بيناتنا').toString(),
    (data['body'] ?? 'رسالة جديدة').toString(),
    NotificationDetails(
      android: AndroidNotificationDetails(
        'messages',
        'الرسائل',
        channelDescription: 'إشعارات الرسائل الجديدة',
        importance: Importance.high,
        priority: Priority.high,
        visibility: NotificationVisibility.private,
        actions: <AndroidNotificationAction>[
          AndroidNotificationAction(
            'reply',
            'رد',
            showsUserInterface: false,
            cancelNotification: false,
            inputs: <AndroidNotificationActionInput>[
              AndroidNotificationActionInput(label: 'اكتب ردك'),
            ],
          ),
        ],
      ),
    ),
    payload: chat,
  );
}

/// يرسل الرد من الإشعار مباشرة (بدون ما تفتح التطبيق)
@pragma('vm:entry-point')
Future<void> _bgNotifResponse(NotificationResponse r) async {
  if (r.actionId != 'reply') return;
  final text = (r.input ?? '').trim();
  final chat = r.payload ?? '';
  if (text.isEmpty || chat.length < 7) return;
  try {
    await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
    await Supabase.instance.client
        .from('messages')
        .insert({'chat_id': chat, 'body': text});
    await _callNotifier.cancel(_msgNotifId(chat));
  } catch (_) {}
}

/// يلغي إشعار المكالمة (لما تفتح شاشة المكالمة داخل التطبيق)
Future<void> _cancelCallNotif() async {
  try {
    await _callNotifier.cancel(_callNotifId);
  } catch (_) {}
}
