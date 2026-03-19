import 'dart:convert';
import 'package:flutter/material.dart';
import '../models/reminder.dart';
import '../repositories/reminder_repository.dart';
import '../repositories/free_time_repository.dart';
import '../services/notification_service.dart';
import '../services/ai_service.dart';
import '../core/app_theme.dart';

class EditReminderScreen extends StatefulWidget {
  final Reminder reminder;
  final ReminderRepository reminderRepository;
  final FreeTimeRepository freeTimeRepository;
  final NotificationService notificationService;
  final AIService aiService;
  final VoidCallback onSaved;

  const EditReminderScreen({
    super.key,
    required this.reminder,
    required this.reminderRepository,
    required this.freeTimeRepository,
    required this.notificationService,
    required this.aiService,
    required this.onSaved,
  });

  @override
  State<EditReminderScreen> createState() => _EditReminderScreenState();
}

class _EditReminderScreenState extends State<EditReminderScreen> {
  late DateTime _selectedDate;
  late TimeOfDay _selectedTime;
  late String _selectedImportance;
  bool _isRescheduling = false;

  final ValueNotifier<DateTime> _scheduledAtNotifier = ValueNotifier<DateTime>(
    DateTime.now(),
  );

  static const List<String> _importanceOptions = ['Day', 'Week', 'Month'];

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.reminder.scheduledAt;
    _selectedTime = TimeOfDay.fromDateTime(widget.reminder.scheduledAt);
    _selectedImportance = widget.reminder.importance;
    _scheduledAtNotifier.value = widget.reminder.scheduledAt;
  }

  @override
  void dispose() {
    _scheduledAtNotifier.dispose();
    super.dispose();
  }

  DateTime get _combinedDateTime {
    return DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      _selectedTime.hour,
      _selectedTime.minute,
    );
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: AppColors.accent,
              surface: AppColors.whiteSurface,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
      _scheduledAtNotifier.value = _combinedDateTime;
    }
  }

  Future<void> _selectTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime,
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: AppColors.accent,
              surface: AppColors.whiteSurface,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() => _selectedTime = picked);
      _scheduledAtNotifier.value = _combinedDateTime;
    }
  }

  Future<void> _rescheduleWithAI() async {
    if (!widget.aiService.hasApiKey()) {
      _showSnackBar('Please configure AI API key in settings', isError: true);
      return;
    }

    setState(() => _isRescheduling = true);

    try {
      final currentTime = DateTime.now();
      DateTime maxTime;

      switch (_selectedImportance) {
        case 'Day':
          maxTime = currentTime.add(const Duration(days: 1));
          break;
        case 'Week':
          maxTime = currentTime.add(const Duration(days: 7));
          break;
        case 'Month':
          maxTime = currentTime.add(const Duration(days: 30));
          break;
        default:
          maxTime = currentTime.add(const Duration(days: 7));
      }

      final freeTimes = widget.freeTimeRepository.getAllAsJson();
      final pendingReminders = widget.reminderRepository
          .getPendingReminders()
          .map(
            (r) => {
              'scheduledAt': r.scheduledAt.toIso8601String(),
              'title': r.title,
            },
          )
          .toList();

      final result = await widget.aiService.estimateBestTime(
        category: widget.reminder.categoryEn ?? 'Other',
        complexity: widget.reminder.complexityEn ?? 'Medium',
        importance: _selectedImportance,
        currentTime: currentTime,
        maxTime: maxTime,
        userFreeTimesJson: freeTimes.isNotEmpty ? jsonEncode(freeTimes) : null,
        pendingRemindersJson: pendingReminders.isNotEmpty
            ? jsonEncode(pendingReminders)
            : null,
      );

      final bestTime = result['bestTime'] as DateTime?;
      if (bestTime != null) {
        setState(() {
          _selectedDate = bestTime;
          _selectedTime = TimeOfDay.fromDateTime(bestTime);
        });
        _scheduledAtNotifier.value = _combinedDateTime;
        _showSnackBar(
          'AI suggested: ${result['explanation'] ?? 'New time scheduled'}',
        );
      } else {
        _showSnackBar('Could not find optimal time', isError: true);
      }
    } catch (e) {
      _showSnackBar('AI reschedule failed: $e', isError: true);
    } finally {
      setState(() => _isRescheduling = false);
    }
  }

  Future<void> _saveChanges() async {
    final updatedReminder = widget.reminder;
    updatedReminder.scheduledAt = _combinedDateTime;
    updatedReminder.importance = _selectedImportance;

    widget.reminderRepository.save(updatedReminder);

    await widget.notificationService.cancelReminder(updatedReminder.id);
    await widget.notificationService.scheduleReminder(updatedReminder);

    widget.onSaved();

    if (mounted) {
      _showSnackBar('Reminder updated successfully');
      Navigator.of(context).pop();
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppColors.error : AppColors.accent,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.whiteBackground,
      appBar: AppBar(
        backgroundColor: AppColors.whiteBackground,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.accent),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Edit Reminder',
          style: TextStyle(
            color: AppColors.whiteTextPrimary,
            fontWeight: FontWeight.w700,
            fontSize: 22,
          ),
        ),
        actions: [
          TextButton(
            onPressed: _saveChanges,
            child: const Text(
              'Save',
              style: TextStyle(
                color: AppColors.accent,
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.whiteSurface,
                borderRadius: BorderRadius.zero,
                border: Border.all(color: AppColors.whiteBorder, width: 1),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.article, color: AppColors.accent),
                      SizedBox(width: 8),
                      Text(
                        'Reminder',
                        style: TextStyle(
                          color: AppColors.whiteTextPrimary,
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    widget.reminder.title,
                    style: const TextStyle(
                      color: AppColors.whiteTextSecondary,
                      fontSize: 14,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.whiteSurface,
                borderRadius: BorderRadius.zero,
                border: Border.all(color: AppColors.whiteBorder, width: 1),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.calendar_today, color: AppColors.accent),
                      SizedBox(width: 8),
                      Text(
                        'Schedule',
                        style: TextStyle(
                          color: AppColors.whiteTextPrimary,
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: _selectDate,
                          borderRadius: BorderRadius.zero,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.whiteBackground,
                              borderRadius: BorderRadius.zero,
                              border: Border.all(
                                color: AppColors.whiteBorder,
                                width: 1,
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.calendar_month,
                                  color: AppColors.whiteTextSecondary,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year}',
                                  style: const TextStyle(
                                    color: AppColors.whiteTextPrimary,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: InkWell(
                          onTap: _selectTime,
                          borderRadius: BorderRadius.zero,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.whiteBackground,
                              borderRadius: BorderRadius.zero,
                              border: Border.all(
                                color: AppColors.whiteBorder,
                                width: 1,
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.access_time,
                                  color: AppColors.whiteTextSecondary,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  _selectedTime.format(context),
                                  style: const TextStyle(
                                    color: AppColors.whiteTextPrimary,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ValueListenableBuilder<DateTime>(
                    valueListenable: _scheduledAtNotifier,
                    builder: (context, value, child) {
                      return Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.whiteBackground,
                          borderRadius: BorderRadius.zero,
                          border: Border.all(
                            color: AppColors.whiteBorder,
                            width: 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.schedule,
                              color: AppColors.accent,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Scheduled for: ${_formatDateTime(value)}',
                              style: const TextStyle(
                                color: AppColors.whiteTextPrimary,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.whiteSurface,
                borderRadius: BorderRadius.zero,
                border: Border.all(color: AppColors.whiteBorder, width: 1),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.flag, color: AppColors.accent),
                      SizedBox(width: 8),
                      Text(
                        'Importance',
                        style: TextStyle(
                          color: AppColors.whiteTextPrimary,
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SegmentedButton<String>(
                    segments: _importanceOptions
                        .map(
                          (option) => ButtonSegment<String>(
                            value: option,
                            label: Text(option),
                            icon: Icon(
                              option == 'Day'
                                  ? Icons.today
                                  : option == 'Week'
                                  ? Icons.date_range
                                  : Icons.calendar_month,
                            ),
                          ),
                        )
                        .toList(),
                    selected: {_selectedImportance},
                    onSelectionChanged: (selection) {
                      setState(() {
                        _selectedImportance = selection.first;
                      });
                    },
                    style: ButtonStyle(
                      backgroundColor: WidgetStateProperty.resolveWith((
                        states,
                      ) {
                        if (states.contains(WidgetState.selected)) {
                          return AppColors.accent;
                        }
                        return AppColors.whiteBackground;
                      }),
                      foregroundColor: WidgetStateProperty.resolveWith((
                        states,
                      ) {
                        if (states.contains(WidgetState.selected)) {
                          return AppColors.whiteBackground;
                        }
                        return AppColors.whiteTextPrimary;
                      }),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _getImportanceDescription(_selectedImportance),
                    style: const TextStyle(
                      color: AppColors.whiteTextSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isRescheduling ? null : _rescheduleWithAI,
                icon: _isRescheduling
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.whiteBackground,
                        ),
                      )
                    : const Icon(Icons.auto_awesome),
                label: Text(
                  _isRescheduling ? 'AI Rescheduling...' : 'AI Reschedule',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: AppColors.whiteBackground,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.zero,
                  ),
                  elevation: 0,
                  shadowColor: Colors.transparent,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'AI will find the optimal time based on your free times and the selected importance.',
              style: TextStyle(
                color: AppColors.whiteTextSecondary,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDateTime(DateTime dt) {
    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final hour = dt.hour.toString().padLeft(2, '0');
    final minute = dt.minute.toString().padLeft(2, '0');
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year} at $hour:$minute';
  }

  String _getImportanceDescription(String importance) {
    switch (importance) {
      case 'Day':
        return 'Complete within today (within 24 hours)';
      case 'Week':
        return 'Complete within this week (within 7 days)';
      case 'Month':
        return 'Complete within this month (within 30 days)';
      default:
        return '';
    }
  }
}
