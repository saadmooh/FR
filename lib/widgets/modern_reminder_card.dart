import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../core/locale_manager.dart';
import '../core/translations.dart';
import '../core/app_theme.dart';

class ModernReminderCard extends StatefulWidget {
  const ModernReminderCard({
    super.key,
    required this.reminder,
    this.onTap,
    this.onLongPress,
    this.isSelected = false,
    this.onSelectionToggle,
    this.inSelectionMode = false,
  });

  final dynamic reminder;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool isSelected;
  final VoidCallback? onSelectionToggle;
  final bool inSelectionMode;

  @override
  State<ModernReminderCard> createState() => _ModernReminderCardState();
}

class _ModernReminderCardState extends State<ModernReminderCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  String get _locale => LocaleManager.instance.getLocale();

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 0.98,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
    LocaleManager.instance.localeNotifier.addListener(_onLocaleChanged);
  }

  void _onLocaleChanged() {
    if (mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    LocaleManager.instance.localeNotifier.removeListener(_onLocaleChanged);
    _controller.dispose();
    super.dispose();
  }

  Color _getImportanceBackgroundColor() {
    final importance = widget.reminder.importance;
    switch (importance) {
      case 'Day':
        return const Color(0xFFFFEDD5);
      case 'Week':
        return const Color(0xFFDBEAFE);
      case 'Month':
        return const Color(0xFFDCFCE7);
      default:
        return const Color(0xFFDCFCE7);
    }
  }

  Color _getImportanceTextColor() {
    final importance = widget.reminder.importance;
    switch (importance) {
      case 'Day':
        return const Color(0xFFEA580C);
      case 'Week':
        return const Color(0xFF2563EB);
      case 'Month':
        return const Color(0xFF16A34A);
      default:
        return const Color(0xFF16A34A);
    }
  }

  String _formatScheduledTime() {
    final now = DateTime.now();
    final difference = widget.reminder.scheduledAt.difference(now);
    final locale = _locale;

    if (difference.isNegative) {
      return Translations.cardOverdue(locale);
    } else if (difference.inDays == 0) {
      return Translations.cardToday(locale);
    } else if (difference.inDays == 1) {
      return Translations.cardTomorrow(locale);
    } else if (difference.inDays < 7) {
      return Translations.cardInDays(locale, difference.inDays);
    } else if (difference.inDays < 30) {
      final weeks = (difference.inDays / 7).floor();
      return Translations.cardInWeeks(locale, weeks);
    } else {
      final months = (difference.inDays / 30).floor();
      return Translations.cardInMonths(locale, months);
    }
  }

@override
  Widget build(BuildContext context) {
    final isRead = widget.reminder.isOpened;
    final isSelected = widget.isSelected;
    final inSelectionMode = widget.inSelectionMode;

    return Hero(
      tag: 'reminder-${widget.reminder.id}',
      flightShuttleBuilder: (
        context,
        animation,
        direction,
        fromContext,
        toContext,
      ) {
        return widget.reminder.isOpened
            ? Container(
                color: AppColors.whiteBackground,
                child: const Center(child: CircularProgressIndicator()),
              )
            : const SizedBox.shrink();
      },
      child: Stack(
        children: [
          GestureDetector(
            onTapDown: inSelectionMode ? null : (_) => _controller.forward(),
            onTapUp: inSelectionMode ? null : (_) {
              _controller.reverse();
              widget.onTap?.call();
            },
            onTapCancel: inSelectionMode ? null : () => _controller.reverse(),
            onLongPress: inSelectionMode ? null : widget.onLongPress,
            onTap: inSelectionMode ? widget.onSelectionToggle : null,
            child: AnimatedBuilder(
              animation: _scaleAnimation,
              builder: (context, child) {
                return Transform.scale(
                  scale: _scaleAnimation.value,
                  child: child,
                );
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected ? AppColors.accent.withValues(alpha: 0.1) : AppColors.whiteCard,
                  borderRadius: BorderRadius.zero,
                  border: isSelected
                      ? Border.all(color: AppColors.accent, width: 2)
                      : null,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.whiteShadow,
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Stack(
                      children: [
                        SizedBox(
                          width: double.infinity,
                          height: 180,
                          child: CachedNetworkImage(
                            imageUrl: (widget.reminder.isPlaylist == true &&
                                        widget.reminder.playlistThumbnail != null)
                                    ? widget.reminder.playlistThumbnail!
                                    : (widget.reminder.imageUrl ?? ''),
                            fit: BoxFit.cover,
                            placeholder: (context, url) => Container(
                              color: AppColors.whiteSurface,
                              child: const Center(
                                child: SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                ),
                              ),
                            ),
                            errorWidget: (context, url, error) => Container(
                              color: AppColors.whiteSurface,
                              child: const Icon(
                                Icons.image_not_supported,
                                size: 48,
                                color: AppColors.whiteTextSecondary,
                              ),
                            ),
                          ),
                        ),
                        Container(
                          width: double.infinity,
                          height: 180,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.transparent,
                                Colors.black.withValues(alpha: 0.3),
                              ],
                              stops: const [0.5, 1.0],
                            ),
                          ),
                        ),
                        Positioned(
                          top: 12,
                          right: 12,
                          child: Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              color: isRead
                                  ? AppColors.whiteTextSecondary.withValues(alpha: 0.2)
                                  : AppColors.accent,
                              shape: BoxShape.circle,
                            ),
                            child: isRead
                                ? const Icon(
                                    Icons.check,
                                    size: 14,
                                    color: Colors.white,
                                  )
                                : const SizedBox.shrink(),
                          ),
                        ),
                        if (widget.reminder.isPlaylist == true &&
                            widget.reminder.playlistTotalItems != null &&
                            widget.reminder.playlistTotalItems > 0)
                          Positioned(
                            bottom: 0,
                            left: 0,
                            right: 0,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Colors.transparent,
                                    Colors.black.withValues(alpha: 0.7),
                                  ],
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(
                                        Icons.playlist_play,
                                        color: Colors.white,
                                        size: 16,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        '${(widget.reminder.playlistCurrentIndex ?? 0) + 1} / ${widget.reminder.playlistTotalItems}',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  ClipRRect(
                                    borderRadius: BorderRadius.zero,
                                    child: LinearProgressIndicator(
                                      value: ((widget.reminder.playlistCurrentIndex ??
                                                  0) +
                                              1) /
                                          widget.reminder.playlistTotalItems!,
                                      backgroundColor:
                                          Colors.white.withValues(alpha: 0.3),
                                      valueColor: const AlwaysStoppedAnimation<Color>(
                                        Colors.white,
                                      ),
                                      minHeight: 4,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            (widget.reminder.isPlaylist == true &&
                                    widget.reminder.playlistTitle != null)
                                ? widget.reminder.playlistTitle!
                                : widget.reminder.title,
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  color: AppColors.whiteTextPrimary,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            widget.reminder.description ?? '',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: AppColors.whiteTextSecondary,
                                  fontSize: 13,
                                ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              _buildChip(
                                label: LocaleManager.instance.getCategory(
                                  widget.reminder.categoryEn,
                                  widget.reminder.categoryAr,
                                  widget.reminder.categoryFr,
                                ),
                              backgroundColor: const Color(0xFFE8F5E9),
                              textColor: const Color(0xFF2E7D32),
                              ),
                              const SizedBox(width: 8),
                              _buildChip(
                                label: LocaleManager.instance.getComplexity(
                                  widget.reminder.complexityEn,
                                  widget.reminder.complexityAr,
                                  widget.reminder.complexityFr,
                                ),
                                backgroundColor: const Color(0xFFF3E8FF),
                                textColor: const Color(0xFF9333EA),
                              ),
                              const SizedBox(width: 8),
                              _buildChip(
                                label: LocaleManager.instance.getImportance(
                                  widget.reminder.importance,
                                ),
                                backgroundColor: _getImportanceBackgroundColor(),
                                textColor: _getImportanceTextColor(),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.access_time,
                                    size: 16,
                                    color: AppColors.whiteTextSecondary,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    _formatScheduledTime(),
                                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                          color: AppColors.whiteTextSecondary,
                                        ),
                                  ),
                                ],
                              ),
                              if (isRead)
                                Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: AppColors.whiteTextSecondary
                                        .withAlpha(51),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.check,
                                    size: 14,
                                    color: AppColors.whiteTextSecondary,
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (inSelectionMode)
            Positioned(
              top: 20,
              left: 20,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: isSelected ? AppColors.accent : Colors.transparent,
                  border: Border.all(
                    color: isSelected ? AppColors.accent : AppColors.whiteTextSecondary,
                    width: 2,
                  ),
                  shape: BoxShape.circle,
                ),
                child: isSelected
                    ? const Icon(
                        Icons.check,
                        size: 18,
                        color: Colors.white,
                      )
                    : null,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildChip({
    required String label,
    required Color backgroundColor,
    required Color textColor,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.zero,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: textColor,
          ),
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}
