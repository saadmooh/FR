import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/ai_service.dart';
import '../services/metadata_service.dart';
import '../services/notification_service.dart';
import '../services/youtube_service.dart';
import '../repositories/reminder_repository.dart';
import '../repositories/free_time_repository.dart';
import '../repositories/category_statistic_repository.dart';
import '../models/reminder.dart';
import '../core/app_theme.dart';
import '../core/constants.dart';
import '../core/locale_manager.dart';
import '../core/translations.dart';

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
  final _youtubeService = YouTubeService();

  String _importance = 'Day';
  bool _isLoading = false;
  String _loadingStatus = '';
  String? _error;

  String get _locale => LocaleManager.instance.getLocale();

  @override
  void initState() {
    super.initState();
    if (widget.initialUrl != null) {
      _urlController.text = widget.initialUrl!;
    }
    _metadataService.setAIService(widget.aiService);
    _metadataService.setYouTubeService(_youtubeService);
    LocaleManager.instance.localeNotifier.addListener(_onLocaleChanged);
  }

  @override
  void dispose() {
    _urlController.dispose();
    LocaleManager.instance.localeNotifier.removeListener(_onLocaleChanged);
    super.dispose();
  }

  void _onLocaleChanged() {
    if (mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    }
  }

  void _showResult(bool success, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: success ? AppColors.accent : AppColors.error,
      ),
    );
  }

  Future<void> _save() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      setState(() => _error = Translations.pleaseEnterUrl(_locale));
      return;
    }

    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      setState(() => _error = Translations.pleaseEnterValidUrl(_locale));
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
      _loadingStatus = Translations.fetchingPostInfo(_locale);
    });

    try {
      // Step 1: Fetch metadata
      final metadata = await _metadataService.fetchMetadata(url);

      if (!mounted) return;
      setState(() => _loadingStatus = Translations.classifyingContent(_locale));

      // Step 2: AI classification
      final classification = await widget.aiService.classifyContent(
        title: metadata.title ?? 'Untitled',
        description: metadata.description,
        availableCategories: AppConstants.availableCategories,
      );

      if (!mounted) return;
      setState(() => _loadingStatus = Translations.findingBestTime(_locale));

      // Step 3: Get free times and pending reminders
      final freeTimes = widget.freeTimeRepository.getAllAsJson();
      final pendingReminders = widget.reminderRepository
          .getPendingReminders()
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

      final scheduledAt =
          bestTimeResult['bestTime'] ?? now.add(const Duration(hours: 24));

      // Get category in all languages
      final categoryData = classification['category'] ?? {};
      final categoryEnVal =
          categoryData['en'] ?? classification['categoryEn'] ?? 'Other';
      final categoryArVal =
          categoryData['ar'] ?? classification['categoryAr'] ?? 'أخرى';
      final categoryFrVal =
          categoryData['fr'] ?? classification['categoryFr'] ?? 'Autre';

      // Get complexity in all languages
      final complexityData = classification['complexity_level'] ?? {};
      final complexityEnVal =
          complexityData['en'] ?? classification['complexityEn'] ?? 'Medium';
      final complexityArVal =
          complexityData['ar'] ?? classification['complexityAr'] ?? 'متوسط';
      final complexityFrVal =
          complexityData['fr'] ?? classification['complexityFr'] ?? 'Moyen';

      // Get ethical reasoning in all languages
      final ethicalData = classification['ethical_reasoning'] ?? '';
      final ethicalParts = ethicalData.toString().split(' | ');
      final ethicalEn = ethicalParts.isNotEmpty ? ethicalParts[0] : '';
      final ethicalAr = ethicalParts.length > 1 ? ethicalParts[1] : '';
      final ethicalFr = ethicalParts.length > 2 ? ethicalParts[2] : '';

      // Get explanation in all languages
      final explanationData = bestTimeResult['explanation'] ?? '';
      final explanationParts = explanationData.toString().split(' | ');
      final explanationEn = explanationParts.isNotEmpty
          ? explanationParts[0]
          : '';
      final explanationAr = explanationParts.length > 1
          ? explanationParts[1]
          : '';
      final explanationFr = explanationParts.length > 2
          ? explanationParts[2]
          : '';

      // Step 5: Save reminder
      final reminder = Reminder(
        url: url,
        title: metadata.title ?? 'Untitled',
        description: metadata.description,
        imageUrl: metadata.ogImage,
        categoryEn: categoryEnVal,
        categoryAr: categoryArVal,
        categoryFr: categoryFrVal,
        complexityEn: complexityEnVal,
        complexityAr: complexityArVal,
        complexityFr: complexityFrVal,
        isEthical:
            classification['is_ethical'] ?? classification['isEthical'] ?? true,
        ethicalReasoning: ethicalEn,
        ethicalReasoningAr: ethicalAr,
        ethicalReasoningFr: ethicalFr,
        importance: _importance,
        scheduledAt: scheduledAt,
        createdAt: now,
        aiExplanation: explanationEn,
        aiExplanationAr: explanationAr,
        aiExplanationFr: explanationFr,
      );

      // Add playlist-specific fields if this is a playlist
      if (metadata.isPlaylist) {
        reminder.isPlaylist = true;
        reminder.playlistId = metadata.playlistId;
        reminder.playlistCurrentIndex = 0;
        reminder.playlistTotalItems = metadata.totalVideos;
        reminder.currentVideoUrl = url;
      }

      final id = widget.reminderRepository.save(reminder);
      reminder.id = id;

      // Step 6: Record statistics
      widget.categoryStatRepository.recordSaved(reminder);

      // Step 7: Schedule notification
      await widget.notificationService.scheduleReminder(reminder);

      if (!mounted) return;

      setState(() => _loadingStatus = Translations.reminderSaved(_locale));

      widget.onSaved();
      Navigator.of(context).pop();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${Translations.reminderSaved(_locale)} ${Translations.reminderScheduledFor(_locale)} ${_formatDateTime(scheduledAt)}',
          ),
          backgroundColor: AppColors.accent,
        ),
      );
    } catch (e) {
      if (mounted) {
        _showResult(false, Translations.errorOccurred(_locale));
        setState(() {
          _error = '${Translations.errorSavingPost(_locale)}: $e';
          _isLoading = false;
        });
      }
    }
  }

  String _formatDateTime(DateTime dt) {
    final formatStr = Translations.dateTimeFormat(_locale);
    return DateFormat(formatStr).format(dt);
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
                  borderRadius: BorderRadius.zero,
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Title
            Text(
              Translations.savePost(_locale),
              style: const TextStyle(
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
              decoration: InputDecoration(
                hintText: Translations.enterUrl(_locale),
                hintStyle: const TextStyle(color: AppColors.textSecondary),
                prefixIcon: const Icon(
                  Icons.link,
                  color: AppColors.textSecondary,
                ),
                suffixIcon: const Icon(
                  Icons.paste,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Importance dropdown
            DropdownButtonFormField<String>(
              value: _importance,
              dropdownColor: AppColors.surface,
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: InputDecoration(
                labelText: Translations.whenToRemind(_locale),
              ),
              items: [
                DropdownMenuItem(
                  value: 'Day',
                  child: Text(Translations.today(_locale)),
                ),
                DropdownMenuItem(
                  value: 'Week',
                  child: Text(Translations.thisWeek(_locale)),
                ),
                DropdownMenuItem(
                  value: 'Month',
                  child: Text(Translations.thisMonth(_locale)),
                ),
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
                      valueColor: AlwaysStoppedAnimation<Color>(
                        AppColors.accent,
                      ),
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
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
              ),
              child: Text(
                Translations.save(_locale),
                style: const TextStyle(
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
