import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/ai_service.dart';
import '../services/metadata_service.dart';
import '../services/notification_service.dart';
import '../repositories/reminder_repository.dart';
import '../repositories/free_time_repository.dart';
import '../repositories/category_statistic_repository.dart';
import '../models/reminder.dart';
import '../core/app_theme.dart';
import '../core/constants.dart';

class SavePostSheet extends StatefulWidget {
  final String? initialUrl;
  final ReminderRepository reminderRepository;
  final FreeTimeRepository freeTimeRepository;
  final CategoryStatisticRepository categoryStatRepository;
  final NotificationService notificationService;
  final AIService aiService;
  final VoidCallback onSaved;

  const SavePostSheet({
    super.key,
    this.initialUrl,
    required this.reminderRepository,
    required this.freeTimeRepository,
    required this.categoryStatRepository,
    required this.notificationService,
    required this.aiService,
    required this.onSaved,
  });

  @override
  State<SavePostSheet> createState() => _SavePostSheetState();
}

class _SavePostSheetState extends State<SavePostSheet> {
  final _urlController = TextEditingController();
  final _metadataService = MetadataService();
  
  String _importance = 'Day';
  bool _isLoading = false;
  String _loadingStatus = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.initialUrl != null) {
      _urlController.text = widget.initialUrl!;
    }
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      setState(() => _error = 'Please enter a URL');
      return;
    }

    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      setState(() => _error = 'Please enter a valid URL');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
      _loadingStatus = '🔍 Fetching post info...';
    });

    try {
      // Step 1: Fetch metadata
      final metadata = await _metadataService.fetchMetadata(url);
      
      if (!mounted) return;
      setState(() => _loadingStatus = '🧠 Classifying content...');

      // Step 2: AI classification
      final classification = await widget.aiService.classifyContent(
        title: metadata.title ?? 'Untitled',
        description: metadata.description,
        availableCategories: AppConstants.availableCategories,
      );

      if (!mounted) return;
      setState(() => _loadingStatus = '⏰ Finding best time...');

      // Step 3: Get free times and pending reminders
      final freeTimes = widget.freeTimeRepository.getAllAsJson();
      final pendingReminders = widget.reminderRepository.getPendingReminders()
          .map((r) => {'scheduledAt': r.scheduledAt.toIso8601String()})
          .toList();

      // Calculate deadline based on importance
      final now = DateTime.now();
      final maxTime = switch (_importance) {
        'Day' => now.add(const Duration(days: 1)),
        'Week' => now.add(const Duration(days: 7)),
        'Month' => now.add(const Duration(days: 30)),
        _ => now.add(const Duration(days: 7)),
      };

      // Step 4: Estimate best time
      final bestTimeResult = await widget.aiService.estimateBestTime(
        category: classification['categoryEn'] ?? 'Other',
        complexity: classification['complexityEn'] ?? 'Medium',
        importance: _importance,
        currentTime: now,
        maxTime: maxTime,
        userFreeTimesJson: jsonEncode(freeTimes),
        pendingRemindersJson: jsonEncode(pendingReminders),
      );

      if (!mounted) return;

      final scheduledAt = bestTimeResult['bestTime'] ?? now.add(const Duration(hours: 24));
      final explanation = bestTimeResult['explanation'] ?? '';

      // Step 5: Save reminder
      final reminder = Reminder(
        url: url,
        title: metadata.title ?? 'Untitled',
        description: metadata.description,
        imageUrl: metadata.ogImage,
        categoryEn: classification['categoryEn'],
        categoryAr: classification['categoryAr'],
        complexityEn: classification['complexityEn'],
        complexityAr: classification['complexityAr'],
        isEthical: classification['isEthical'] ?? true,
        ethicalReasoning: classification['ethicalReasoning'],
        importance: _importance,
        scheduledAt: scheduledAt,
        createdAt: now,
        aiExplanation: explanation,
      );

      final id = widget.reminderRepository.save(reminder);
      reminder.id = id;

      // Step 6: Record statistics
      widget.categoryStatRepository.recordSaved(reminder);

      // Step 7: Schedule notification
      await widget.notificationService.scheduleReminder(reminder);

      if (!mounted) return;

      setState(() => _loadingStatus = '✅ Reminder saved!');

      widget.onSaved();
      Navigator.of(context).pop();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ Reminder scheduled for ${_formatDateTime(scheduledAt)}'),
          backgroundColor: AppColors.accent,
        ),
      );

    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Error saving post: $e';
          _isLoading = false;
        });
      }
    }
  }

  String _formatDateTime(DateTime dt) {
    return '${dt.day}/${dt.month} at ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.textSecondary.withAlpha(128),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Title
            const Text(
              'Save a Post',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 20),

            // URL field
            TextField(
              controller: _urlController,
              autofocus: widget.initialUrl != null,
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: const InputDecoration(
                hintText: 'Enter URL...',
                hintStyle: TextStyle(color: AppColors.textSecondary),
                prefixIcon: Icon(Icons.link, color: AppColors.textSecondary),
                suffixIcon: Icon(Icons.paste, color: AppColors.textSecondary),
              ),
            ),
            const SizedBox(height: 16),

            // Importance dropdown
            DropdownButtonFormField<String>(
              value: _importance,
              dropdownColor: AppColors.surface,
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: const InputDecoration(
                labelText: 'When to remind',
              ),
              items: const [
                DropdownMenuItem(value: 'Day', child: Text('Today (اليوم)')),
                DropdownMenuItem(value: 'Week', child: Text('This Week (هذا الأسبوع)')),
                DropdownMenuItem(value: 'Month', child: Text('This Month (هذا الشهر)')),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() => _importance = value);
                }
              },
            ),
            const SizedBox(height: 16),

            // Error message
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(
                  _error!,
                  style: const TextStyle(color: AppColors.error),
                ),
              ),

            // Loading indicator
            if (_isLoading) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(AppColors.accent),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    _loadingStatus,
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],

            // Save button
            ElevatedButton(
              onPressed: _isLoading ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: AppColors.background,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'Save',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
