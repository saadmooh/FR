import 'dart:io' show Platform;
import 'dart:isolate';
import 'dart:ui' show IsolateNameServer;
import 'dart:async' show unawaited;
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'objectbox.g.dart';
import 'package:objectbox_flutter_libs/objectbox_flutter_libs.dart';
import 'core/app_config.dart';
import 'core/app_theme.dart';
import 'core/app_router.dart';
import 'core/constants.dart';
import 'core/locale_manager.dart';
import 'core/ui_messenger.dart';
import 'repositories/reminder_repository.dart';
import 'repositories/free_time_repository.dart';
import 'repositories/category_statistic_repository.dart';
import 'repositories/app_settings_repository.dart';
import 'services/ai_service.dart';
import 'services/ai_proxy_service.dart';
import 'services/local_timezone.dart';
import 'services/notification_service.dart';
import 'services/proxy_config_service.dart';
import 'services/overdue_reminder_service.dart';
import 'services/reschedule_lock_service.dart';
import 'services/workmanager_service.dart';
import 'services/auth_service.dart';
import 'services/revenuecat_service.dart';

late Store store;
late ReminderRepository reminderRepository;
late FreeTimeRepository freeTimeRepository;
late CategoryStatisticRepository categoryStatRepository;
late AppSettingsRepository settingsRepository;
late AIService aiService;
late NotificationService notificationService;
late OverdueReminderService overdueReminderService;
late AppRouter appRouter;
late AuthService authService;
late RevenueCatService revenueCatService;

final ValueNotifier<String?> pendingSharedUrl = ValueNotifier<String?>(null);
final ValueNotifier<String?> aiRescheduleError = ValueNotifier<String?>(null);
String? initError;
final ValueNotifier<int?> reminderOpenedId = ValueNotifier<int?>(null);

const String _bgUiLogQueueKey = 'bg_ui_log_queue';
const String bgLogPortName = 'bg_log_port';

/// Reads queued background logs from SharedPreferences (cold start / resume fallback)
Future<void> _showQueuedBgLogs(SharedPreferences prefs) async {
  final logs = prefs.getStringList(_bgUiLogQueueKey);
  if (logs == null || logs.isEmpty) return;

  await prefs.remove(_bgUiLogQueueKey);

  for (final log in logs) {
    showUiLog(log, duration: const Duration(seconds: 5));
  }
}

// Global scaffold messenger key for IntegritySnackBar and RC UI logs
// (defined in core/ui_messenger.dart)

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Catch unhandled errors during initialization
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
  };

  try {
    await _initApp();
  } catch (e, stackTrace) {
    debugPrint('App initialization failed: $e\n$stackTrace');
    initError = 'App initialization failed: $e';
  }
}

/// Opens the ObjectBox store from the main isolate.
///
/// A WorkManager background isolate may already hold the store open on the
/// same path (e.g. after a background task cold-started the process). In that
/// case we attach to the existing store instead of opening a second one, which
/// would fail with "another store is still open". Falls back to retrying a few
/// times to cover short-lived background tasks that close the store shortly
/// after start.
Future<Store> _openMainStore() async {
  await loadObjectBoxLibraryAndroidCompat();
  final directoryPath = (await defaultStoreDirectory()).path;

  if (Store.isOpen(directoryPath)) {
    debugPrint('[main] ObjectBox store already open, attaching to it');
    return Store.attach(getObjectBoxModel(), directoryPath);
  }

  const maxAttempts = 10;
  const baseDelay = Duration(milliseconds: 500);
  for (int attempt = 1; attempt <= maxAttempts; attempt++) {
    try {
      return await openStore(directory: directoryPath);
    } catch (e) {
      if (e.toString().contains('another store is still open') &&
          attempt < maxAttempts) {
        final delay = baseDelay * attempt; // exponential backoff
        debugPrint(
          '[main] Store lock held by another isolate '
          '(attempt $attempt/$maxAttempts), retrying in ${delay.inMilliseconds}ms...',
        );
        await Future.delayed(delay);
      } else {
        rethrow;
      }
    }
  }
  throw StateError('Failed to open ObjectBox store after $maxAttempts attempts');
}

Future<void> _initApp() async {
  try {
    await Firebase.initializeApp();
  } catch (e, stackTrace) {
    debugPrint('Firebase initialization failed: $e\n$stackTrace');
    if (initError == null) initError = 'Firebase initialization failed: $e';
  }

  // Initialize Supabase (guarded: skip when --dart-define placeholders are used)
  if (AppConfig.isSupabaseConfigured) {
    try {
      await Supabase.initialize(
        url: AppConfig.supabaseUrl,
        publishableKey: AppConfig.supabaseAnonKey,
      );
    } catch (e) {
      debugPrint('Supabase initialization failed: $e');
      if (initError == null) initError = 'Supabase initialization failed: $e';
    }
  } else {
    debugPrint(
      'Supabase not configured — pass --dart-define '
      'SUPABASE_URL / SUPABASE_ANON_KEY / GCP_CLOUD_PROJECT_NUMBER',
    );
  }

  authService = AuthService();
  revenueCatService = RevenueCatService();
  try {
    await revenueCatService.initialize();
  } catch (e) {
    debugPrint('RevenueCat initialization failed: $e');
    if (initError == null) initError = 'RevenueCat initialization failed: $e';
  }

  // Initialize timezone (resolves the device's IANA zone, not UTC)
  try {
    await initLocalTimeZone();
  } catch (e) {
    debugPrint('Timezone initialization failed: $e');
    if (initError == null) initError = 'Timezone initialization failed: $e';
  }

  // Initialize ObjectBox
  try {
    store = await _openMainStore();
  } catch (e) {
    debugPrint('ObjectBox initialization failed: $e');
    if (initError == null) initError = 'ObjectBox initialization failed: $e';
    rethrow;
  }

  // Initialize SharedPreferences
  final prefs = await SharedPreferences.getInstance();

  // Set default provider if not set
  if (!prefs.containsKey(AppConstants.aiProviderKey)) {
    await prefs.setString(
      AppConstants.aiProviderKey,
      AppConstants.defaultProvider,
    );
  }

  // Initialize repositories
  settingsRepository = AppSettingsRepository(prefs);
  reminderRepository = ReminderRepository(store);
  freeTimeRepository = FreeTimeRepository(store);
  categoryStatRepository = CategoryStatisticRepository(store);

  // Set repositories in settings for backup/restore
  settingsRepository.setRepositories(reminderRepository, freeTimeRepository);

  // Initialize locale manager
  LocaleManager.instance.initialize(settingsRepository);

  // Pre-fetch proxy config from Supabase and cache for 24 hours.
  // Non-blocking: if it times out or fails, the app can still start.
  if (AppConfig.isSupabaseConfigured) {
    unawaited(
      ProxyConfigService.instance.prefetch().timeout(
        const Duration(seconds: 12),
      ).catchError((_) {}),
    );
  }

  // Check for previous AI reschedule errors
  final lastError = prefs.getString('last_ai_reschedule_error');
  if (lastError != null && lastError.isNotEmpty) {
    aiRescheduleError.value = lastError;
    await prefs.remove('last_ai_reschedule_error');
  }

  // Show queued background logs as SnackBars
  await _showQueuedBgLogs(prefs);

  // Initialize services
  aiService = AIService(settingsRepository);
  final aiProxy = AiProxyService.fromConfig();
  aiService = AIService(settingsRepository, aiProxy: aiProxy);
  notificationService = NotificationService();

  // Initialize WorkManager for background monitoring (Android/iOS only)
  if (Platform.isAndroid || Platform.isIOS) {
    try {
      await Workmanager().initialize(
        callbackDispatcher,
        isInDebugMode: kDebugMode,
      );
    } catch (e) {
      debugPrint('WorkManager initialization failed: $e');
      if (initError == null) initError = 'WorkManager initialization failed: $e';
    }
  }

  // Pass store directory path to notification service for WorkManager tasks
  final storeDir = await defaultStoreDirectory();
  notificationService.setStoreDirectoryPath(storeDir.path);

  try {
    await notificationService.initialize(
      reminderRepository: reminderRepository,
      categoryStatRepository: categoryStatRepository,
      freeTimeRepository: freeTimeRepository,
      settingsRepository: settingsRepository,
    );
  } catch (e) {
    debugPrint('Notification service initialization failed: $e');
    if (initError == null) initError = 'Notification service initialization failed: $e';
  }

  // Initialize overdue reminder service
  overdueReminderService = OverdueReminderService(
    reminderRepository: reminderRepository,
    freeTimeRepository: freeTimeRepository,
    aiService: aiService,
    notificationService: notificationService,
    lockService: RescheduleLockService(store),
  );

  // Run initial overdue check on app start
  try {
    final rescheduledCount = await overdueReminderService
        .reviewOverdueReminders();
    if (rescheduledCount > 0) {
      debugPrint(
        '[main] Rescheduled $rescheduledCount overdue reminders on app start',
      );
    }
  } catch (e, stackTrace) {
    debugPrint('[main] Failed to review overdue reminders on start: $e');
    debugPrint('Stack trace: $stackTrace');
    if (initError == null) initError = 'Overdue check failed on start: $e';
    showUiLog(
      'Overdue check failed on start: $e',
      duration: const Duration(seconds: 6),
    );
  }

  // Request background permissions for reliable monitoring
  try {
    await notificationService.requestBackgroundPermissions();
  } catch (e) {
    debugPrint('Background permissions failed: $e');
    if (initError == null) initError = 'Background permissions failed: $e';
  }

  // Handle app launch from notification (if terminated)
  try {
    await notificationService.handleAppLaunchFromNotification();
  } catch (e) {
    debugPrint('Notification launch handling failed: $e');
    if (initError == null) initError = 'Notification launch handling failed: $e';
  }

  // Handle cold-start shared URL
  String? initialSharedUrl;
  try {
    final initial = await ReceiveSharingIntent.instance.getInitialMedia();
    if (initial.isNotEmpty) {
      final text = initial.first.path;
      if (text.startsWith('http')) {
        initialSharedUrl = text;
      }
      ReceiveSharingIntent.instance.reset();
    }
  } catch (e) {
    // Platform might not support this
  }

  // Create app router
  appRouter = AppRouter(
    reminderRepository: reminderRepository,
    freeTimeRepository: freeTimeRepository,
    categoryStatRepository: categoryStatRepository,
    notificationService: notificationService,
    aiService: aiService,
    settingsRepository: settingsRepository,
    pendingSharedUrl: pendingSharedUrl,
    aiRescheduleError: aiRescheduleError,
    reminderOpenedId: reminderOpenedId,
    authService: authService,
    revenueCatService: revenueCatService,
  );

  // Set router in notification service
  notificationService.setRouter(appRouter.router);

  runApp(
    FlexReminderApp(
      initialSharedUrl: initialSharedUrl,
      aiRescheduleError: aiRescheduleError,
    ),
  );
}

class FlexReminderApp extends StatefulWidget {
  final String? initialSharedUrl;
  final ValueNotifier<String?> aiRescheduleError;

  const FlexReminderApp({
    super.key,
    this.initialSharedUrl,
    required this.aiRescheduleError,
  });

  @override
  State<FlexReminderApp> createState() => _FlexReminderAppState();
}

class _FlexReminderAppState extends State<FlexReminderApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);

    // Set initial shared URL
    if (widget.initialSharedUrl != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        pendingSharedUrl.value = widget.initialSharedUrl;
      });
    }

    // Listen to locale changes for rebuild
    LocaleManager.instance.localeNotifier.addListener(_onLocaleChanged);

    // Set up cross-isolate communication for background task SnackBars
    final receivePort = ReceivePort();
    IsolateNameServer.removePortNameMapping(bgLogPortName);
    IsolateNameServer.registerPortWithName(receivePort.sendPort, bgLogPortName);
    receivePort.listen((message) {
      if (message is String) {
        showUiLog(message, duration: const Duration(seconds: 5));
      } else if (message is Map && message['command'] == 'trigger_overdue_check') {
        // Trigger overdue check in foreground
        debugPrint('[main] Received trigger_overdue_check from background');
        unawaited(overdueReminderService.reviewOverdueReminders().then((count) {
          if (count > 0) {
            debugPrint('[main] Foreground overdue check rescheduled $count reminders');
            showUiLog('Rescheduled $count overdue reminders', duration: const Duration(seconds: 4));
          } else {
            debugPrint('[main] Foreground overdue check: no overdue reminders found');
            showUiLog('Overdue check completed — no overdue reminders', duration: const Duration(seconds: 3));
          }
        }));
      }
    });

    // Listen to incoming shared intents while app is open
    ReceiveSharingIntent.instance.getMediaStream().listen((sharedMedia) {
      if (sharedMedia.isNotEmpty) {
        final text = sharedMedia.first.path;
        if (text.startsWith('http')) {
          pendingSharedUrl.value = text;
        }
        ReceiveSharingIntent.instance.reset();
      }
    });

    // Show startup RC/UI logs that arrived before MaterialApp mounted
    WidgetsBinding.instance.addPostFrameCallback((_) {
      flushPendingUiLogs();
    });
  }

  @override
  @override
  void dispose() {
    IsolateNameServer.removePortNameMapping(bgLogPortName);
    WidgetsBinding.instance.removeObserver(this);
    LocaleManager.instance.localeNotifier.removeListener(_onLocaleChanged);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        // Store stays open for the entire process lifetime
        break;
      case AppLifecycleState.resumed:
        await _runOverdueCheck();
        final prefs = await SharedPreferences.getInstance();
        await _showQueuedBgLogs(prefs);
        flushPendingUiLogs();
        break;
      default:
        break;
    }
  }

  Future<void> _runOverdueCheck() async {
    try {
      final rescheduledCount = await overdueReminderService
          .reviewOverdueReminders();
      if (rescheduledCount > 0) {
        debugPrint(
          '[AppLifecycle] Rescheduled $rescheduledCount overdue reminders on app resume',
        );
      }
    } catch (e, stackTrace) {
      debugPrint(
        '[AppLifecycle] Failed to review overdue reminders on resume: $e',
      );
      debugPrint('Stack trace: $stackTrace');
      showUiLog(
        'Overdue check failed on resume: $e',
        duration: const Duration(seconds: 6),
      );
    }
  }

  void _onLocaleChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: buildWhiteTheme(),
      routerConfig: appRouter.router,
      scaffoldMessengerKey: scaffoldMessengerKey,
      locale: LocaleManager.instance.currentAppLocale,
      supportedLocales: LocaleManager.supportedLocales,
      localizationsDelegates: [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
    );
  }
}
