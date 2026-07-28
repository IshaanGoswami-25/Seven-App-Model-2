import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  static Future<void> init() async {
    tz.initializeTimeZones();
    
    try {
      tz.setLocalLocation(tz.getLocation('Asia/Kolkata'));
    } catch (_) {
      try {
        tz.setLocalLocation(tz.getLocation('UTC'));
      } catch (_) {}
    }

    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/launcher_icon');

    const DarwinInitializationSettings iosSettings =
        DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const InitializationSettings initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _notificationsPlugin.initialize(
      initSettings,
    );
  }

  static Future<void> requestPermissions() async {
    final AndroidFlutterLocalNotificationsPlugin? androidImplementation =
        _notificationsPlugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    
    if (androidImplementation != null) {
      await androidImplementation.requestNotificationsPermission();
      try {
        await androidImplementation.requestExactAlarmsPermission();
      } catch (_) {}
    }
  }

  // Cancel all scheduled notifications to prevent duplicates
  static Future<void> cancelAllNotifications() async {
    await _notificationsPlugin.cancelAll();
  }

  // Schedule a weekly notification 5 minutes before the class start time
  static Future<void> scheduleClassNotification({
    required String id,
    required String subject,
    required String room,
    required String weekday, // e.g. "Monday", "Tuesday", etc.
    required String timeString, // e.g. "09.25" (24-hour format)
  }) async {
    // 1. Parse hour and minute from timeString
    final parts = timeString.split('.');
    if (parts.length != 2) return;
    
    int hour = int.parse(parts[0]);
    int minute = int.parse(parts[1]);

    // 2. Subtract 5 minutes for the alert offset
    int targetHour = hour;
    int targetMinute = minute - 5;
    
    if (targetMinute < 0) {
      targetHour -= 1;
      targetMinute += 60;
    }
    if (targetHour < 0) {
      targetHour += 24;
    }

    // Map weekday string to weekday int (1 = Monday, ..., 7 = Sunday)
    int targetWeekday = _mapWeekday(weekday);
    if (targetWeekday == 0) return;

    // Calculate the next occurrence of this weekday and time
    final tz.TZDateTime scheduledDate = _nextInstanceOfWeekdayTime(targetWeekday, targetHour, targetMinute);

    final int notificationId = id.hashCode;

    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'class_schedule_channel',
      'Class Schedule Alerts',
      channelDescription: 'Alerts sent 5 minutes before classes start',
      importance: Importance.max,
      priority: Priority.high,
      styleInformation: BigTextStyleInformation(''),
    );

    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const NotificationDetails platformDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notificationsPlugin.zonedSchedule(
      notificationId,
      'Upcoming Class: $subject',
      'Room: $room starts in 5 minutes!',
      scheduledDate,
      platformDetails,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
    );
  }

  static int _mapWeekday(String weekday) {
    switch (weekday.toLowerCase()) {
      case 'monday': return DateTime.monday;
      case 'tuesday': return DateTime.tuesday;
      case 'wednesday': return DateTime.wednesday;
      case 'thursday': return DateTime.thursday;
      case 'friday': return DateTime.friday;
      case 'saturday': return DateTime.saturday;
      case 'sunday': return DateTime.sunday;
      default: return 0;
    }
  }

  static tz.TZDateTime _nextInstanceOfWeekdayTime(int dayOfWeek, int hour, int minute) {
    final tz.TZDateTime now = tz.TZDateTime.now(tz.local);
    tz.TZDateTime scheduledDate = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    
    // If the scheduled time has already passed today, or the day of week is different, increment day by day
    while (scheduledDate.weekday != dayOfWeek || scheduledDate.isBefore(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }
    return scheduledDate;
  }
}
