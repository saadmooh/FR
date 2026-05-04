import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../screens/reminders_screen.dart';
import '../screens/post_detail_screen.dart';
import '../screens/edit_reminder_screen.dart';
import '../screens/statistics_screen.dart';
import '../screens/free_times_screen.dart';
import '../screens/settings_screen.dart';
import '../repositories/reminder_repository.dart';
import '../repositories/free_time_repository.dart';
import '../repositories/category_statistic_repository.dart';
import '../repositories/app_settings_repository.dart';
import '../services/notification_service.dart';
import '../services/ai_service.dart';
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

  late final GoRouter router;

  AppRouter({
    required this.reminderRepository,
    required this.freeTimeRepository,
    required this.categoryStatRepository,
    required this.notificationService,
    required this.aiService,
    required this.settingsRepository,
    required this.pendingSharedUrl,
    required this.aiRescheduleError,
  }) {
    router = GoRouter(
      initialLocation: '/',
      routes: [
        ShellRoute(
          builder: (context, state, child) => MainShell(child: child),
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
          ),
        ),
      ],
    );
  }
}

class MainShell extends StatefulWidget {
  final Widget child;

  const MainShell({super.key, required this.child});

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
      body: widget.child,
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
