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
import '../services/youtube_service.dart';
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
  YouTubeService? _youtubeService;

  String get _locale => LocaleManager.instance.getLocale();

  @override
  void initState() {
    super.initState();
    _youtubeService = YouTubeService();
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
    if (mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    }
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
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      ),
    );
  }

  Future<void> _openPost() async {
    if (_reminder == null) return;

    final isPlaylist = _reminder!.isPlaylist == true;
    final playlistId = _reminder!.playlistId;
    final currentIndex = _reminder!.playlistCurrentIndex ?? 0;
    final totalItems = _reminder!.playlistTotalItems ?? 0;

    String urlToOpen;

    if (isPlaylist && playlistId != null && _youtubeService != null) {
      urlToOpen = _reminder!.currentVideoUrl ?? _reminder!.url;

      final nextIndex = currentIndex + 1;
      if (nextIndex < totalItems) {
        try {
          final playlist = await _youtubeService!.getPlaylistInfo(
            'https://www.youtube.com/playlist?list=$playlistId',
          );

          if (playlist != null && nextIndex < playlist.items.length) {
            final nextVideo = playlist.items[nextIndex];

            _reminder!.playlistCurrentIndex = nextIndex;
            _reminder!.currentVideoUrl =
                'https://www.youtube.com/watch?v=${nextVideo.videoId}&list=$playlistId';
            _reminder!.title = nextVideo.title;
            _reminder!.description = nextVideo.description;
            _reminder!.imageUrl = nextVideo.thumbnailUrl;

            await widget.notificationService.cancelReminder(_reminder!.id);
            await widget.notificationService.scheduleReminder(_reminder!);
          }
        } catch (e) {
        }
      }
    } else {
      urlToOpen = _reminder!.url;
    }

    final uri = Uri.parse(urlToOpen);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }

    _reminder!.isOpened = true;
    _reminder!.openedAt = DateTime.now();
    widget.reminderRepository.save(_reminder!);

    widget.categoryStatRepository.recordOpened(_reminder!);
    await widget.notificationService.cancelReminder(_reminder!.id);

    _loadReminder();
  }

  Future<void> _reschedule() async {
    if (_reminder == null) return;

    setState(() => _isRescheduling = true);

    try {
      final freeTimes = widget.freeTimeRepository.getAllAsJson();
      final now = DateTime.now();
      final result = await widget.aiService.reschedulePost(
        previousAttemptsJson: '[]',
        category: _reminder!.categoryEn ?? 'Other',
        complexity: _reminder!.complexityEn ?? 'Medium',
        importance: _reminder!.importance,
        userFreeTimesJson: freeTimes.isNotEmpty
            ? '{"free_times": $freeTimes}'
            : null,
        currentTime: now,
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
        _showResult(false, '${Translations.aiRescheduleFailed(_locale)}: $e');
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        title: Text(
          Translations.deletePost(_locale),
          style: TextStyle(color: AppColors.whiteTextPrimary),
        ),
        content: Text(
          Translations.deleteWarning(_locale),
          style: TextStyle(color: AppColors.whiteTextSecondary),
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
              style: TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );

    if (confirm == true) {
      debugPrint('[PostDetailScreen] Deleting reminder ${_reminder!.id}');
      await widget.reminderRepository.deleteWithCleanup(_reminder!.id, widget.notificationService.cancelReminder);
      debugPrint('[PostDetailScreen] Delete completed');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(Translations.deletePost(_locale)),
            behavior: SnackBarBehavior.floating,
            backgroundColor: AppColors.whiteSurface,
          ),
        );
        context.pop();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: AppColors.whiteBackground,
        body: Center(
          child: CircularProgressIndicator(
            color: AppColors.accent,
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
              icon: const Icon(Icons.edit, color: AppColors.whiteAccent),
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
            style: TextStyle(color: AppColors.whiteTextPrimary),
          ),
        ),
      );
    }

    final imageUrl = _reminder!.imageUrl;

    return Scaffold(
      backgroundColor: AppColors.whiteBackground,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight:
                imageUrl != null && imageUrl.isNotEmpty ? 220 : 100,
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
                  ? Hero(
                      tag: 'reminder-${_reminder!.id}',
                      child: CachedNetworkImage(
                        imageUrl: imageUrl,
                        fit: BoxFit.cover,
                        width: double.infinity,
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

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _reminder!.title,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          color: AppColors.whiteTextPrimary,
                        ),
                  ),

                  if (_reminder!.isPlaylist == true) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.accent.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.zero,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.play_circle_filled,
                            size: 16,
                            color: AppColors.accent,
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              'Now: ${_reminder!.title}',
                              style: const TextStyle(
                                fontSize: 13,
                                color: AppColors.accent,
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 16),

                  if (_reminder!.description != null &&
                      _reminder!.description!.isNotEmpty)
                    Text(
                      _reminder!.description!,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppColors.whiteTextSecondary,
                            height: 1.5,
                          ),
                    ),
                  const SizedBox(height: 24),

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
                          color: AppColors.whiteShadow,
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
                        const Divider(
                            color: AppColors.whiteBorder, height: 24),
                        _buildMetadataRow(
                          Translations.complexityLabel(_locale),
                          LocaleManager.instance.getComplexity(
                            _reminder!.complexityEn,
                            _reminder!.complexityAr,
                            _reminder!.complexityFr,
                          ),
                        ),
                        const Divider(color: AppColors.whiteBorder, height: 24),
                        _buildMetadataRow(
                          Translations.importance(_locale),
                          LocaleManager.instance.getImportance(
                            _reminder!.importance,
                          ),
                        ),
                        const Divider(color: AppColors.whiteBorder, height: 24),
                        _buildMetadataRow(
                          Translations.scheduledLabel(_locale),
                          _formatDateTime(_reminder!.scheduledAt),
                        ),
                        const Divider(color: AppColors.whiteBorder, height: 24),
                        if (_reminder!.isPlaylist == true) ...[
                          _buildMetadataRow(
                            'Playlist',
                            _reminder!.playlistTitle ?? 'Unknown',
                            valueColor: AppColors.whiteAccent,
                          ),
                          const Divider(
                              color: AppColors.whiteBorder, height: 24),
                          _buildMetadataRow(
                            'Watching',
                            'Video ${(_reminder!.playlistCurrentIndex ?? 0) + 1} of ${_reminder!.playlistTotalItems ?? 0}',
                            valueColor: AppColors.whiteAccent,
                          ),
                          const Divider(
                              color: AppColors.whiteBorder, height: 24),
                        ],
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
                            color: AppColors.whiteShadow,
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
                                color: AppColors.whiteAccent,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                Translations.aiAnalysis(_locale),
                                style: Theme.of(context)
                                    .textTheme.titleMedium
                                    ?.copyWith(color: AppColors.whiteAccent),
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
                            style: TextStyle(
                              fontStyle: FontStyle.italic,
                              color: AppColors.whiteTextSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 32),

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _openPost,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.whiteAccent,
                        foregroundColor: AppColors.whiteBackground,
                        padding:
                            const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.zero,
                        ),
                        elevation: 0,
                        shadowColor: Colors.transparent,
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

                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: _isRescheduling ? null : _reschedule,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.whiteAccent,
                        side: const BorderSide(color: AppColors.whiteAccent),
                        padding:
                            const EdgeInsets.symmetric(vertical: 16),
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

                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: _delete,
                      child: Text(
                        Translations.delete(_locale),
                        style: TextStyle(
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
          style: TextStyle(color: AppColors.whiteTextSecondary),
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
