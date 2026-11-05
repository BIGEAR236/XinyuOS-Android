import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'models.dart';

/// Offline scheduler: only generic reminders are scheduled while the app is
/// closed. No LLM keys or user messages are given to Android AlarmManager.
/// The real AI-generated follow-up happens in AppController when app resumes.
class ProactiveNotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  static int _id(String input) {
    var hash = 17;
    for (final code in input.codeUnits) {
      hash = (hash * 31 + code) & 0x7fffffff;
    }
    return hash;
  }

  static Future<void> initialize() async {
    if (_ready) return;
    tzdata.initializeTimeZones();
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(
        requestSoundPermission: false,
        requestAlertPermission: false,
        requestBadgePermission: false));
    await _plugin.initialize(settings);
    _ready = true;
  }

  static Future<bool> requestPermission() async {
    await initialize();
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) return await android.requestNotificationsPermission() ?? false;
    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) {
      return await ios.requestPermissions(alert: true, sound: true, badge: true) ?? false;
    }
    return true;
  }

  static Future<void> schedule(ProactiveEvent event, String characterName) async {
    await initialize();
    if (!event.dueAt.isAfter(DateTime.now())) return;
    // UTC represents the absolute instant selected with the phone's local
    // date/time picker. This avoids asking for the user's IANA timezone.
    final moment = tz.TZDateTime.from(event.dueAt.toUtc(), tz.UTC);
    await _plugin.zonedSchedule(
      _id(event.id), '心屿 · 事件提醒',
      '有一条事件提醒，打开应用后查看。',
      moment,
      const NotificationDetails(android: AndroidNotificationDetails(
        'xinyu_proactive_v1', '心屿事件关怀',
        channelDescription: '经用户许可的角色事件提醒',
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority)),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle);
  }

  static Future<void> cancel(String id) async {
    await initialize();
    await _plugin.cancel(_id(id));
  }
}
