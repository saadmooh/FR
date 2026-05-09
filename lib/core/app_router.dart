import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../screens/reminders_screen.dart';
import '../screens/post_detail_screen.dart';
import '../screens/edit_reminder_screen.dart';
import '../screens/statistics_screen.dart';
import '../screens/free_times_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/login_screen.dart';
import '../repositories/reminder_repository.dart';
import '../repositories/free_time_repository.dart';
import '../repositories/category_statistic_repository.dart';
import '../repositories/app_settings_repository.dart';
import '../services/notification_service.dart';
import '../services/ai_service.dart';
import '../services/auth_service.dart';
import '../services/revenuecat_service.dart';
import 'app_theme.dart';
import 'locale_manager.dart';
import 'translations.dart';

class AppRouter {
  final ReminderRepository reminderRepository;
  final FreeTimeRepository freeTimeRepository;
  final CategoryStatisticRepository categoryStatRepository;
  final NotificationService notificationService;
  final AIService aiService;
  final AppSettingsRepository settingsRepository;
  final ValueNotifier<String?> pendingSharedUrl;
  final ValueNotifier<String?> aiRescheduleError;
  final AuthService authService;
  final RevenueCatService revenueCatService;

  late GoRouter router;

  AppRouter({
    required this.reminderRepository,
    required this.freeTimeRepository,
    required this.categoryStatRepository,
    required this.notificationService,
    required this.aiService,
    required this.settingsRepository,
    required this.pendingSharedUrl,
    required this.aiRescheduleError,
    required this.authService,
    required this.revenueCatService,
  }) {
    router = GoRouter(
      initialLocation: '/',
      redirect: (context, state) {
        final isLoggedIn = authService.isSignedIn;
        final isOnLogin = state.matchedLocation == '/login';
        if (!isLoggedIn && !isOnLogin) {
          return '/login';
        }
        if (isLoggedIn && isOnLogin) {
          return '/';
        }
        return null;
      },
      routes: [
        GoRoute(
          path: '/login',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: LoginScreen(),
          ),
        ),
        ShellRoute(
          builder: (context, state, child) => MainShell(
            child: child,
            authService: authService,
            revenueCatService: revenueCatService,
            settingsRepository: settingsRepository,
          ),
          routes: [
            GoRoute(
              path: '/',
              pageBuilder: (context, state) => NoTransitionPage(
                child: RemindersScreen(
                  reminderRepository: reminderRepository,
                  freeTimeRepository: freeTimeRepository,
                  categoryStatRepository: categoryStatRepository,
                  notificationService: notificationService,
                  aiService: aiService,
                  pendingSharedUrl: pendingSharedUrl,
                  aiRescheduleError: aiRescheduleError,
                ),
              ),
            ),
            GoRoute(
              path: '/statistics',
              pageBuilder: (context, state) => NoTransitionPage(
                child: StatisticsScreen(
                  reminderRepository: reminderRepository,
                  categoryStatRepository: categoryStatRepository,
                  aiService: aiService,
                ),
              ),
            ),
            GoRoute(
              path: '/free-times',
              pageBuilder: (context, state) => NoTransitionPage(
                child: FreeTimesScreen(freeTimeRepository: freeTimeRepository),
              ),
            ),
          ],
        ),
        GoRoute(
          path: '/post/:id',
          builder: (context, state) {
            final id = int.parse(state.pathParameters['id']!);
            return PostDetailScreen(
              id: id,
              reminderRepository: reminderRepository,
              freeTimeRepository: freeTimeRepository,
              categoryStatRepository: categoryStatRepository,
              notificationService: notificationService,
              aiService: aiService,
            );
          },
        ),
        GoRoute(
          path: '/post/:id/edit',
          redirect: (context, state) {
            final id = int.parse(state.pathParameters['id']!);
            final reminder = reminderRepository.getById(id);
            if (reminder == null) {
              return '/post/$id';
            }
            return null;
          },
          builder: (context, state) {
            final id = int.parse(state.pathParameters['id']!);
            final reminder = reminderRepository.getById(id)!;
            return EditReminderScreen(
              reminder: reminder,
              reminderRepository: reminderRepository,
              freeTimeRepository: freeTimeRepository,
              notificationService: notificationService,
              aiService: aiService,
              onSaved: () => context.go('/post/$id'),
            );
          },
        ),
        GoRoute(
          path: '/settings',
          builder: (context, state) => SettingsScreen(
            aiService: aiService,
            settingsRepository: settingsRepository,
            authService: authService,
            revenueCatService: revenueCatService,
          ),
        ),
      ],
    );
  }
}

class MainShell extends StatefulWidget {
  final Widget child;
  final AuthService authService;
  final RevenueCatService revenueCatService;
  final AppSettingsRepository settingsRepository;

  const MainShell({
    super.key,
    required this.child,
    required this.authService,
    required this.revenueCatService,
    required this.settingsRepository,
  });

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    LocaleManager.instance.localeNotifier.addListener(_onLocaleChanged);
  }

  @override
  void dispose() {
    LocaleManager.instance.localeNotifier.removeListener(_onLocaleChanged);
    super.dispose();
  }

  void _onLocaleChanged() {
    if (mounted) setState(() {});
  }

  String get _locale => LocaleManager.instance.getLocale();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          Expanded(child: widget.child),
          Container(
            width: 1,
            color: AppColors.surfaceLight,
          ),
          GestureDetector(
            onTap: () => context.push('/settings'),
            child: Container(
              width: 56,
              color: AppColors.surface,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    widget.revenueCatService.isPremium
                        ? Icons.workspace_premium
                        : Icons.account_circle,
                    color: AppColors.accent,
                    size: 24,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    Translations.settings(_locale),
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(
            top: BorderSide(color: AppColors.surfaceLight, width: 1),
          ),
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) {
            setState(() => _currentIndex = index);
            switch (index) {
              case 0:
                context.go('/');
                break;
              case 1:
                context.go('/statistics');
                break;
              case 2:
                context.go('/free-times');
                break;
            }
          },
          items: [
            BottomNavigationBarItem(
              icon: const Icon(Icons.bookmark),
              label: Translations.navPosts(_locale),
            ),
            BottomNavigationBarItem(
              icon: const Icon(Icons.bar_chart),
              label: Translations.navStats(_locale),
            ),
            BottomNavigationBarItem(
              icon: const Icon(Icons.access_time),
              label: Translations.navFreeTime(_locale),
            ),
          ],
        ),
      ),
    );
  }
}