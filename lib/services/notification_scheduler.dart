import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

/// Schedules a zoned notification using exact allow-while-idle mode when the
/// platform permits it, falling back to inexact mode when exact alarms are
/// rejected (e.g. missing `SCHEDULE_EXACT_ALARM` on Android 12+).
Future<void> zonedScheduleWithExactFallback({
  required FlutterLocalNotificationsPlugin plugin,
  required int id,
  required String title,
  required String body,
  required tz.TZDateTime scheduledDate,
  required NotificationDetails notificationDetails,
  String? payload,
}) async {
  try {
    await plugin.zonedSchedule(
      id: id,
      title: title,
      body: body,
      scheduledDate: scheduledDate,
      notificationDetails: notificationDetails,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      payload: payload,
    );
  } catch (e) {
    debugPrint('Exact scheduling failed ($e), falling back to inexact');
    await plugin.zonedSchedule(
      id: id,
      title: title,
      body: body,
      scheduledDate: scheduledDate,
      notificationDetails: notificationDetails,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      payload: payload,
    );
  }
}