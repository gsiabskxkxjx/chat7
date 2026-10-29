part of 'main.dart';

// ---------- إشعار المكالمة الواردة بشاشة كاملة (والتطبيق مسكّر) ----------

const _callNotifId = 9001;

final FlutterLocalNotificationsPlugin _callNotifier =
    FlutterLocalNotificationsPlugin();

Future<void> _initCallNotifier() async {
  await _callNotifier.initialize(const InitializationSettings(
    android: AndroidInitializationSettings('@mipmap/ic_launcher'),
  ));
}

/// يُستدعى بالخلفية لما توصل رسالة مكالمة (حتى لو التطبيق مسكّر)
@pragma('vm:entry-point')
Future<void> _bgCallMessage(RemoteMessage message) async {
  if (message.data['type'] != 'call') return;
  try {
    if (Firebase.apps.isEmpty) await Firebase.initializeApp();
    await _initCallNotifier();
    await _callNotifier.show(
      _callNotifId,
      message.data['title'] ?? 'بيناتنا',
      message.data['body'] ?? 'مكالمة واردة',
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
      payload: message.data['chat'],
    );
  } catch (_) {}
}

/// يلغي إشعار المكالمة (لما تفتح شاشة المكالمة داخل التطبيق)
Future<void> _cancelCallNotif() async {
  try {
    await _callNotifier.cancel(_callNotifId);
  } catch (_) {}
}
