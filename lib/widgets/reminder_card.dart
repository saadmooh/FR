import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import '../models/reminder.dart';
import '../core/app_theme.dart';
import '../core/locale_manager.dart';

class ReminderCard extends StatelessWidget {
  final Reminder reminder;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const ReminderCard({
    super.key,
    required this.reminder,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('EEE, MMM d · h:mm a');
    final imageUrl = reminder.imageUrl;
    final isRead = reminder.isOpened;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.zero,
        child: Row(
          children: [
            // Left teal accent border
            Container(
              width: 4,
              height: 120,
              decoration: BoxDecoration(
                color: isRead ? AppColors.read : AppColors.accent,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  bottomLeft: Radius.circular(16),
                ),
              ),
            ),

            // Thumbnail
            SizedBox(
              width: 90,
              height: 90,
              child: imageUrl != null && imageUrl.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: imageUrl,
                      fit: BoxFit.cover,
                      placeholder: (context, url) => Container(
                        color: AppColors.surfaceLight,
                        child: const Center(
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                      errorWidget: (context, url, error) => Container(
                        color: AppColors.surfaceLight,
                        child: const Icon(
                          Icons.image_not_supported,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    )
                  : Container(
                      color: AppColors.surfaceLight,
                      child: const Icon(
                        Icons.link,
                        color: AppColors.textSecondary,
                      ),
                    ),
            ),

            // Content
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title
                    Text(
                      reminder.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),

                    // Description
                    if (reminder.description != null &&
                        reminder.description!.isNotEmpty)
                      Text(
                        reminder.description!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),

                    const SizedBox(height: 8),

                    // Chips and time
                    Row(
                      children: [
                        // Category chip
                        if (reminder.categoryEn != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.accentDim,
                              borderRadius: BorderRadius.zero,
                            ),
                            child: Text(
                              LocaleManager.instance.getCategory(
                                reminder.categoryEn,
                                reminder.categoryAr,
                                reminder.categoryFr,
                              ),
                              style: const TextStyle(
                                color: AppColors.accent,
                                fontSize: 10,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),

                        const SizedBox(width: 4),

                        // Complexity chip
                        if (reminder.complexityEn != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceLight,
                              borderRadius: BorderRadius.zero,
                            ),
                            child: Text(
                              LocaleManager.instance.getComplexity(
                                reminder.complexityEn,
                                reminder.complexityAr,
                                reminder.complexityFr,
                              ),
                              style: const TextStyle(
                                fontSize: 10,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ),

                        const Spacer(),

                        // Time
                        Text(
                          dateFormat.format(reminder.scheduledAt),
                          style: const TextStyle(
                            fontSize: 10,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
