import 'dart:convert';
import 'dart:ui' show IsolateNameServer;
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:objectbox_flutter_libs/objectbox_flutter_libs.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:workmanager/workmanager.dart';
import '../core/app_config.dart';
import '../repositories/reminder_repository.dart';
import '../repositories/free_time_repository.dart';
import '../repositories/app_settings_repository.dart';
import '../objectbox.g.dart';
import '../services/ai_service.dart';
import '../services/ai_proxy_service.dart';
import '../services/ai_reschedule_parser.dart';
import '../services/local_timezone.dart';
import '../services/notification_scheduler.dart';
import '../services/reschedule_lock_service.dart';
import '../services/reschedule_policy.dart';

const String _monitoringTaskName = 'reminder_monitoring_task';

/// Public hook so foreground code (e.g. OverdueReminderService) can schedule a
/// background retry of the AI rescheduling task after 30 minutes.
/// Uses the app's default store directory.
Future<void> scheduleAiRescheduleRetry(int reminderId) async {
  await _scheduleAiRetry(reminderId, null);
}

const String _notificationChannelId = 'flex_reminders_channel';
const String _notificationChannelName = 'Smart Pocket';
const String _notificationChannelDescription = 'Smart post reading reminders';
const String _uiLogQueueKey = 'bg_ui_log_queue';

bool _bgServicesInitialized = false;

/// Sends a message to the main isolate for SnackBar display via IsolateNameServer.
/// Falls back to SharedPreferences for cold start / resume scenarios.
Future<void> _queueUiLog(String message) async {
  final tagged = '[BG] $message';

  // Primary: send directly to main isolate via SendPort (instant)
  try {
    final sendPort = IsolateNameServer.lookupPortByName('bg_log_port');
    if (sendPort != null) {
      sendPort.send(tagged);
      debugPrint('[BG-PORT] Sent to main isolate: $message');
    } else {
      debugPrint(
        '[BG-PORT] SendPort not found, falling back to SharedPreferences',
      );
    }
  } catch (e) {
    debugPrint('[BG-PORT] Failed to send via port: $e');
  }

  // Fallback: also write to SharedPreferences (for cold start / resume)
  try {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getStringList(_uiLogQueueKey) ?? [];
    existing.add(tagged);
    if (existing.length > 50) {
      existing.removeRange(0, existing.length - 50);
    }
    await prefs.setStringList(_uiLogQueueKey, existing);
  } catch (e) {
    debugPrint('[QUEUE-UI] SharedPreferences write failed: $e');
  }
}

/// Helper to both debugPrint and queue for UI
Future<void> _log(String message) async {
  debugPrint(message);
  await _queueUiLog(message);
}

/// Remote logging to Supabase debug_logs table for WorkManager diagnostics.
/// This works independently of app state, SharedPreferences, or UI reopening.
Future<void> _remoteLog(String event, {Map<String, dynamic>? details}) async {
  try {
    // Initialize Supabase if not already done in this isolate
    final client = Supabase.instance.client;
    final session = client.auth.currentSession;
    if (session == null) {
      await Supabase.initialize(
        url: AppConfig.supabaseUrl,
        publishableKey: AppConfig.supabaseAnonKey,
      );
    }
    await Supabase.instance.client.from('debug_logs').insert([
      {'event': event, 'details': details ?? {}},
    ]);
  } catch (e) {
    // Swallow errors - this is diagnostic only, don't break the task
    debugPrint('[RemoteLog] Failed: $e');
  }
}

Future<void> _initBackgroundServices() async {
  // Required for SharedPreferences, Platform channels, and other Flutter bindings
  // in this background isolate (WorkManager runs in a separate isolate).
  // NOTE: WidgetsFlutterBinding.ensureInitialized() is already called in callbackDispatcher
  // as the very first line, before any platform channel usage.

  // Firebase is required for the Supabase session-restore fallback.
  if (!_bgServicesInitialized) {
    try {
      await Firebase.initializeApp();
      // Ensure auth state is loaded in this isolate before reading currentUser
      await firebase_auth.FirebaseAuth.instance.authStateChanges().first;
    } catch (_) {
      // Already initialized or unavailable.
    }
  }

  if (!AppConfig.isSupabaseConfigured) {
    await _log('⚠️ [Supabase] Not configured (missing --dart-define)');
    return;
  }

  if (!_bgServicesInitialized) {
    try {
      await Supabase.initialize(
        url: AppConfig.supabaseUrl,
        publishableKey: AppConfig.supabaseAnonKey,
      );
      await _log('✅ [Supabase] Initialized in background isolate');
    } catch (e) {
      await _log('⚠️ [Supabase] Init failed (may already be initialized): $e');
    }
  }

  // Supabase Flutter restores the session from local storage on init. If that
  // failed (box unavailable / expired), rebuild it from the Firebase user,
  // mirroring main.dart's cold-start restore (main.dart:124-137).
  try {
    final client = Supabase.instance.client;
    final existingSession = client.auth.currentSession;
    final sessionExpired =
        existingSession != null &&
        DateTime.fromMillisecondsSinceEpoch(
          existingSession.expiresAt! * 1000,
        ).isBefore(DateTime.now());

    await _log(
      '🔐 [Supabase] Session check: hasSession=${existingSession != null}, expired=$sessionExpired, userId=${existingSession?.user.id}',
    );

    if (existingSession == null || sessionExpired) {
      await _log(
        '🔄 [Supabase] Session missing/expired — attempting Firebase fallback...',
      );
      final firebaseUser = firebase_auth.FirebaseAuth.instance.currentUser;
      await _log(
        '👤 [Firebase] currentUser in isolate: ${firebaseUser != null ? "UID: ${firebaseUser.uid}" : "NULL"}',
      );

      if (firebaseUser != null) {
        final idToken = await firebaseUser.getIdToken();
        if (idToken != null) {
          await _log(
            '🔑 [Firebase] Got ID token (length: ${idToken.length}), signing into Supabase...',
          );
          await client.auth.signInWithIdToken(
            provider: OAuthProvider('custom:firebase'),
            idToken: idToken,
          );
          await _log(
            '✅ [Supabase] Session restored from Firebase successfully',
          );
          await _log(
            '👤 [Supabase] New session user: ${client.auth.currentSession?.user.id}',
          );
        } else {
          await _log('❌ [Firebase] Failed to get ID token');
        }
      } else {
        await _log(
          '❌ [Firebase] No Firebase user in this isolate — cannot restore Supabase session',
        );
      }
    } else {
      await _log('✅ [Supabase] Session already valid, no restore needed');
    }
  } catch (e, stackTrace) {
    await _log('❌ [Supabase] Session restore failed: $e');
    debugPrint('📋 Stack: $stackTrace');
  }

  _bgServicesInitialized = true;
}

Future<Store> _openStoreInBackground(String? directoryPath) async {
  await loadObjectBoxLibraryAndroidCompat();

  final dirPath = (directoryPath != null && directoryPath.isNotEmpty)
      ? directoryPath
      : (await defaultStoreDirectory()).path;

  if (Store.isOpen(dirPath)) {
    return Store.attach(getObjectBoxModel(), dirPath);
  } else {
    return openStore(directory: dirPath);
  }
}

/// Schedules the AI rescheduling task to retry after 30 minutes.
///
/// Used when the AI rescheduling failed for any reason. The reminder's
/// scheduled time is left unchanged; the same monitoring task is re-queued so
/// it attempts the AI reschedule again later.
Future<void> _scheduleAiRetry(
  int reminderId,
  String? storeDirectoryPath,
) async {
  final inputData = <String, String>{'reminderId': reminderId.toString()};
  if (storeDirectoryPath != null && storeDirectoryPath.isNotEmpty) {
    inputData['storeDirectory'] = storeDirectoryPath;
  }
  await Workmanager().registerOneOffTask(
    'reminder_monitoring_$reminderId',
    _monitoringTaskName,
    initialDelay: const Duration(minutes: 30),
    inputData: inputData,
    tag: 'reminder_$reminderId',
    existingWorkPolicy: ExistingWorkPolicy.keep,
  );
}

Future<AIService> _createAIService() async {
  final prefs = await SharedPreferences.getInstance();
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

  final androidPlugin = plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

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
void callbackDispatcher() {
  // CRITICAL: Must be the FIRST line - initializes binary messenger for this isolate
  // Before ANY platform channel usage (SharedPreferences, Supabase, etc.)
  WidgetsFlutterBinding.ensureInitialized();

  _workmanagerCallback();
}

@pragma('vm:entry-point')
Future<void> _workmanagerCallback() async {
  await _log('WorkManager callback started');

  Workmanager().executeTask((taskName, inputData) async {
    // Remote log: Task execution started (independent of local storage/UI)
    await _remoteLog(
      'workmanager_task_started',
      details: {'task': taskName, 'inputData': inputData},
    );

    await _log('WorkManager task: $taskName, inputData: $inputData');

    if (taskName != _monitoringTaskName) {
      await _log('Unknown task name: $taskName');
      return true;
    }

    final reminderIdStr = inputData?['reminderId'] as String?;
    if (reminderIdStr == null) {
      await _log('No reminderId in inputData');
      return true;
    }

    final reminderId = int.tryParse(reminderIdStr);
    if (reminderId == null) {
      await _log('Invalid reminderId: $reminderIdStr');
      return true;
    }

    final storeDirectoryPath = inputData?['storeDirectory'] as String?;

    Store? store;
    RescheduleLockService? lockService;
    try {
      await _log('Initializing background services...');
      await _initBackgroundServices();

      await _log('Initializing timezone...');
      await initLocalTimeZone();

      await _log('Creating AI service...');
      final aiService = await _createAIService();

      await _log('Initializing notifications...');
      await _initNotificationsInBackground();

      // Early check: if main app already has store open, skip this task
      // The main app's OverdueReminderService will handle overdue reminders on startup/resume.
      final dirPath = (storeDirectoryPath != null && storeDirectoryPath.isNotEmpty)
          ? storeDirectoryPath
          : (await defaultStoreDirectory()).path;
      if (Store.isOpen(dirPath)) {
        await _log('Main app has store open, skipping background reschedule');
        return true;
      }

      await _log('Opening store...');
      store = await _openStoreInBackground(storeDirectoryPath);

      final reminderRepo = ReminderRepository(store);
      final freeTimeRepo = FreeTimeRepository(store);

      await _log('Fetching reminder $reminderId...');
      final reminder = reminderRepo.getById(reminderId);
      if (reminder == null) {
        await _log('Reminder $reminderId not found');
        store.close();
        return true;
      }

      if (reminder.isOpened) {
        await _log(
          '✅ Reminder "${reminder.title}" was already opened (you completed it)',
        );
        store.close();
        return true;
      }

      final now = DateTime.now();
      if (reminder.scheduledAt.isBefore(
        now.subtract(const Duration(days: 30)),
      )) {
        await _log('Reminder $reminderId is too old (>30 days)');
        store.close();
        return true;
      }

      await _log('Getting reminder history...');
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

      await _log(
        '📋 [Reschedule] Reminder $reminderId history: ${previousAttempts.length} attempts',
      );
      for (int i = 0; i < previousAttempts.length; i++) {
        await _log(
          '   └─ Attempt ${i + 1}: scheduled=${previousAttempts[i]['scheduled_at']}, opened=${previousAttempts[i]['opened']}',
        );
      }

      await _log('Getting free times...');
      final freeTimes = freeTimeRepo.getAllAsJson();
      await _log('⏰ [Reschedule] Free times count: ${freeTimes.length}');

      await _log('🤖 [Reschedule] Calling AI for reschedule...');
      await _log(
        '📝 [Reschedule] Params: category="${reminder.categoryEn}", complexity="${reminder.complexityEn}", importance="${reminder.importance}", currentAttempts=${reminder.rescheduleAttempts}',
      );

      // Race guard: atomic lock via ObjectBox transaction shared with
      // OverdueReminderService, so the foreground and background paths can
      // never reschedule the same reminder concurrently (TOCTOU-safe).
      lockService = RescheduleLockService(store);
      if (!lockService.acquireLock(reminderId)) {
        await _log(
          '⚠️ [RaceGuard] Another reschedule in progress for reminder $reminderId, skipping',
        );
        store.close();
        return true;
      }
      await _log(
        '🔒 [RaceGuard] Acquired reschedule lock for reminder $reminderId',
      );

      Map<String, dynamic> aiResult = {};
      String? rawResponse;

      try {
        rawResponse = await aiService.reschedulePostRaw(
          previousAttemptsJson: jsonEncode(previousAttempts),
          category: reminder.categoryEn ?? 'Other',
          complexity: reminder.complexityEn ?? 'Medium',
          importance: reminder.importance,
          userFreeTimesJson: freeTimes.isNotEmpty
              ? '{"free_times": $freeTimes}'
              : null,
          currentTime: DateTime.now(),
        );
        await _log('📥 [Reschedule] Raw AI response: $rawResponse');
      } catch (e, stackTrace) {
        await _log(
          '❌ [Reschedule] AI call failed: $e — keeping time, '
          'retrying in 30 minutes',
        );
        debugPrint('📋 Stack: $stackTrace');
        await _scheduleAiRetry(reminderId, storeDirectoryPath);
        lockService.releaseLock(reminderId);
        await _log(
          '🔓 [RaceGuard] Released reschedule lock for reminder $reminderId',
        );
        await _log(
          '⏳ [Reschedule] AI retry scheduled in 30 minutes, '
          'no time change',
        );
        store.close();
        return true;
      }

      try {
        aiResult = AiRescheduleParser.parse(rawResponse);
      } catch (e) {
        await _log(
          '❌ [Reschedule] AI response parse failed: $e — keeping time, '
          'retrying in 30 minutes',
        );
        await _scheduleAiRetry(reminderId, storeDirectoryPath);
        lockService.releaseLock(reminderId);
        await _log(
          '🔓 [RaceGuard] Released reschedule lock for reminder $reminderId',
        );
        await _log(
          '⏳ [Reschedule] AI parse retry scheduled in 30 minutes, '
          'no time change',
        );
        store.close();
        return true;
      }
      await _log('Parsed AI result: $aiResult');

      final newTime = aiResult['newTime'] as DateTime?;
      if (newTime == null) {
        await _log('AI returned null new time, keeping time');
        await _scheduleAiRetry(reminderId, storeDirectoryPath);
        lockService.releaseLock(reminderId);
        await _log(
          '🔓 [RaceGuard] Released reschedule lock for reminder $reminderId',
        );
        await _log(
          '⏳ [Reschedule] AI retry scheduled in 30 minutes, no time change',
        );
        store.close();
        return true;
      }

      // Enforce the rescheduling deadline and a strict future-time constraint,
      // matching the foreground OverdueReminderService policy.
      final deadline = reschedulingDeadline(now, reminder.importance);
      final finalTime = clampRescheduleTime(newTime, now, deadline);
      if (finalTime != newTime) {
        await _log(
          "Clamped reschedule time from $newTime to $finalTime (deadline: $deadline)",
        );
      }

      await _log('Updating reminder with new time: $finalTime');
      reminder.scheduledAt = finalTime;
      reminder.rescheduleAttempts++;
      final reason = aiResult['reason'] as String? ?? '';
      final reasonParts = reason.split(' | ');
      reminder.aiExplanation = reasonParts.isNotEmpty ? reasonParts[0] : reason;
      reminder.aiExplanationAr = reasonParts.length > 1 ? reasonParts[1] : '';
      reminder.isOpened = false;
      reminder.openedAt = null;
      reminderRepo.save(reminder);
      await _log('Reminder saved successfully');

      await _log('Rescheduling WorkManager task...');
      await Workmanager().cancelByTag('reminder_$reminderId');
      final nextInputData = <String, String>{
        'reminderId': reminderId.toString(),
      };
      if (storeDirectoryPath != null) {
        nextInputData['storeDirectory'] = storeDirectoryPath;
      }
      var nextDelay =
          reminder.scheduledAt.difference(DateTime.now()) +
          const Duration(minutes: 1);
      if (nextDelay.isNegative) {
        await _log(
          'New scheduled time already passed, skipping next monitoring',
        );
        lockService.releaseLock(reminderId);
        await _log(
          '🔓 [RaceGuard] Released reschedule lock for reminder $reminderId',
        );
        store.close();
        return true;
      }
      const minDelay = Duration(minutes: 15);
      if (nextDelay < minDelay) {
        await _log(
          'initialDelay ${nextDelay.inMinutes}min < 15min, clamping to 15min',
        );
        nextDelay = minDelay;
      }
      await Workmanager().registerOneOffTask(
        'reminder_monitoring_$reminderId',
        _monitoringTaskName,
        initialDelay: nextDelay,
        inputData: nextInputData,
        tag: 'reminder_$reminderId',
        existingWorkPolicy: ExistingWorkPolicy.replace,
      );
      await _log('WorkManager task rescheduled');

      // Release lock BEFORE scheduling notification so it survives connection drops
      await _log('Releasing race guard lock...');
      lockService.releaseLock(reminderId);
      await _log(
        '🔓 [RaceGuard] Released reschedule lock for reminder $reminderId',
      );

      // Schedule notification (least critical — can be retried on next app launch)
      await _log('Scheduling new notification...');
      final plugin = FlutterLocalNotificationsPlugin();
      await zonedScheduleWithExactFallback(
        plugin: plugin,
        id: reminderId,
        title: ' Time to read: ${reminder.title}',
        body:
            '${reminder.categoryEn ?? "General"} · ${reminder.complexityAr ?? "متوسط"}',
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
        payload: reminderId.toString(),
      );
      await _log('Notification scheduled successfully');

      final formattedTime =
          '${finalTime.hour.toString().padLeft(2, '0')}:${finalTime.minute.toString().padLeft(2, '0')}';
      final successBody =
          '${reminder.title}\nNew time: $formattedTime\n${reminder.aiExplanation}';
      await plugin.show(
        id: reminderId,
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
      await _log('Reschedule notification shown');

      await _log('Closing store...');
      store.close();
      await _log('WorkManager task completed successfully');
      await _remoteLog(
        'workmanager_task_success',
        details: {'reminderId': reminderId},
      );
      return true;
    } catch (e, stackTrace) {
      await _log('WorkManager monitoring callback failed: $e');
      debugPrint('Stack trace: $stackTrace');
      await _remoteLog(
        'workmanager_task_error',
        details: {'reminderId': reminderId, 'error': e.toString()},
      );
      try {
        store?.close();
        await _log('Store closed after error');
      } catch (_) {}
      // Release race guard lock on error (via ObjectBox if store is open)
      if (store != null && lockService != null) {
        try {
          lockService.releaseLock(reminderId);
          await _log(
            '🔓 [RaceGuard] Released reschedule lock for reminder $reminderId (error path)',
          );
        } catch (_) {}
      }
      // If app is in foreground, store is locked by main isolate.
      // Ensure store is closed and return false so WorkManager knows the task failed and may retry.
      if (e.toString().contains('another store is still open')) {
        await _log(
          'App is in foreground, store locked — task failed, will retry',
        );
        try {
          store?.close();
          await _log('Store closed after "another store is still open" error');
        } catch (_) {}
        return false;
      }
      try {
        final prefs2 = await SharedPreferences.getInstance();
        await prefs2.setString('last_ai_reschedule_error', e.toString());
        await _log('Error saved to preferences');
      } catch (_) {}
      try {
        final errorPlugin = FlutterLocalNotificationsPlugin();
        await errorPlugin.initialize(
          settings: const InitializationSettings(
            android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          ),
        );
        final androidPlugin = errorPlugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();
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
        final errorText = e.toString().length > 100
            ? '${e.toString().substring(0, 100)}...'
            : e.toString();
        // Same id as the reminder; the scheduled notification (if any) replaces
        // this temporary error notification at delivery time.
        await errorPlugin.show(
          id: reminderId,
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
