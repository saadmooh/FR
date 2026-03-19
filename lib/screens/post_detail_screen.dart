import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../repositories/reminder_repository.dart';
import '../repositories/free_time_repository.dart';
import '../repositories/category_statistic_repository.dart';
import '../services/notification_service.dart';
import '../services/ai_service.dart';
import '../models/reminder.dart';
import '../core/app_theme.dart';
import '../core/locale_manager.dart';
import '../core/translations.dart';

class PostDetailScreen extends StatefulWidget {
  final int id;
  final ReminderRepository reminderRepository;
  final FreeTimeRepository freeTimeRepository;
  final CategoryStatisticRepository categoryStatRepository;
  final NotificationService notificationService;
  final AIService aiService;

  const PostDetailScreen({
    super.key,
    required this.id,
    required this.reminderRepository,
    required this.freeTimeRepository,
    required this.categoryStatRepository,
    required this.notificationService,
    required this.aiService,
  });

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  Reminder? _reminder;
  bool _isLoading = true;
  bool _isRescheduling = false;
  final ValueNotifier<bool> _refreshNotifier = ValueNotifier<bool>(false);

  String get _locale => LocaleManager.instance.getLocale();

  @override
  void initState() {
    super.initState();
    _loadReminder();
    _refreshNotifier.addListener(_onRefresh);
    LocaleManager.instance.localeNotifier.addListener(_onLocaleChanged);
  }

  @override
  void dispose() {
    _refreshNotifier.removeListener(_onRefresh);
    _refreshNotifier.dispose();
    LocaleManager.instance.localeNotifier.removeListener(_onLocaleChanged);
    super.dispose();
  }

  void _onLocaleChanged() {
    if (mounted) setState(() {});
  }

  void _onRefresh() {
    _loadReminder();
  }

  @override
  void didUpdateWidget(PostDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.id != widget.id) {
      _loadReminder();
    }
  }

  void _loadReminder() {
    setState(() {
      _reminder = widget.reminderRepository.getById(widget.id);
      _isLoading = false;
    });
  }

  void _showResult(bool success, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: success ? AppColors.accent : AppColors.error,
      ),
    );
  }

  Future<void> _openPost() async {
    if (_reminder == null) return;

    final uri = Uri.parse(_reminder!.url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }

    // Mark as read
    _reminder!.isOpened = true;
    _reminder!.openedAt = DateTime.now();
    widget.reminderRepository.save(_reminder!);

    // Update statistics
    widget.categoryStatRepository.recordOpened(_reminder!);
    // Cancel notification
    await widget.notificationService.cancelReminder(_reminder!.id);

    _loadReminder();
  }

  Future<void> _reschedule() async {
    if (_reminder == null) return;

    setState(() => _isRescheduling = true);

    try {
      final freeTimes = widget.freeTimeRepository.getAllAsJson();
      final result = await widget.aiService.reschedulePost(
        previousAttemptsJson: '[]',
        category: _reminder!.categoryEn ?? 'Other',
        complexity: _reminder!.complexityEn ?? 'Medium',
        importance: _reminder!.importance,
        userFreeTimesJson: freeTimes.isNotEmpty
            ? '{"free_times": $freeTimes}'
            : null,
      );
      if (result['newTime'] != null && mounted) {
        _reminder!.scheduledAt = result['newTime'];
        widget.reminderRepository.save(_reminder!);

        await widget.notificationService.cancelReminder(_reminder!.id);
        await widget.notificationService.scheduleReminder(_reminder!);

        if (mounted) {
          _showResult(true, Translations.scheduledFor(_locale));
          _loadReminder();
        }
      }
    } catch (e) {
      if (mounted) {
        _showResult(false, 'Error: $e');
      }
    }

    setState(() => _isRescheduling = false);
  }

  Future<void> _delete() async {
    if (_reminder == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.whiteSurface,
        title: Text(
          Translations.deletePost(_locale),
          style: const TextStyle(color: AppColors.whiteTextPrimary),
        ),
        content: Text(
          Translations.deleteWarning(_locale),
          style: const TextStyle(color: AppColors.whiteTextSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(Translations.cancel(_locale)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              Translations.delete(_locale),
              style: const TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await widget.notificationService.cancelReminder(_reminder!.id);
      widget.reminderRepository.delete(_reminder!.id);
      if (mounted) {
        context.pop();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: AppColors.whiteBackground,
        body: Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(AppColors.accent),
          ),
        ),
      );
    }

    if (_reminder == null) {
      return Scaffold(
        backgroundColor: AppColors.whiteBackground,
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(
              Icons.arrow_back,
              color: AppColors.whiteTextPrimary,
            ),
            onPressed: () => context.pop(),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.edit, color: AppColors.accent),
              onPressed: () async {
                await context.push('/post/${widget.id}/edit');
                Future.microtask(() {
                  _loadReminder();
                  _refreshNotifier.value = !_refreshNotifier.value;
                });
              },
            ),
          ],
        ),
        body: Center(
          child: Text(
            Translations.postNotFound(_locale),
            style: const TextStyle(color: AppColors.whiteTextPrimary),
          ),
        ),
      );
    }

    final imageUrl = _reminder!.imageUrl;

    return Scaffold(
      backgroundColor: AppColors.whiteBackground,
      body: CustomScrollView(
        slivers: [
          // App bar with image
          SliverAppBar(
            expandedHeight: imageUrl != null && imageUrl.isNotEmpty ? 220 : 100,
            pinned: true,
            backgroundColor: AppColors.whiteBackground,
            leading: IconButton(
              icon: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.5),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.arrow_back, color: Colors.white),
              ),
              onPressed: () => context.pop(),
            ),
            actions: [
              IconButton(
                icon: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.edit, color: Colors.white),
                ),
                onPressed: () async {
                  await context.push('/post/${widget.id}/edit');
                  Future.microtask(() {
                    _loadReminder();
                    _refreshNotifier.value = !_refreshNotifier.value;
                  });
                },
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: imageUrl != null && imageUrl.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: imageUrl,
                      fit: BoxFit.cover,
                      placeholder: (context, url) => Container(
                        color: AppColors.whiteSurface,
                        child: const Center(child: CircularProgressIndicator()),
                      ),
                      errorWidget: (context, url, error) => Container(
                        color: AppColors.whiteSurface,
                        child: const Icon(
                          Icons.image_not_supported,
                          color: AppColors.whiteTextSecondary,
                          size: 64,
                        ),
                      ),
                    )
                  : Container(
                      color: AppColors.whiteSurface,
                      child: const Icon(
                        Icons.link,
                        color: AppColors.whiteTextSecondary,
                        size: 64,
                      ),
                    ),
            ),
          ),

          // Content
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title
                  Text(
                    _reminder!.title,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: AppColors.whiteTextPrimary,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Description
                  if (_reminder!.description != null &&
                      _reminder!.description!.isNotEmpty)
                    Text(
                      _reminder!.description!,
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.5,
                        color: AppColors.whiteTextSecondary,
                      ),
                    ),
                  const SizedBox(height: 24),

                  // Metadata section
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppColors.whiteSurface,
                      borderRadius: BorderRadius.zero,
                      border: Border.all(
                        color: AppColors.whiteBorder,
                        width: 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        _buildMetadataRow(
                          Translations.categoryLabel(_locale),
                          LocaleManager.instance.getCategory(
                            _reminder!.categoryEn,
                            _reminder!.categoryAr,
                            _reminder!.categoryFr,
                          ),
                        ),
                        const Divider(color: AppColors.whiteBorder, height: 24),
                        _buildMetadataRow(
                          Translations.complexityLabel(_locale),
                          LocaleManager.instance.getComplexity(
                            _reminder!.complexityEn,
                            _reminder!.complexityAr,
                            _reminder!.complexityFr,
                          ),
                        ),
                        const Divider(
                          color: AppColors.whiteTextSecondary,
                          height: 24,
                        ),
                        _buildMetadataRow(
                          Translations.importance(_locale),
                          LocaleManager.instance.getImportance(
                            _reminder!.importance,
                          ),
                        ),
                        const Divider(
                          color: AppColors.whiteTextSecondary,
                          height: 24,
                        ),
                        _buildMetadataRow(
                          Translations.scheduledLabel(_locale),
                          _formatDateTime(_reminder!.scheduledAt),
                        ),
                        const Divider(
                          color: AppColors.whiteTextSecondary,
                          height: 24,
                        ),
                        _buildMetadataRow(
                          Translations.statusLabel(_locale),
                          _reminder!.isOpened
                              ? Translations.read(_locale)
                              : Translations.unread(_locale),
                          valueColor: _reminder!.isOpened
                              ? AppColors.success
                              : AppColors.warning,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // AI Explanation
                  if (_reminder!.aiExplanation != null &&
                      _reminder!.aiExplanation!.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: AppColors.whiteSurface,
                        borderRadius: BorderRadius.zero,
                        border: Border.all(
                          color: AppColors.whiteBorder,
                          width: 1,
                        ),
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
                          Row(
                            children: [
                              const Icon(
                                Icons.auto_awesome,
                                color: AppColors.accent,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                Translations.aiAnalysis(_locale),
                                style: const TextStyle(
                                  color: AppColors.accent,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            LocaleManager.instance.getExplanation(
                              _reminder!.aiExplanation,
                              _reminder!.aiExplanationAr,
                              _reminder!.aiExplanationFr,
                            ),
                            style: const TextStyle(
                              fontStyle: FontStyle.italic,
                              color: AppColors.whiteTextSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 32),

                  // Open Post button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _openPost,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        foregroundColor: AppColors.whiteBackground,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.zero,
                        ),
                      ),
                      child: Text(
                        Translations.openPost(_locale),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Reschedule button
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: _isRescheduling ? null : _reschedule,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.accent,
                        side: const BorderSide(color: AppColors.accent),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.zero,
                        ),
                      ),
                      child: _isRescheduling
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(
                              Translations.reschedule(_locale),
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Delete button
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: _delete,
                      child: Text(
                        Translations.delete(_locale),
                        style: const TextStyle(
                          color: AppColors.error,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetadataRow(String label, String value, {Color? valueColor}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(color: AppColors.whiteTextSecondary),
        ),
        Text(
          value,
          style: TextStyle(
            color: valueColor ?? AppColors.whiteTextPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  String _formatDateTime(DateTime dt) {
    final formatStr = Translations.dateTimeFormat(_locale);
    return DateFormat(formatStr).format(dt);
  }
}
