import 'package:flutter/material.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;

import 'objectbox.g.dart';
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

late Store store;
late ReminderRepository reminderRepository;
late FreeTimeRepository freeTimeRepository;
late CategoryStatisticRepository categoryStatRepository;
late AppSettingsRepository settingsRepository;
late AIService aiService;
late NotificationService notificationService;
late AppRouter appRouter;

final ValueNotifier<String?> pendingSharedUrl = ValueNotifier<String?>(null);

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
  // Initialize timezone
  tz_data.initializeTimeZones();
  // Use local timezone instead of UTC
  tz.setLocalLocation(tz.local);

  // Initialize ObjectBox
  store = await openStore();

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

  // Initialize services
  aiService = AIService(settingsRepository);
  notificationService = NotificationService();

  await notificationService.initialize(
    reminderRepository: reminderRepository,
    categoryStatRepository: categoryStatRepository,
  );

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
  );

  // Set router in notification service
  notificationService.setRouter(appRouter.router);

  runApp(FlexReminderApp(initialSharedUrl: initialSharedUrl));
}

class FlexReminderApp extends StatefulWidget {
  final String? initialSharedUrl;

  const FlexReminderApp({super.key, this.initialSharedUrl});

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
  }

  @override
  void dispose() {
    LocaleManager.instance.localeNotifier.removeListener(_onLocaleChanged);
    super.dispose();
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
