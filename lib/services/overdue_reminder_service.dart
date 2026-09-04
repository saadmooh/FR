import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../models/reminder.dart';
import '../repositories/reminder_repository.dart';
import '../repositories/free_time_repository.dart';
import '../services/ai_service.dart';
import '../services/notification_service.dart';
import '../services/reschedule_lock_service.dart';
import '../services/reschedule_policy.dart';
import '../services/workmanager_service.dart';
import '../core/ui_messenger.dart';

/// Service responsible for detecting and rescheduling overdue reminders.
///
/// This service runs when the app starts or returns to the foreground,
/// checking all active (unopened) reminders and rescheduling those
/// whose scheduled time has passed using the existing AI rescheduling system.
class OverdueReminderService {
  final ReminderRepository _reminderRepository;
  final FreeTimeRepository _freeTimeRepository;
  final AIService _aiService;
  final NotificationService _notificationService;
  final RescheduleLockService _lockService;

  bool _isProcessing = false;
  DateTime? _lastProcessedTime;
  final Set<int> _processingReminders = {};

  OverdueReminderService({
    required ReminderRepository reminderRepository,
    required FreeTimeRepository freeTimeRepository,
    required AIService aiService,
    required NotificationService notificationService,
    required RescheduleLockService lockService,
  }) : _reminderRepository = reminderRepository,
       _freeTimeRepository = freeTimeRepository,
       _aiService = aiService,
       _notificationService = notificationService,
       _lockService = lockService;

  /// Processes all overdue reminders.
  ///
  /// Returns the number of reminders successfully rescheduled.
  /// Safe to call multiple times - uses locks to prevent duplicate processing.
  Future<int> reviewOverdueReminders() async {
    if (_isProcessing) {
      debugPrint(
        '[OverdueReminderService] Already processing, skipping duplicate call',
      );
      return 0;
    }

    // Prevent rapid repeated calls within 5 seconds
    final now = DateTime.now();
    if (_lastProcessedTime != null &&
        now.difference(_lastProcessedTime!) < const Duration(seconds: 5)) {
      debugPrint('[OverdueReminderService] Called too recently, skipping');
      return 0;
    }

    _isProcessing = true;
    _lastProcessedTime = now;

    try {
      final currentTime = DateTime.now();
      debugPrint(
        '[OverdueReminderService] Current device time: ${currentTime.toIso8601String()}',
      );

      // Get all unread reminders (not opened, not deleted)
      final allUnread = _reminderRepository.getAllUnread();
      debugPrint(
        '[OverdueReminderService] Total unread reminders: ${allUnread.length}',
      );

      // Filter overdue reminders (with 2-minute grace period)
      final overdueReminders = allUnread
          .where((r) => isOverdue(r, currentTime))
          .toList();

      debugPrint(
        '[OverdueReminderService] Found ${overdueReminders.length} overdue reminders (with 2-min grace period)',
      );

      if (overdueReminders.isEmpty) {
        return 0;
      }

      // Log overdue reminders
      for (final reminder in overdueReminders) {
        debugPrint(
          '[OverdueReminderService] Overdue: id=${reminder.id}, title="${reminder.title}", scheduledAt=${reminder.scheduledAt.toIso8601String()}, importance=${reminder.importance}, rescheduleAttempts=${reminder.rescheduleAttempts}',
        );
      }

      // Process overdue reminders in bounded batches per cycle. The remainder
      // stays unread and is picked up by the next app start/resume, keeping
      // AI cost and latency predictable even with many overdue reminders.
      const batchLimit = 5;
      final batchToProcess = overdueReminders.take(batchLimit).toList();
      if (overdueReminders.length > batchLimit) {
        debugPrint(
          '[OverdueReminderService] ${overdueReminders.length - batchLimit} overdue reminders deferred to next cycle',
        );
      }

      // Process each overdue reminder
      int rescheduledCount = 0;
      for (final reminder in batchToProcess) {
        try {
          final success = await _rescheduleOverdueReminder(
            reminder,
            currentTime,
          );
          if (success) {
            rescheduledCount++;
          }
        } catch (e, stackTrace) {
          debugPrint(
            '[OverdueReminderService] Failed to reschedule reminder ${reminder.id}: $e',
          );
          debugPrint('Stack trace: $stackTrace');
          showUiLog(
            'Failed to reschedule "${reminder.title}": $e',
            duration: const Duration(seconds: 6),
          );
          // Lock is released in finally block of _rescheduleOverdueReminder
          // Continue with other reminders
        }
      }

      debugPrint(
        '[OverdueReminderService] Successfully rescheduled $rescheduledCount of ${batchToProcess.length} overdue reminders (batch)',
      );
      return rescheduledCount;
    } finally {
      _isProcessing = false;
    }
  }

  /// Reschedules a single overdue reminder using the existing AI rescheduling system.
  Future<bool> _rescheduleOverdueReminder(
    Reminder reminder,
    DateTime currentTime,
  ) async {
    // Check if reminder is too old (>30 days)
    if (reminder.scheduledAt.isBefore(
      currentTime.subtract(const Duration(days: 30)),
    )) {
      debugPrint(
        '[OverdueReminderService] Reminder ${reminder.id} is too old (>30 days), skipping',
      );
      showUiLog(
        '"${reminder.title}" is too old (>30 days), not rescheduled',
        duration: const Duration(seconds: 6),
      );
      return false;
    }

    // Race guard: try to acquire atomic lock via ObjectBox transaction
    final bool alreadyProcessing = _processingReminders.contains(reminder.id);
    if (!_lockService.acquireLock(reminder.id)) {
      debugPrint(
        '[OverdueReminderService] ⚠️ [RaceGuard] Another reschedule in progress for reminder ${reminder.id}, skipping',
      );
      if (!alreadyProcessing) {
        showUiLog(
          'Reschedule in progress for "${reminder.title}", skipping',
          duration: const Duration(seconds: 4),
        );
      }
      return false;
    }
    _processingReminders.add(reminder.id);
    debugPrint(
      '[OverdueReminderService] 🔒 [RaceGuard] Acquired reschedule lock for reminder ${reminder.id}',
    );

    try {
      // Get reminder history for AI context
      final previousAttempts = _reminderRepository
          .getReminderHistory(reminder.id)
          .map(
            (r) => {
              'scheduled_at': r.scheduledAt.toIso8601String(),
              'opened': r.isOpened,
              'opened_at': r.openedAt?.toIso8601String(),
            },
          )
          .toList();

      // Get free times
      final freeTimes = _freeTimeRepository.getAllAsJson();
      debugPrint(
        '[OverdueReminderService] Free times count: ${freeTimes.length}',
      );

      // Call AI for rescheduling
      debugPrint(
        '[OverdueReminderService] Calling AI for reschedule: id=${reminder.id}, category=${reminder.categoryEn}, complexity=${reminder.complexityEn}, importance=${reminder.importance}',
      );

      Map<String, dynamic> result;
      try {
        result = await _aiService.reschedulePost(
          previousAttemptsJson: jsonEncode(previousAttempts),
          category: reminder.categoryEn ?? 'Other',
          complexity: reminder.complexityEn ?? 'Medium',
          importance: reminder.importance,
          userFreeTimesJson: freeTimes.isNotEmpty
              ? '{"free_times": $freeTimes}'
              : null,
          currentTime: currentTime,
        );
      } catch (e, stackTrace) {
        debugPrint(
          '[OverdueReminderService] AI call failed for reminder ${reminder.id}: $e — keeping time, retrying in 30 minutes',
        );
        debugPrint('Stack trace: $stackTrace');
        showUiLog(
          'AI reschedule failed for "${reminder.title}", will retry in 30 min',
          duration: const Duration(seconds: 6),
        );
        await _scheduleAiRetry(reminder.id);
        return false;
      }

      // CRITICAL: Re-fetch reminder from DB after AI call to check isOpened
      final freshReminder = _reminderRepository.getById(reminder.id);
      if (freshReminder == null || freshReminder.isOpened) {
        debugPrint(
          '[OverdueReminderService] Reminder ${reminder.id} was opened or deleted during AI processing, aborting',
        );
        _lockService.releaseLock(reminder.id);
        debugPrint(
          '[OverdueReminderService] 🔓 [RaceGuard] Released reschedule lock for reminder ${reminder.id}',
        );
        return true;
      }

      final newTime = result['newTime'] as DateTime?;
      if (newTime == null) {
        debugPrint(
          '[OverdueReminderService] AI returned null time for reminder ${reminder.id}',
        );
        showUiLog(
          'AI returned invalid time for "${reminder.title}", will retry in 30 min',
          duration: const Duration(seconds: 6),
        );
        await _scheduleAiRetry(reminder.id);
        return false;
      }

      // Validate new time is in the future and within deadline
      final deadline = reschedulingDeadline(currentTime, reminder.importance);
      final finalTime = clampRescheduleTime(newTime, currentTime, deadline);

      // Update reminder fields (using freshReminder to preserve any concurrent changes)
      freshReminder.scheduledAt = finalTime;
      freshReminder.rescheduleAttempts++;
      final reason = result['reason'] as String? ?? '';
      final reasonParts = reason.split(' | ');
      freshReminder.aiExplanation = reasonParts.isNotEmpty
          ? reasonParts[0]
          : reason;
      freshReminder.aiExplanationAr = reasonParts.length > 1
          ? reasonParts[1]
          : '';
      freshReminder.isOpened = false;
      freshReminder.openedAt = null;

      // Save to database
      _reminderRepository.save(freshReminder);
      debugPrint(
        '[OverdueReminderService] Reminder ${reminder.id} saved with new scheduledAt: ${freshReminder.scheduledAt.toIso8601String()}',
      );

      // Update notification
      await _notificationService.cancelReminder(reminder.id);
      await _notificationService.scheduleReminder(freshReminder);
      debugPrint(
        '[OverdueReminderService] Notification updated for reminder ${reminder.id}',
      );

      return true;
    } catch (e, stackTrace) {
      debugPrint(
        '[OverdueReminderService] Failed to reschedule reminder ${reminder.id}: $e',
      );
      debugPrint('Stack trace: $stackTrace');
      showUiLog(
        'Reschedule failed for "${reminder.title}": $e',
        duration: const Duration(seconds: 6),
      );
      rethrow;
    } finally {
      _processingReminders.remove(reminder.id);
      _lockService.releaseLock(reminder.id);
      debugPrint(
        '[OverdueReminderService] 🔓 [RaceGuard] Released reschedule lock for reminder ${reminder.id}',
      );
    }
  }

  /// Validates that a scheduled time is in the future.
  ///
  /// Throws [ArgumentError] if the time is not in the future.
  static void validateFutureDateTime(DateTime scheduledAt) {
    final now = DateTime.now();
    if (!scheduledAt.isAfter(now)) {
      throw ArgumentError(
        'Scheduled time must be in the future. '
        'Provided: ${scheduledAt.toIso8601String()}, Current: ${now.toIso8601String()}',
      );
    }
  }

  /// Checks if a reminder is overdue.
  /// Uses a 2-minute grace period to avoid racing with WorkManager.
  static bool isOverdue(Reminder reminder, [DateTime? currentTime]) {
    final now = currentTime ?? DateTime.now();
    return !reminder.isOpened &&
        reminder.scheduledAt.isBefore(now.subtract(const Duration(minutes: 2)));
  }

  /// Re-queues the AI rescheduling task so it is retried in 30 minutes.
  /// The reminder's scheduled time is left unchanged.
  Future<void> _scheduleAiRetry(int reminderId) async {
    try {
      await scheduleAiRescheduleRetry(reminderId);
      debugPrint(
        '[OverdueReminderService] Scheduled AI reschedule retry for reminder $reminderId in 30 minutes',
      );
    } catch (e) {
      debugPrint(
        '[OverdueReminderService] Failed to schedule AI retry for reminder $reminderId: $e',
      );
    }
  }
}
