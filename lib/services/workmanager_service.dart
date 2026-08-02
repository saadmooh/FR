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
import 'ai_proxy_service.dart';

const String _monitoringTaskName = 'reminder_monitoring_task';
const String _notificationChannelId = 'flex_reminders_channel';
const String _notificationChannelName = 'Smart Pocket';
const String _notificationChannelDescription = 'Smart post reading reminders';

Map<String, dynamic> _parseAiRescheduleResponse(String content) {
  debugPrint('Parsing AI response: $content');
  
  if (content.isEmpty) {
    throw Exception('AI returned empty response');
  }
  
  String jsonStr = content;
  if (content.contains('```')) {
    final codeBlockMatch = RegExp(r'```(?:json)?\s*([\s\S]*?)```').firstMatch(content);
    if (codeBlockMatch != null) {
      jsonStr = codeBlockMatch.group(1) ?? content;
    }
  }
  
  final jsonMatch = RegExp(r'\{[\s\S]*\}').firstMatch(jsonStr);
  if (jsonMatch != null) {
    final data = json.decode(jsonMatch.group(0)!);
    final newTime = DateTime.tryParse(data['new_time'] ?? '');
    if (newTime == null) {
      debugPrint('Failed to parse new_time: ${data['new_time']}');
      throw Exception('Invalid new_time format: ${data['new_time']}');
    }
    debugPrint('Successfully parsed newTime: $newTime, reason: ${data['reason']}');
    return {
      'newTime': newTime,
      'reason': data['reason'] ?? '',
    };
  }
  throw Exception('No JSON found in response');
}

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
  const maxRetries = 5;
  const retryDelay = Duration(seconds: 30);

  for (int attempt = 0; attempt < maxRetries; attempt++) {
    try {
      if (directoryPath != null && directoryPath.isNotEmpty) {
        final dir = Directory(directoryPath);
        if (await dir.exists()) {
          // Clean up stale lock file if app was force-killed
          final lockFile = File('$directoryPath/lock.mdb');
          if (await lockFile.exists()) {
            debugPrint('Found stale lock file, removing...');
            await lockFile.delete();
          }
          debugPrint('Opening store at: $directoryPath (attempt ${attempt + 1})');
          return openStore(directory: directoryPath);
        }
      }
      debugPrint('Opening store with default directory (attempt ${attempt + 1})');
      return openStore();
    } catch (e) {
      if (e.toString().contains('another store is still open') && attempt < maxRetries - 1) {
        debugPrint('Store locked, waiting for release... (attempt ${attempt + 1}/$maxRetries)');
        await Future.delayed(retryDelay);
      } else {
        debugPrint('Failed to open store: $e');
        rethrow;
      }
    }
  }
  throw Exception('Failed to open store after $maxRetries attempts');
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
  final aiProxy = AiProxyService.fromConfig();
  return AIService(settingsRepo, aiProxy: aiProxy);
}

Future<void> _initNotificationsInBackground() async {
  final plugin = FlutterLocalNotificationsPlugin();
  
  await plugin.initialize(
    settings: const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    ),
  );

  final androidPlugin = plugin.resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>();
  
  if (androidPlugin != null) {
    const channel = AndroidNotificationChannel(
      _notificationChannelId,
      _notificationChannelName,
      description: _notificationChannelDescription,
      importance: Importance.high,
      enableVibration: true,
      playSound: true,
    );
    await androidPlugin.createNotificationChannel(channel);
    debugPrint('Notification channel created in background');
  }
}

@pragma('vm:entry-point')
Future<void> _workmanagerCallback() async {
  debugPrint('WorkManager callback started');
  
  Workmanager().executeTask((taskName, inputData) async {
    debugPrint('WorkManager task: $taskName, inputData: $inputData');
    
    if (taskName != _monitoringTaskName) {
      debugPrint('Unknown task name: $taskName');
      return true;
    }

    final reminderIdStr = inputData?['reminderId'] as String?;
    if (reminderIdStr == null) {
      debugPrint('No reminderId in inputData');
      return true;
    }
    
    final reminderId = int.tryParse(reminderIdStr);
    if (reminderId == null) {
      debugPrint('Invalid reminderId: $reminderIdStr');
      return true;
    }

    final storeDirectoryPath = inputData?['storeDirectory'] as String?;
    final apiKey = inputData?['apiKey'] as String?;
    final provider = inputData?['provider'] as String? ?? 'google';
    final model = inputData?['model'] as String? ?? '';

    debugPrint('API Key present: ${apiKey != null && apiKey.isNotEmpty}');
    debugPrint('Provider: $provider');
    debugPrint('Model: $model');

    Store? store;
    try {
      debugPrint('Initializing timezone...');
      tz_data.initializeTimeZones();
      tz.setLocalLocation(tz.local);

      if (apiKey == null || apiKey.isEmpty) {
        debugPrint('No API key available in WorkManager task');
        return true;
      }

      debugPrint('Creating AI service...');
      final aiService = await _createAIService(
        apiKey: apiKey,
        provider: provider,
        model: model,
      );

      debugPrint('Initializing notifications...');
      await _initNotificationsInBackground();

      debugPrint('Opening store...');
      store = await _openStoreInBackground(storeDirectoryPath);
      
      final reminderRepo = ReminderRepository(store);
      final freeTimeRepo = FreeTimeRepository(store);

      debugPrint('Fetching reminder $reminderId...');
      final reminder = reminderRepo.getById(reminderId);
      if (reminder == null) {
        debugPrint('Reminder $reminderId not found');
        store.close();
        return true;
      }
      
      if (reminder.isOpened) {
        debugPrint('Reminder $reminderId already opened');
        store.close();
        return true;
      }

      final maxReschedules = _getMaxReschedules(reminder.importance);
      if (reminder.rescheduleAttempts >= maxReschedules) {
        debugPrint('Reminder $reminderId reached max reschedules ($maxReschedules)');
        store.close();
        return true;
      }

      final now = DateTime.now();
      if (reminder.scheduledAt.isBefore(now.subtract(const Duration(days: 30)))) {
        debugPrint('Reminder $reminderId is too old (>30 days)');
        store.close();
        return true;
      }

      debugPrint('Getting reminder history...');
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

      debugPrint('Getting free times...');
      final freeTimes = freeTimeRepo.getAllAsJson();
      debugPrint('Free times count: ${freeTimes.length}');

      debugPrint('Calling AI for reschedule...');
      debugPrint('Calling with - category: ${reminder.categoryEn}, complexity: ${reminder.complexityEn}, importance: ${reminder.importance}');
      
      String rawResponse;
      try {
        rawResponse = await aiService.reschedulePostRaw(
          previousAttemptsJson: jsonEncode(previousAttempts),
          category: reminder.categoryEn ?? 'Other',
          complexity: reminder.complexityEn ?? 'Medium',
          importance: reminder.importance,
          userFreeTimesJson: freeTimes.isNotEmpty 
              ? '{"free_times": $freeTimes}'
              : null,
        );
      } catch (e) {
        debugPrint('AI call failed: $e');
        store.close();
        return true;
      }
      
      debugPrint('Raw AI response: $rawResponse');
      
      Map<String, dynamic> aiResult;
      try {
        aiResult = _parseAiRescheduleResponse(rawResponse);
      } catch (e) {
        debugPrint('Failed to parse AI response: $e, using fallback');
        // Use fallback - keep same time, just increment attempts
        final newTime = reminder.scheduledAt.add(const Duration(hours: 1));
        aiResult = {
          'newTime': newTime,
          'reason': 'AI response parse failed, rescheduled by 1 hour',
        };
      }
      
      debugPrint('Parsed AI result: $aiResult');
      
      final newTime = aiResult['newTime'] as DateTime?;
      if (newTime == null || !newTime.isAfter(now)) {
        debugPrint('AI returned invalid new time: $newTime');
        store.close();
        return true;
      }

      debugPrint('Updating reminder with new time: $newTime');
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
      debugPrint('Reminder saved successfully');

      debugPrint('Scheduling new notification...');
      final plugin = FlutterLocalNotificationsPlugin();
      await plugin.zonedSchedule(
        id: reminderId,
        title: ' Time to read: ${reminder.title}',
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
            color: const Color(0xFF22C55E),
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
      debugPrint('Notification scheduled successfully');

      debugPrint('Rescheduling WorkManager task...');
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
        initialDelay: const Duration(minutes: 1),
        inputData: nextInputData,
        tag: 'reminder_$reminderId',
      );
      debugPrint('WorkManager task rescheduled');

      final formattedTime = '${newTime.hour.toString().padLeft(2, '0')}:${newTime.minute.toString().padLeft(2, '0')}';
      final successBody = '${reminder.title}\nNew time: $formattedTime\n${reminder.aiExplanation}';
      await plugin.show(
        id: reminderId + 1000000,
        title: 'Reminder Rescheduled',
        body: successBody,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            _notificationChannelId,
            _notificationChannelName,
            channelDescription: _notificationChannelDescription,
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
            icon: '@mipmap/ic_launcher',
            color: const Color(0xFF22C55E),
            enableVibration: false,
            playSound: false,
          ),
        ),
      );

      debugPrint('Closing store...');
      store.close();
      debugPrint('WorkManager task completed successfully');
      return true;
    } catch (e, stackTrace) {
      debugPrint('WorkManager monitoring callback failed: $e');
      debugPrint('Stack trace: $stackTrace');
      try {
        store?.close();
        debugPrint('Store closed after error');
      } catch (_) {}
      // If app is in foreground, store is locked by main isolate.
      // Silently exit - monitoring is not needed since user is active.
      if (e.toString().contains('another store is still open')) {
        debugPrint('App is in foreground, skipping monitoring (user is active)');
        return true;
      }
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('last_ai_reschedule_error', e.toString());
        debugPrint('Error saved to preferences');
      } catch (_) {}
      try {
        final errorPlugin = FlutterLocalNotificationsPlugin();
        await errorPlugin.initialize(
          settings: const InitializationSettings(
            android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          ),
        );
        final androidPlugin = errorPlugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
        if (androidPlugin != null) {
          const channel = AndroidNotificationChannel(
            _notificationChannelId,
            _notificationChannelName,
            description: _notificationChannelDescription,
            importance: Importance.high,
            enableVibration: true,
            playSound: true,
          );
          await androidPlugin.createNotificationChannel(channel);
        }
        final errorText = e.toString().length > 100 ? '${e.toString().substring(0, 100)}...' : e.toString();
        await errorPlugin.show(
          id: reminderId + 2000000,
          title: 'Monitoring Failed',
          body: 'Reminder: $reminderId\nError: $errorText',
          notificationDetails: NotificationDetails(
            android: AndroidNotificationDetails(
              _notificationChannelId,
              _notificationChannelName,
              channelDescription: _notificationChannelDescription,
              importance: Importance.defaultImportance,
              priority: Priority.defaultPriority,
              icon: '@mipmap/ic_launcher',
              color: const Color(0xFFFF5252),
              enableVibration: false,
              playSound: false,
            ),
          ),
        );
      } catch (_) {}
      return true;
    }
  });
}

@pragma('vm:entry-point')
void callbackDispatcher() {
  debugPrint('WorkManager callback dispatcher called');
  _workmanagerCallback();
}
