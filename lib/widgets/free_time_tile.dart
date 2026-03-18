import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import '../models/free_time_slot.dart';
import '../core/app_theme.dart';

class FreeTimeTile extends StatelessWidget {
  final FreeTimeSlot slot;
  final VoidCallback onDelete;

  const FreeTimeTile({
    super.key,
    required this.slot,
    required this.onDelete,
  });

  String _getDayName(int dayOfWeek) {
    const days = ['', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    return days[dayOfWeek];
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
            label: 'Delete',
            borderRadius: BorderRadius.circular(12),
          ),
        ],
      ),
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.accentDim,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(
            Icons.access_time,
            color: AppColors.accent,
          ),
        ),
        title: Text(
          '${slot.startTime} → ${slot.endTime}',
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(
          _getDayName(slot.dayOfWeek),
          style: const TextStyle(color: AppColors.textSecondary),
        ),
      ),
    );
  }
}
