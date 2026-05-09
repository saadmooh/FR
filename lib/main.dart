import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:workmanager/workmanager.dart';
import 'package:firebase_core/firebase_core.dart';

import 'objectbox.g.dart';
import 'package:objectbox_flutter_libs/objectbox_flutter_libs.dart';
import 'core/app_theme.dart';
import 'core/app_router.dart';
import 'core/constants.dart';
import 'core/locale_manager.dart';
import 'repositories/reminder_repository.dart';
import 'repositories/free_time_repository.dart';
import 'repositories/category_statistic_repository.dart';
import 'repositories/app_settings_repository.dart';
import 'services/ai_service.dart';
import 'services/notification_service.dart';
import 'services/workmanager_service.dart';
import 'services/auth_service.dart';
import 'services/revenuecat_service.dart';

late Store store;
bool _storeInitialized = false;
late ReminderRepository reminderRepository;
late FreeTimeRepository freeTimeRepository;
late CategoryStatisticRepository categoryStatRepository;
late AppSettingsRepository settingsRepository;
late AIService aiService;
late NotificationService notificationService;
late AppRouter appRouter;
late AuthService authService;
late RevenueCatService revenueCatService;

final ValueNotifier<String?> pendingSharedUrl = ValueNotifier<String?>(null);
final ValueNotifier<String?> aiRescheduleError = ValueNotifier<String?>(null);
final ValueNotifier<int> storeReopenSignal = ValueNotifier<int>(0);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Catch unhandled errors during initialization
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
  };

  try {
    await _initApp();
  } catch (e, stackTrace) {
    // Show error screen instead of blank screen
    debugPrint('App initialization failed: $e\n$stackTrace');
    runApp(
      MaterialApp(
        home: Scaffold(
          backgroundColor: const Color(0xFF1A1A2E),
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 64),
                  const SizedBox(height: 16),
                  const Text(
                    'Failed to start app',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    e.toString(),
                    style: const TextStyle(color: Colors.white70, fontSize: 14),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    return;
  }
}

Future<void> _initApp() async {
  await Firebase.initializeApp();
  authService = AuthService();
  revenueCatService = RevenueCatService();
  await revenueCatService.initialize();

  // Initialize timezone
  tz_data.initializeTimeZones();
  // Use local timezone instead of UTC
  tz.setLocalLocation(tz.local);

  // Initialize ObjectBox with retry on conflict
  Store? tempStore;
  const maxRetries = 3;
  const retryDelay = Duration(seconds: 2);
  
  for (int attempt = 0; attempt < maxRetries; attempt++) {
    try {
      tempStore = await openStore();
      store = tempStore;
      _storeInitialized = true;
      break;
    } catch (e) {
      if (e.toString().contains('another store is still open') && attempt < maxRetries - 1) {
        debugPrint('Store conflict detected (attempt ${attempt + 1}/$maxRetries), waiting for lock release...');
        await Future.delayed(retryDelay);
      } else {
        debugPrint('Store initialization failed: $e');
        rethrow;
      }
    }
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

  // Check for previous AI reschedule errors
  final lastError = prefs.getString('last_ai_reschedule_error');
  if (lastError != null && lastError.isNotEmpty) {
    aiRescheduleError.value = lastError;
    await prefs.remove('last_ai_reschedule_error');
  }

  // Initialize services
  aiService = AIService(settingsRepository);
  notificationService = NotificationService();

  // Initialize WorkManager for background monitoring (Android/iOS only)
  if (Platform.isAndroid || Platform.isIOS) {
    try {
      await Workmanager().initialize(callbackDispatcher);
    } catch (e) {
      debugPrint('WorkManager initialization failed: $e');
    }
  }

  // Pass store directory path to notification service for WorkManager tasks
  final storeDir = await defaultStoreDirectory();
  notificationService.setStoreDirectoryPath(storeDir.path);

  // Pass AI config to notification service for WorkManager background tasks
  notificationService.setAiConfig(
    settingsRepository.getApiKey() ?? '',
    settingsRepository.getProvider(),
    settingsRepository.getModel(),
  );

  await notificationService.initialize(
    reminderRepository: reminderRepository,
    categoryStatRepository: categoryStatRepository,
    freeTimeRepository: freeTimeRepository,
    settingsRepository: settingsRepository,
  );

  // Request background permissions for reliable monitoring
  await notificationService.requestBackgroundPermissions();

  // Handle app launch from notification (if terminated)
  await notificationService.handleAppLaunchFromNotification();

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
    authService: authService,
    revenueCatService: revenueCatService,
  );

  // Set router in notification service
  notificationService.setRouter(appRouter.router);

  runApp(FlexReminderApp(initialSharedUrl: initialSharedUrl, aiRescheduleError: aiRescheduleError));
}

class FlexReminderApp extends StatefulWidget {
  final String? initialSharedUrl;
  final ValueNotifier<String?> aiRescheduleError;

  const FlexReminderApp({super.key, this.initialSharedUrl, required this.aiRescheduleError});

  @override
  State<FlexReminderApp> createState() => _FlexReminderAppState();
}

class _FlexReminderAppState extends State<FlexReminderApp> {
  @override
  void initState() {
    super.initState();

    // Set initial shared URL
    if (widget.initialSharedUrl != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        pendingSharedUrl.value = widget.initialSharedUrl;
      });
    }

    // Listen to locale changes for rebuild
    LocaleManager.instance.localeNotifier.addListener(_onLocaleChanged);

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

    // Handle app lifecycle for store cleanup
    WidgetsBinding.instance.addObserver(_AppLifecycleObserver());

    // Listen to store reopen signals to rebuild with new router
    storeReopenSignal.addListener(_onStoreReopened);
  }

  @override
  void dispose() {
    LocaleManager.instance.localeNotifier.removeListener(_onLocaleChanged);
    storeReopenSignal.removeListener(_onStoreReopened);
    super.dispose();
  }

  void _onStoreReopened() {
    if (mounted) {
      setState(() {});
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
      locale: LocaleManager.instance.currentAppLocale,
      supportedLocales: LocaleManager.supportedLocales,
    );
  }
}

class _AppLifecycleObserver extends WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused && _storeInitialized) {
      try {
        store.close();
        _storeInitialized = false;
        debugPrint('Store closed on app background');
      } catch (_) {}
    } else if (state == AppLifecycleState.resumed && !_storeInitialized) {
      _reopenStore().catchError((e) {
        debugPrint('Failed to reopen store: $e');
      });
    } else if (state == AppLifecycleState.detached && _storeInitialized) {
      try {
        store.close();
        _storeInitialized = false;
      } catch (_) {}
    }
  }

  Future<void> _reopenStore() async {
    const maxRetries = 3;
    const retryDelay = Duration(seconds: 1);
    
    for (int attempt = 0; attempt < maxRetries; attempt++) {
      try {
        store = await openStore();
        _storeInitialized = true;
        
        reminderRepository = ReminderRepository(store);
        freeTimeRepository = FreeTimeRepository(store);
        categoryStatRepository = CategoryStatisticRepository(store);
        settingsRepository.setRepositories(reminderRepository, freeTimeRepository);
        
        appRouter = AppRouter(
          reminderRepository: reminderRepository,
          freeTimeRepository: freeTimeRepository,
          categoryStatRepository: categoryStatRepository,
          notificationService: notificationService,
          aiService: aiService,
          settingsRepository: settingsRepository,
          pendingSharedUrl: pendingSharedUrl,
          aiRescheduleError: aiRescheduleError,
          authService: authService,
          revenueCatService: revenueCatService,
        );
        notificationService.setRouter(appRouter.router);
        
        storeReopenSignal.value++;
        debugPrint('Store reopened on app resume');
        return;
      } catch (e) {
        if (attempt < maxRetries - 1) {
          debugPrint('Store reopen attempt ${attempt + 1} failed, retrying...');
          await Future.delayed(retryDelay);
        } else {
          rethrow;
        }
      }
    }
  }
}
