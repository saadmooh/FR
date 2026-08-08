import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;
import '../services/ai_service.dart';
import '../services/metadata_service.dart';
import '../services/notification_service.dart';
import '../services/youtube_service.dart';
import '../repositories/reminder_repository.dart';
import '../repositories/free_time_repository.dart';
import '../repositories/category_statistic_repository.dart';
import '../models/reminder.dart';
import '../models/ai_proxy_response.dart';
import '../core/app_theme.dart';
import '../core/constants.dart';
import '../core/locale_manager.dart';
import '../core/translations.dart';
import '../core/app_config.dart';

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
  bool _retrying = false;

  String get _locale => LocaleManager.instance.getLocale();

  Future<void> _refreshSupabaseSession() async {
    if (!AppConfig.isSupabaseConfigured) return;
    final firebaseUser = firebase_auth.FirebaseAuth.instance.currentUser;
    if (firebaseUser == null) return;
    try {
      final idToken = await firebaseUser.getIdToken();
      if (idToken != null) {
        await supabase.Supabase.instance.client.auth.signInWithIdToken(
          provider: const supabase.OAuthProvider('custom:firebase'),
          idToken: idToken,
        );
        debugPrint('Supabase session refreshed from Firebase user');
      }
    } catch (e) {
      debugPrint('Failed to refresh Supabase session: $e');
      rethrow;
    }
  }

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
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
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
      final metadata = await _metadataService.fetchMetadata(url);

      if (!mounted) return;
      setState(() => _loadingStatus = Translations.classifyingContent(_locale));

      final classification = await widget.aiService.classifyContent(
        title: metadata.title ?? 'Untitled',
        description: metadata.description,
        availableCategories: AppConstants.availableCategories,
      );

      if (!mounted) return;
      setState(() => _loadingStatus = Translations.findingBestTime(_locale));

      final freeTimes = widget.freeTimeRepository.getAllAsJson();
      final pendingReminders = widget.reminderRepository
          .getPendingReminders()
          .map((r) => {'scheduledAt': r.scheduledAt.toIso8601String()})
          .toList();

      final now = DateTime.now();
      final maxTime = switch (_importance) {
        'Day' => now.add(const Duration(days: 1)),
        'Week' => now.add(const Duration(days: 7)),
        'Month' => now.add(const Duration(days: 30)),
        _ => now.add(const Duration(days: 7)),
      };

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

      final scheduledAt = bestTimeResult['bestTime'] ??
          now.add(const Duration(hours: 24));

      final categoryData = classification['category'] ?? {};
      final categoryEnVal =
          categoryData['en'] ?? classification['categoryEn'] ?? 'Other';
      final categoryArVal =
          categoryData['ar'] ?? classification['categoryAr'] ?? 'أخرى';
      final categoryFrVal =
          categoryData['fr'] ?? classification['categoryFr'] ?? 'Autre';

      final complexityData = classification['complexity_level'] ?? {};
      final complexityEnVal =
          complexityData['en'] ?? classification['complexityEn'] ?? 'Medium';
      final complexityArVal =
          complexityData['ar'] ?? classification['complexityAr'] ?? 'متوسط';
      final complexityFrVal =
          complexityData['fr'] ?? classification['complexityFr'] ?? 'Moyen';

      final ethicalData = classification['ethical_reasoning'] ?? '';
      final ethicalParts = ethicalData.toString().split(' | ');
      final ethicalEn = ethicalParts.isNotEmpty ? ethicalParts[0] : '';
      final ethicalAr = ethicalParts.length > 1 ? ethicalParts[1] : '';
      final ethicalFr = ethicalParts.length > 2 ? ethicalParts[2] : '';

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
        isEthical: classification['is_ethical'] ??
            classification['isEthical'] ??
            true,
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

      if (metadata.isPlaylist) {
        reminder.isPlaylist = true;
        reminder.playlistId = metadata.playlistId;
        reminder.playlistTitle = metadata.title;
        reminder.playlistThumbnail = metadata.ogImage;
        reminder.playlistCurrentIndex = 0;
        reminder.playlistTotalItems = metadata.totalVideos;

        reminder.currentVideoUrl = metadata.firstVideoUrl ?? url;

        if (metadata.firstVideoThumbnail != null) {
          reminder.imageUrl = metadata.firstVideoThumbnail;
        }
      }

      final id = widget.reminderRepository.save(reminder);
      reminder.id = id;

      widget.categoryStatRepository.recordSaved(reminder);

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
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        ),
      );
    } catch (e) {
      // Handle 401 UNAUTHENTICATED by trying to refresh Supabase session
      if (e is AiProxyException &&
          e.statusCode == 401 &&
          e.code == 'UNAUTHENTICATED' &&
          !_retrying &&
          mounted) {
        try {
          setState(() {
            _retrying = true;
            _loadingStatus = Translations.refreshingSession(_locale);
          });
          await _refreshSupabaseSession();
          // Retry the save operation
          await _save();
          return;
        } catch (refreshError) {
          // If refresh fails, fall through to show error
          debugPrint('Session refresh failed: $refreshError');
        }
      }

      if (mounted) {
        String errorMessage;
        if (e is AiProxyException) {
          if (e.statusCode == 401 && e.code == 'UNAUTHENTICATED') {
            errorMessage =
                '${Translations.errorSavingPost(_locale)}: ${Translations.pleaseSignInAgain(_locale)}';
          } else if (e.code == 'INTEGRITY_FAILED' || e.code == 'INTEGRITY_MISSING') {
            // Google Play Integrity error - distinguish from Supabase errors
            final source = e.code == 'INTEGRITY_FAILED' 
                ? 'Google Play Integrity' 
                : 'App Integrity Check';
            errorMessage =
                '${Translations.errorSavingPost(_locale)}: [$source] ${e.message}\nCode: ${e.code}\nStatus: ${e.statusCode}';
          } else if (e.code.startsWith('UPSTREAM_') || e.code == 'BAD_RESPONSE' || e.code == 'UNKNOWN') {
            // Supabase/Edge Function errors
            errorMessage =
                '${Translations.errorSavingPost(_locale)}: [Supabase/Edge Function] ${e.message}\nCode: ${e.code}\nStatus: ${e.statusCode}';
          } else if (e.code.startsWith('RATE_LIMIT')) {
            // Rate limiting from Supabase
            errorMessage =
                '${Translations.errorSavingPost(_locale)}: [Rate Limit] ${e.message}\nCode: ${e.code}\nStatus: ${e.statusCode}';
          } else {
            errorMessage =
                '${Translations.errorSavingPost(_locale)}: ${e.message}\nCode: ${e.code}\nStatus: ${e.statusCode}\nRetryable: ${e.isRetryable}';
          }
        } else {
          errorMessage = '${Translations.errorSavingPost(_locale)}: $e';
        }
        _showResult(false, errorMessage);
        setState(() {
          _error = errorMessage;
          _isLoading = false;
          _retrying = false;
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
        color: AppColors.whiteBackground,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.whiteTextSecondary.withAlpha(128),
                  borderRadius: BorderRadius.zero,
                ),
              ),
            ),
            const SizedBox(height: 20),

            Text(
              Translations.savePost(_locale),
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: AppColors.whiteTextPrimary,
                  ),
            ),
            const SizedBox(height: 20),

            TextField(
              controller: _urlController,
              autofocus: widget.initialUrl != null,
              style: TextStyle(color: AppColors.whiteTextPrimary),
              decoration: InputDecoration(
                hintText: Translations.enterUrl(_locale),
                hintStyle:
                    TextStyle(color: AppColors.whiteTextSecondary),
                prefixIcon: const Icon(
                  Icons.link,
                  color: AppColors.whiteTextSecondary,
                ),
                suffixIcon: const Icon(
                  Icons.paste,
                  color: AppColors.whiteTextSecondary,
                ),
                enabledBorder: OutlineInputBorder(
                  borderSide: const BorderSide(
                    color: AppColors.whiteTextSecondary,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide:
                      const BorderSide(color: AppColors.whiteAccent),
                ),
              ),
            ),
            const SizedBox(height: 16),

            DropdownButtonFormField<String>(
              initialValue: _importance,
              dropdownColor: AppColors.whiteSurface,
              style: TextStyle(color: AppColors.whiteTextPrimary),
              decoration: const InputDecoration(
                labelStyle: TextStyle(color: AppColors.whiteTextSecondary),
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

            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(
                  _error!,
                  style: const TextStyle(color: AppColors.error),
                ),
              ),

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
                    style: TextStyle(color: AppColors.whiteTextSecondary),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],

            ElevatedButton(
              onPressed: _isLoading ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.whiteAccent,
                foregroundColor: AppColors.whiteBackground,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.zero,
                ),
                elevation: 0,
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
