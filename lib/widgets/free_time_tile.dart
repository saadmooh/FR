import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import '../models/free_time_slot.dart';
import '../core/app_theme.dart';
import '../core/translations.dart';
import '../core/locale_manager.dart';

class FreeTimeTile extends StatelessWidget {
  final FreeTimeSlot slot;
  final VoidCallback onDelete;

  const FreeTimeTile({super.key, required this.slot, required this.onDelete});

  String get _locale => LocaleManager.instance.getLocale();

  String _getDayName(int dayOfWeek) {
    return Translations.getDayName(dayOfWeek, _locale);
  }

  @override
  Widget build(BuildContext context) {
    return Slidable(
      key: Key('free_time_${slot.id}'),
      endActionPane: ActionPane(
        motion: const ScrollMotion(),
        children: [
          SlidableAction(
            onPressed: (_) => onDelete(),
            backgroundColor: AppColors.error,
            foregroundColor: Colors.white,
            icon: Icons.delete,
            label: Translations.delete(_locale),
            borderRadius: BorderRadius.zero,
          ),
        ],
      ),
      child: Container(
        margin: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
        decoration: BoxDecoration(
          color: AppColors.whiteBackground,
          borderRadius: BorderRadius.zero,
          border: Border.all(
            color: AppColors.whiteTextSecondary.withValues(alpha: 0.1),
            width: 1,
          ),
        ),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 4,
          ),
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.zero,
            ),
            child: const Icon(
              Icons.access_time,
              color: AppColors.accent,
              size: 20,
            ),
          ),
          title: Text(
            '${slot.startTime} → ${slot.endTime}',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: AppColors.whiteTextPrimary,
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
          ),
          subtitle: Text(
            _getDayName(slot.dayOfWeek),
            style: TextStyle(
              color: AppColors.whiteTextSecondary.withValues(alpha: 0.8),
              fontSize: 12,
            ),
          ),
          trailing: IconButton(
            icon: Icon(
              Icons.delete_outline,
              color: AppColors.whiteTextSecondary.withValues(alpha: 0.5),
              size: 20,
            ),
            onPressed: onDelete,
          ),
        ),
      ),
    );
  }
}
