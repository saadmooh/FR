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
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'objectbox.g.dart';
import 'package:objectbox_flutter_libs/objectbox_flutter_libs.dart';
import 'core/app_config.dart';
import 'core/app_theme.dart';
import 'core/app_router.dart';
import 'core/auth_diagnostics.dart';
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

  FlutterError.onError = (details) => FlutterError.presentError(details);

  try {
    await _initApp();
  } catch (e, st) {
    debugPrint('App initialization failed: $e\n$st');
    initError = 'App initialization failed: $e';
    runApp(MaterialApp(
      home: Scaffold(
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: SelectableText('INIT ERROR:\n$e\n\n$st'),
          ),
        ),
      ),
    ));
  }
}

// AUTH-DIAG (temporary)
void _boot(String step) {
  debugPrint('[boot] $step');
  unawaited(authDiag('boot_$step', details: {'step': step}));
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

  // AUTH-DIAG (temporary)
  firebase_auth.FirebaseAuth.instance.userChanges().listen((user) {
    unawaited(authDiag('user_changed', details: {'uid': user?.uid}));
  });
  // AUTH-DIAG (temporary)
  final authStart = DateTime.now().millisecondsSinceEpoch;
  final authFirstFuture = firebase_auth.FirebaseAuth.instance.authStateChanges().first;
  final authFirstTimeout = authFirstFuture.timeout(const Duration(seconds: 5), onTimeout: () => null);
  unawaited(authFirstTimeout.then((user) {
    final elapsed = DateTime.now().millisecondsSinceEpoch - authStart;
    unawaited(authDiag('auth_first_event', details: {'uid': user?.uid, 'elapsedMillis': elapsed}));
  }));

  final u = firebase_auth.FirebaseAuth.instance.currentUser;
  showUiLog('🔥 [AUTH-1] after Firebase.init: uid=${u?.uid}, email=${u?.email}');

  // Initialize RevenueCat early to avoid race condition with auth state listener
  revenueCatService = RevenueCatService();
  await revenueCatService.initialize();

  // Initialize AuthService and wait for initial auth state to avoid race condition
  authService = AuthService();
  await authService.waitForInitialAuth();
  _boot('after_auth');

  // Initialize timezone (resolves the device's IANA zone, not UTC)
  try {
    await initLocalTimeZone();
  } catch (e) {
    debugPrint('Timezone initialization failed: $e');
    if (initError == null) initError = 'Timezone initialization failed: $e';
  }
  _boot('after_timezone');

  // Initialize ObjectBox
  try {
    store = await _openMainStore();
  } catch (e) {
    debugPrint('ObjectBox initialization failed: $e');
    if (initError == null) initError = 'ObjectBox initialization failed: $e';
    rethrow;
  }
  _boot('after_objectbox');

  // Initialize SharedPreferences
  final prefs = await SharedPreferences.getInstance();
  _boot('after_prefs');

  // AUTH-DIAG (temporary)
  showUiLog(
    'DIAG remoteErr=${prefs.getString('auth_diag_last_remote_error')} '
    'logCount=${prefs.getStringList('auth_diag_log')?.length ?? 0}',
  );

  // Initialize repositories
  settingsRepository = AppSettingsRepository(prefs);
  reminderRepository = ReminderRepository(store);
  freeTimeRepository = FreeTimeRepository(store);
  categoryStatRepository = CategoryStatisticRepository(store);

  // Set repositories in settings for backup/restore
  settingsRepository.setRepositories(reminderRepository, freeTimeRepository);
  _boot('after_repos');

  // AUTH-DIAG (temporary)
  try {
    final reminderCount = reminderRepository.getTotalCount();
    final loginMarker = prefs.getString('debug_login_marker');
    unawaited(authDiag('app_start', details: {
      'currentUser': firebase_auth.FirebaseAuth.instance.currentUser?.uid,
      'debug_login_marker': loginMarker,
      'reminderCount': reminderCount,
    }));
  } catch (_) {
    // Guard: diagnostics must never break startup.
  }

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
  _boot('after_services');

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
  _boot('after_workmanager');

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
  _boot('after_notif_init');

  // Initialize overdue reminder service
  overdueReminderService = OverdueReminderService(
    reminderRepository: reminderRepository,
    freeTimeRepository: freeTimeRepository,
    aiService: aiService,
    notificationService: notificationService,
    lockService: RescheduleLockService(store),
  );

  // Run initial overdue check on app start
  _boot('before_overdue');

  // Request background permissions for reliable monitoring
  try {
    await notificationService
        .requestBackgroundPermissions()
        .timeout(const Duration(seconds: 5));
  } catch (e) {
    debugPrint('Background permissions failed: $e');
    if (initError == null) initError = 'Background permissions failed: $e';
  }
  _boot('after_bgperm');

  // Handle app launch from notification (if terminated)
  try {
    await notificationService.handleAppLaunchFromNotification();
  } catch (e) {
    debugPrint('Notification launch handling failed: $e');
    if (initError == null) initError = 'Notification launch handling failed: $e';
  }
  _boot('after_launch_notif');

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

  _boot('before_runapp');

  runApp(
    FlexReminderApp(
      initialSharedUrl: initialSharedUrl,
      aiRescheduleError: aiRescheduleError,
    ),
  );

  unawaited(overdueReminderService.reviewOverdueReminders().then((c) {
    if (c > 0) {
      debugPrint('[main] Rescheduled $c overdue reminders on start');
    }
  }).catchError((e) {
    showUiLog('Overdue check failed on start: $e');
  }));
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
