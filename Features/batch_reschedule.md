# Feature: Batch Reschedule

## Overview

Reschedule all reminders in a category at once. Useful when planning a category-focused reading week.

## Implementation

### 1. Add Batch Reschedule to Repository

```dart
// In reminder_repository.dart

int rescheduleByCategory(String category, DateTime newTime) {
  final reminders = getByCategory(category);
  int count = 0;
  
  for (final reminder in reminders) {
    // Keep the time of day, change the date
    reminder.scheduledAt = DateTime(
      newTime.year,
      newTime.month,
      newTime.day,
      reminder.scheduledAt.hour,
      reminder.scheduledAt.minute,
    );
    save(reminder);
    count++;
  }
  
  return count;
}

int rescheduleByComplexity(String complexity, DateTime newTime) {
  final query = _box.query(Reminder_.complexityEn.equals(complexity)).build();
  final reminders = query.find();
  query.close();
  
  int count = 0;
  for (final reminder in reminders) {
    reminder.scheduledAt = DateTime(
      newTime.year,
      newTime.month,
      newTime.day,
      reminder.scheduledAt.hour,
      reminder.scheduledAt.minute,
    );
    save(reminder);
    count++;
  }
  
  return count;
}
```

### 2. Create BatchRescheduleDialog

```dart
class BatchRescheduleDialog extends StatefulWidget {
  final String category;

  const BatchRescheduleDialog({super.key, required this.category});

  @override
  State<BatchRescheduleDialog> createState() => _BatchRescheduleDialogState();
}

class _BatchRescheduleDialogState extends State<BatchRescheduleDialog> {
  DateTime? _selectedDate;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final count = reminderRepository.getByCategory(widget.category).length;

    return AlertDialog(
      title: Text(t.batchReschedule),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(t.rescheduleCategory(widget.category, count)),
          const SizedBox(height: 16),
          ListTile(
            title: Text(_selectedDate != null
                ? _formatDate(_selectedDate!)
                : t.selectDate),
            trailing: const Icon(Icons.calendar_today),
            onTap: _selectDate,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(t.cancel),
        ),
        ElevatedButton(
          onPressed: _selectedDate != null ? _reschedule : null,
          child: Text(t.reschedule),
        ),
      ],
    );
  }

  Future<void> _selectDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    
    if (date != null) {
      setState(() => _selectedDate = date);
    }
  }

  void _reschedule() async {
    final count = reminderRepository.rescheduleByCategory(
      widget.category,
      _selectedDate!,
    );
    
    // Reschedule notifications
    final reminders = reminderRepository.getByCategory(widget.category);
    for (final reminder in reminders) {
      await notificationService.cancelReminder(reminder.id);
      await notificationService.scheduleReminder(reminder);
    }
    
    if (mounted) {
      Navigator.pop(context, count);
    }
  }
}
```

### 3. Add to Statistics Screen

```dart
// In category breakdown section
ListTile(
  trailing: PopupMenuButton(
    itemBuilder: (context) => [
      PopupMenuItem(
        value: 'reschedule',
        child: Row(
          children: [
            const Icon(Icons.schedule),
            const SizedBox(width: 8),
            Text(Translations.of(context).rescheduleAll),
          ],
        ),
      ),
    ],
    onSelected: (value) {
      if (value == 'reschedule') {
        showDialog(
          context: context,
          builder: (context) => BatchRescheduleDialog(
            category: category,
          ),
        ).then((count) {
          if (count != null && count > 0) {
            setState(() {});
          }
        });
      }
    },
  ),
)
```

## Testing Checklist

- [ ] Category selection works
- [ ] Date picker works
- [ ] All reminders in category rescheduled
- [ ] Notifications updated
- [ ] Count reported correctly
