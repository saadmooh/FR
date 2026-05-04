import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:workmanager/workmanager.dart';
import '../repositories/reminder_repository.dart';
import '../repositories/free_time_repository.dart';
import '../repositories/app_settings_repository.dart';
import '../objectbox.g.dart';
import 'ai_service.dart';

const String _monitoringTaskName = 'reminder_monitoring_task';
const String _notificationChannelId = 'flex_reminders_channel';
const String _notificationChannelName = 'Smart Pocket';
const String _notificationChannelDescription = 'Smart post reading reminders';

int _getMaxReschedules(String importance) {
  switch (importance) {
    case 'Day':
      return 1;
    case 'Week':
      return 2;
    case 'Month':
      return 3;
    default:
      return 2;
  }
}

Future<Store> _openStoreInBackground(String? directoryPath) async {
  if (directoryPath != null && directoryPath.isNotEmpty) {
    try {
      final dir = Directory(directoryPath);
      if (await dir.exists()) {
        return openStore(directory: directoryPath);
      }
    } catch (e) {
      debugPrint('Failed to open store with provided directory: $e');
    }
  }

  return openStore();
}

Future<AIService> _createAIService({
  required String apiKey,
  required String provider,
  required String model,
}) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('ai_api_key', apiKey);
  await prefs.setString('ai_provider', provider);
  if (model.isNotEmpty) {
    await prefs.setString('ai_model', model);
  }
  final settingsRepo = AppSettingsRepository(prefs);
  return AIService(settingsRepo);
}

@pragma('vm:entry-point')
Future<void> _workmanagerCallback() async {
  Workmanager().executeTask((taskName, inputData) async {
    if (taskName != _monitoringTaskName) return true;

    final reminderIdStr = inputData?['reminderId'];
    if (reminderIdStr == null) return true;
    final reminderId = int.tryParse(reminderIdStr);
    if (reminderId == null) return true;

    final storeDirectoryPath = inputData?['storeDirectory'];
    final apiKey = inputData?['apiKey'];
    final provider = inputData?['provider'] ?? 'google';
    final model = inputData?['model'] ?? '';

    Store? store;
    try {
      tz_data.initializeTimeZones();
      tz.setLocalLocation(tz.local);

      if (apiKey == null || apiKey.isEmpty) {
        debugPrint('No API key available in WorkManager task');
        return true;
      }

      final aiService = await _createAIService(
        apiKey: apiKey,
        provider: provider,
        model: model,
      );

      store = await _openStoreInBackground(storeDirectoryPath);
      final reminderRepo = ReminderRepository(store);
      final freeTimeRepo = FreeTimeRepository(store);

      final reminder = reminderRepo.getById(reminderId);
      if (reminder == null || reminder.isOpened) {
        store.close();
        return true;
      }

      if (reminder.rescheduleAttempts >= _getMaxReschedules(reminder.importance)) {
        store.close();
        return true;
      }

      final now = DateTime.now();
      if (reminder.scheduledAt.isBefore(now.subtract(const Duration(days: 30)))) {
        store.close();
        return true;
      }

      final previousAttempts = reminderRepo
          .getReminderHistory(reminderId)
          .map(
            (r) => {
              'scheduled_at': r.scheduledAt.toIso8601String(),
              'opened': r.isOpened,
              'opened_at': r.openedAt?.toIso8601String(),
            },
          )
          .toList();

      final freeTimes = freeTimeRepo.getAllAsJson();

      final aiResult = await aiService.reschedulePost(
        previousAttemptsJson: jsonEncode(previousAttempts),
        category: reminder.categoryEn ?? 'Other',
        complexity: reminder.complexityEn ?? 'Medium',
        importance: reminder.importance,
        userFreeTimesJson: jsonEncode(freeTimes),
      );

      final newTime = aiResult['newTime'] as DateTime?;
      if (newTime == null || !newTime.isAfter(now)) {
        store.close();
        return true;
      }

      reminder.scheduledAt = newTime;
      reminder.rescheduleAttempts++;
      final reason = aiResult['reason'] as String? ?? '';
      final reasonParts = reason.split(' | ');
      reminder.aiExplanation =
          reasonParts.isNotEmpty ? reasonParts[0] : reason;
      reminder.aiExplanationAr =
          reasonParts.length > 1 ? reasonParts[1] : '';
      reminder.isOpened = false;
      reminder.openedAt = null;
      reminderRepo.save(reminder);

      final plugin = FlutterLocalNotificationsPlugin();
      await plugin.zonedSchedule(
        id: reminderId,
        title: '📖 Time to read: ${reminder.title}',
        body: '${reminder.categoryEn ?? "General"} · ${reminder.complexityAr ?? "متوسط"}',
        scheduledDate: tz.TZDateTime.from(reminder.scheduledAt, tz.local),
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            _notificationChannelId,
            _notificationChannelName,
            channelDescription: _notificationChannelDescription,
            importance: Importance.high,
            priority: Priority.high,
            icon: '@mipmap/ic_launcher',
            color: const Color(0xFF00D4C8),
            enableVibration: true,
            playSound: true,
            category: AndroidNotificationCategory.reminder,
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
            categoryIdentifier: 'REMINDER',
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: reminderId.toString(),
      );

      await Workmanager().cancelByTag('reminder_$reminderId');
      final nextInputData = <String, String>{
        'reminderId': reminderId.toString(),
        'provider': provider,
      };
      if (storeDirectoryPath != null) {
        nextInputData['storeDirectory'] = storeDirectoryPath;
      }
      if (apiKey.isNotEmpty) {
        nextInputData['apiKey'] = apiKey;
      }
      if (model.isNotEmpty) {
        nextInputData['model'] = model;
      }
      await Workmanager().registerOneOffTask(
        'reminder_monitoring_$reminderId',
        _monitoringTaskName,
        initialDelay: const Duration(minutes: 5),
        inputData: nextInputData,
        tag: 'reminder_$reminderId',
      );

      store.close();
      return true;
    } catch (e) {
      debugPrint('WorkManager monitoring callback failed: $e');
      try {
        store?.close();
      } catch (_) {}
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('last_ai_reschedule_error', e.toString());
      } catch (_) {}
      return true;
    }
  });
}

@pragma('vm:entry-point')
void callbackDispatcher() {
  _workmanagerCallback();
}
