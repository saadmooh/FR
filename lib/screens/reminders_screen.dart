import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../repositories/reminder_repository.dart';
import '../repositories/free_time_repository.dart';
import '../repositories/category_statistic_repository.dart';
import '../services/notification_service.dart';
import '../services/ai_service.dart';
import '../models/reminder.dart';
import '../widgets/reminder_card.dart';
import '../widgets/save_post_sheet.dart';
import '../widgets/empty_state.dart';
import '../core/app_theme.dart';

class RemindersScreen extends StatefulWidget {
  final ReminderRepository reminderRepository;
  final FreeTimeRepository freeTimeRepository;
  final CategoryStatisticRepository categoryStatRepository;
  final NotificationService notificationService;
  final AIService aiService;
  final ValueNotifier<String?> pendingSharedUrl;

  const RemindersScreen({
    super.key,
    required this.reminderRepository,
    required this.freeTimeRepository,
    required this.categoryStatRepository,
    required this.notificationService,
    required this.aiService,
    required this.pendingSharedUrl,
  });

  @override
  State<RemindersScreen> createState() => _RemindersScreenState();
}

class _RemindersScreenState extends State<RemindersScreen> {
  late PageController _pageController;
  int _currentPage = 0;
  List<Reminder> _unreadReminders = [];
  List<Reminder> _readReminders = [];
  bool _isLoading = true;

  void _showResult(bool success, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(success ? '✅ $message' : '❌ $message'),
        backgroundColor: success ? AppColors.accent : AppColors.error,
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: 0);
    _loadReminders();

    // Listen for pending shared URL
    widget.pendingSharedUrl.addListener(_onPendingSharedUrlChanged);
  }

  @override
  void dispose() {
    widget.pendingSharedUrl.removeListener(_onPendingSharedUrlChanged);
    _pageController.dispose();
    super.dispose();
  }

  void _onPendingSharedUrlChanged() {
    final url = widget.pendingSharedUrl.value;
    if (url != null && url.isNotEmpty && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _openSaveSheet(initialUrl: url);
        widget.pendingSharedUrl.value = null;
      });
    }
  }

  void _loadReminders() {
    setState(() {
      _unreadReminders = widget.reminderRepository.getUnread();
      _readReminders = widget.reminderRepository.getRead();
      _isLoading = false;
    });
  }

  void _openSaveSheet({String? initialUrl}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SavePostSheet(
        initialUrl: initialUrl,
        reminderRepository: widget.reminderRepository,
        freeTimeRepository: widget.freeTimeRepository,
        categoryStatRepository: widget.categoryStatRepository,
        notificationService: widget.notificationService,
        aiService: widget.aiService,
        onSaved: _loadReminders,
      ),
    );
  }

  void _showContextMenu(Reminder reminder) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.schedule, color: AppColors.accent),
              title: const Text(
                'Reschedule',
                style: TextStyle(color: AppColors.textPrimary),
              ),
              onTap: () {
                Navigator.pop(context);
                _rescheduleReminder(reminder);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: AppColors.error),
              title: const Text(
                'Delete',
                style: TextStyle(color: AppColors.error),
              ),
              onTap: () {
                Navigator.pop(context);
                _deleteReminder(reminder);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _rescheduleReminder(Reminder reminder) async {
    try {
      final freeTimes = widget.freeTimeRepository.getAllAsJson();
      final result = await widget.aiService.reschedulePost(
        previousAttemptsJson: '[]',
        category: reminder.categoryEn ?? 'Other',
        complexity: reminder.complexityEn ?? 'Medium',
        importance: reminder.importance,
        userFreeTimesJson: freeTimes.isNotEmpty
            ? '{"free_times": $freeTimes}'
            : null,
      );
      _showResult(true, 'Rescheduled: ${result['newTime']}');

      if (result['newTime'] != null) {
        reminder.scheduledAt = result['newTime'];
        widget.reminderRepository.save(reminder);

        await widget.notificationService.cancelReminder(reminder.id);
        await widget.notificationService.scheduleReminder(reminder);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Rescheduled to ${reminder.scheduledAt}'),
              backgroundColor: AppColors.accent,
            ),
          );
          _loadReminders();
        }
      }
    } catch (e) {
      if (mounted) {
        _showResult(false, 'Error: $e');
      }
    }
  }

  Future<void> _deleteReminder(Reminder reminder) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text(
          'Delete Post?',
          style: TextStyle(color: AppColors.textPrimary),
        ),
        content: const Text(
          'This action cannot be undone.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Delete',
              style: TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await widget.notificationService.cancelReminder(reminder.id);
      widget.reminderRepository.delete(reminder.id);
      _loadReminders();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(
              Icons.bookmark_rounded,
              color: AppColors.accent,
              size: 26,
            ),
            const SizedBox(width: 8),
            Text(
              'Flex Reminder',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 20,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_rounded, color: AppColors.accent),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.accent),
              ),
            )
          : Column(
              children: [
                // Page view
                Expanded(
                  child: PageView(
                    controller: _pageController,
                    onPageChanged: (page) {
                      setState(() => _currentPage = page);
                    },
                    children: [
                      // Unread tab
                      _buildReminderList(_unreadReminders, isUnread: true),
                      // Read tab
                      _buildReminderList(_readReminders, isUnread: false),
                    ],
                  ),
                ),

                // Page indicator
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildDot(0),
                      const SizedBox(width: 8),
                      _buildDot(1),
                    ],
                  ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openSaveSheet(),
        child: const Icon(Icons.add_rounded),
      ),
    );
  }

  Widget _buildDot(int index) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: _currentPage == index ? 24 : 8,
      height: 8,
      decoration: BoxDecoration(
        color: _currentPage == index
            ? AppColors.accent
            : AppColors.textSecondary,
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }

  Widget _buildReminderList(
    List<Reminder> reminders, {
    required bool isUnread,
  }) {
    if (reminders.isEmpty) {
      return EmptyState(
        icon: isUnread
            ? Icons.bookmark_add_outlined
            : Icons.check_circle_outline,
        title: isUnread ? 'No saved posts yet' : 'No read posts yet',
        subtitle: isUnread ? 'Tap + to save your first post' : null,
      );
    }

    return RefreshIndicator(
      onRefresh: () async => _loadReminders(),
      color: AppColors.accent,
      child: ListView.builder(
        padding: const EdgeInsets.only(top: 8, bottom: 80),
        itemCount: reminders.length,
        itemBuilder: (context, index) {
          final reminder = reminders[index];
          return ReminderCard(
            reminder: reminder,
            onTap: () => context.push('/post/${reminder.id}'),
            onLongPress: () => _showContextMenu(reminder),
          );
        },
      ),
    );
  }
}
