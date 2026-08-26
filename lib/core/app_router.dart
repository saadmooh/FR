import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../screens/reminders_screen.dart';
import '../screens/post_detail_screen.dart';
import '../screens/edit_reminder_screen.dart';
import '../screens/statistics_screen.dart';
import '../screens/free_times_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/login_screen.dart';
import '../screens/paywall_screen.dart';
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
      refreshListenable: revenueCatService,
      redirect: (context, state) {
        final isLoggedIn = authService.isSignedIn;
        final isPremium = revenueCatService.isPremium;
        final isOnLogin = state.matchedLocation == '/login';
        final isOnPaywall = state.matchedLocation == '/paywall';

        // Layer 1: signed out -> only /login is reachable.
        if (!isLoggedIn) {
          return isOnLogin ? null : '/login';
        }

        // Layer 2: signed in without an active entitlement ->
        // only /paywall is reachable.
        if (!isPremium) {
          return isOnPaywall ? null : '/paywall';
        }

        // Layer 3: paying user -> keep them out of login/paywall.
        if (isOnLogin || isOnPaywall) {
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
        GoRoute(
          path: '/paywall',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: PaywallScreen(),
          ),
        ),
        ShellRoute(
          builder: (context, state, child) => MainShell(
            authService: authService,
            revenueCatService: revenueCatService,
            settingsRepository: settingsRepository,
            child: child,
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
          path: '/settings',
          builder: (context, state) => SettingsScreen(
            settingsRepository: settingsRepository,
            authService: authService,
            revenueCatService: revenueCatService,
          ),
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

  void _onNavTapped(int index) {
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
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: widget.child,
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: AppColors.whiteSurface,
          border: Border(
            top: BorderSide(color: AppColors.whiteBorder, width: 1),
          ),
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: _onNavTapped,
          type: BottomNavigationBarType.fixed,
          elevation: 8,
          backgroundColor: AppColors.whiteSurface,
          selectedItemColor: AppColors.whiteAccent,
          unselectedItemColor: AppColors.whiteTextSecondary,
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
