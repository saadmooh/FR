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

  @override
  void initState() {
    super.initState();
    _loadReminder();
  }

  void _loadReminder() {
    setState(() {
      _reminder = widget.reminderRepository.getById(widget.id);
      _isLoading = false;
    });
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

    final freeTimes = widget.freeTimeRepository.getAllAsJson();
    final result = await widget.aiService.reschedulePost(
      previousAttemptsJson: '[]',
      category: _reminder!.categoryEn ?? 'Other',
      complexity: _reminder!.complexityEn ?? 'Medium',
      importance: _reminder!.importance,
      userFreeTimesJson: freeTimes.isNotEmpty ? '{"free_times": $freeTimes}' : null,
    );

    if (result['newTime'] != null && mounted) {
      _reminder!.scheduledAt = result['newTime'];
      widget.reminderRepository.save(_reminder!);

      // Reschedule notification
      await widget.notificationService.cancelReminder(_reminder!.id);
      await widget.notificationService.scheduleReminder(_reminder!);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Rescheduled to ${DateFormat('MMM d, h:mm a').format(_reminder!.scheduledAt)}'),
            backgroundColor: AppColors.accent,
          ),
        );
        _loadReminder();
      }
    }

    setState(() => _isRescheduling = false);
  }

  Future<void> _delete() async {
    if (_reminder == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Delete Post?', style: TextStyle(color: AppColors.textPrimary)),
        content: const Text('This action cannot be undone.', style: TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: AppColors.error)),
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
        backgroundColor: AppColors.background,
        body: Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(AppColors.accent),
          ),
        ),
      );
    }

    if (_reminder == null) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
            onPressed: () => context.pop(),
          ),
        ),
        body: const Center(
          child: Text('Post not found', style: TextStyle(color: AppColors.textPrimary)),
        ),
      );
    }

    final dateFormat = DateFormat('EEEE, MMMM d, yyyy · h:mm a');
    final imageUrl = _reminder!.imageUrl;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          // App bar with image
          SliverAppBar(
            expandedHeight: imageUrl != null && imageUrl.isNotEmpty ? 220 : 100,
            pinned: true,
            backgroundColor: AppColors.background,
            leading: IconButton(
              icon: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.5),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.arrow_back, color: Colors.white),
              ),
              onPressed: () => context.pop(),
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: imageUrl != null && imageUrl.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: imageUrl,
                      fit: BoxFit.cover,
                      placeholder: (context, url) => Container(
                        color: AppColors.surfaceLight,
                        child: const Center(child: CircularProgressIndicator()),
                      ),
                      errorWidget: (context, url, error) => Container(
                        color: AppColors.surfaceLight,
                        child: const Icon(Icons.image_not_supported, color: AppColors.textSecondary, size: 64),
                      ),
                    )
                  : Container(
                      color: AppColors.surfaceLight,
                      child: const Icon(Icons.link, color: AppColors.textSecondary, size: 64),
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
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Description
                  if (_reminder!.description != null && _reminder!.description!.isNotEmpty)
                    Text(
                      _reminder!.description!,
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.5,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  const SizedBox(height: 24),

                  // Metadata section
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      children: [
                        _buildMetadataRow('📂 Category', '${_reminder!.categoryEn ?? "N/A"} / ${_reminder!.categoryAr ?? ""}'),
                        const Divider(color: AppColors.textSecondary, height: 24),
                        _buildMetadataRow('🎯 Complexity', '${_reminder!.complexityEn ?? "N/A"} / ${_reminder!.complexityAr ?? ""}'),
                        const Divider(color: AppColors.textSecondary, height: 24),
                        _buildMetadataRow('📅 Importance', _reminder!.importance),
                        const Divider(color: AppColors.textSecondary, height: 24),
                        _buildMetadataRow('⏰ Scheduled', dateFormat.format(_reminder!.scheduledAt)),
                        const Divider(color: AppColors.textSecondary, height: 24),
                        _buildMetadataRow(
                          '✅ Status',
                          _reminder!.isOpened ? 'Read' : 'Unread',
                          valueColor: _reminder!.isOpened ? AppColors.success : AppColors.warning,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // AI Explanation
                  if (_reminder!.aiExplanation != null && _reminder!.aiExplanation!.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.accentDim,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.auto_awesome, color: AppColors.accent, size: 20),
                              SizedBox(width: 8),
                              Text(
                                'AI Analysis',
                                style: TextStyle(
                                  color: AppColors.accent,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _reminder!.aiExplanation!,
                            style: const TextStyle(
                              fontStyle: FontStyle.italic,
                              color: AppColors.textSecondary,
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
                        foregroundColor: AppColors.background,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Open Post',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _isRescheduling
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text(
                              'Reschedule',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Delete button
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: _delete,
                      child: const Text(
                        'Delete',
                        style: TextStyle(color: AppColors.error, fontSize: 16),
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
        Text(label, style: const TextStyle(color: AppColors.textSecondary)),
        Text(
          value,
          style: TextStyle(
            color: valueColor ?? AppColors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
