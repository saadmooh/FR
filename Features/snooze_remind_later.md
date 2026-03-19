# Feature: Snooze / Remind Later

## Overview

Allows users to temporarily postpone a reminder without losing their scheduled slot. Instead of permanently rescheduling, users can quickly defer notifications to a more convenient time.

## User Experience

### Use Cases
- User receives notification but is busy → snooze for 1 hour
- User sees reminder but wants to read later → snooze until tomorrow morning
- User wants a quick defer without editing details

### UI Flow
1. User swipes left on reminder card OR long-press → context menu
2. Tap "Snooze" option
3. Bottom sheet appears with options:
   - **1 hour** - defer by 60 minutes
   - **3 hours** - defer by 3 hours
   - **Tomorrow, 9 AM** - next day morning
   - **Tomorrow, 7 PM** - next day evening
   - **Custom** - date/time picker
4. Confirm → notification rescheduled, card updates

## Implementation Guide

### 1. Add SnoozeOptions Enum

Create `lib/models/snooze_option.dart`:

```dart
enum SnoozeOption {
  oneHour,
  threeHours,
  tomorrowMorning,
  tomorrowEvening,
  custom,
}

extension SnoozeOptionExtension on SnoozeOption {
  String getLabel(AppTranslations t) {
    switch (this) {
      case SnoozeOption.oneHour:
        return t.snoozeOneHour;
      case SnoozeOption.threeHours:
        return t.snoozeThreeHours;
      case SnoozeOption.tomorrowMorning:
        return t.snoozeTomorrowMorning;
      case SnoozeOption.tomorrowEvening:
        return t.snoozeTomorrowEvening;
      case SnoozeOption.custom:
        return t.snoozeCustom;
    }
  }

  Duration get duration {
    switch (this) {
      case SnoozeOption.oneHour:
        return const Duration(hours: 1);
      case SnoozeOption.threeHours:
        return const Duration(hours: 3);
      case SnoozeOption.tomorrowMorning:
      case SnoozeOption.tomorrowEvening:
      case SnoozeOption.custom:
        return Duration.zero; // Special handling
    }
  }

  DateTime calculateNewTime(SnoozeOption option) {
    final now = DateTime.now();
    switch (option) {
      case SnoozeOption.oneHour:
        return now.add(const Duration(hours: 1));
      case SnoozeOption.threeHours:
        return now.add(const Duration(hours: 3));
      case SnoozeOption.tomorrowMorning:
        return DateTime(now.year, now.month, now.day + 1, 9, 0);
      case SnoozeOption.tomorrowEvening:
        return DateTime(now.year, now.month, now.day + 1, 19, 0);
      case SnoozeOption.custom:
        return now; // Caller must set actual time
    }
  }
}
```

### 2. Add Translations

In `lib/core/translations.dart`, add:

```dart
// In each language section
String get snoozeOneHour => 'In 1 hour';
String get snoozeThreeHours => 'In 3 hours';
String get snoozeTomorrowMorning => 'Tomorrow, 9 AM';
String get snoozeTomorrowEvening => 'Tomorrow, 7 PM';
String get snoozeCustom => 'Custom time';
String get snoozeConfirm => 'Snooze';
String get snoozeCancelled => 'Snooze cancelled';
```

### 3. Create SnoozeSheet Widget

Create `lib/widgets/snooze_sheet.dart`:

```dart
class SnoozeSheet extends StatefulWidget {
  final Reminder reminder;
  final Function(DateTime) onSnooze;

  const SnoozeSheet({
    super.key,
    required this.reminder,
    required this.onSnooze,
  });

  @override
  State<SnoozeSheet> createState() => _SnoozeSheetState();
}

class _SnoozeSheetState extends State<SnoozeSheet> {
  DateTime? customTime;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(t.snoozeTitle, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          ...SnoozeOption.values.map((option) => _buildOptionTile(option, t)),
          if (customTime != null)
            _buildCustomTimeDisplay(t),
        ],
      ),
    );
  }

  Widget _buildOptionTile(SnoozeOption option, AppTranslations t) {
    return ListTile(
      title: Text(option.getLabel(t)),
      onTap: () => _handleOptionSelected(option),
    );
  }

  Future<void> _handleOptionSelected(SnoozeOption option) async {
    if (option == SnoozeOption.custom) {
      final date = await showDatePicker(...);
      final time = await showTimePicker(...);
      if (date != null && time != null) {
        customTime = DateTime(date.year, date.month, date.day, time.hour, time.minute);
        setState(() {});
      }
      return;
    }
    
    final newTime = option.calculateNewTime(option);
    widget.onSnooze(newTime);
    if (mounted) Navigator.pop(context);
  }
}
```

### 4. Add Snooze Repository Method

In `lib/repositories/reminder_repository.dart`:

```dart
void snooze(int id, DateTime newTime) {
  final reminder = _box.get(id);
  if (reminder != null) {
    reminder.scheduledAt = newTime;
    _box.put(reminder);
  }
}
```

### 5. Integrate with NotificationService

In `lib/services/notification_service.dart`:

```dart
Future<void> snoozeReminder(int reminderId, DateTime newTime) async {
  final reminder = reminderRepository.getById(reminderId);
  if (reminder != null) {
    // Cancel old notification
    await cancelReminder(reminderId);
    
    // Update reminder time
    reminderRepository.snooze(reminderId, newTime);
    
    // Schedule new notification
    await scheduleReminder(reminder);
  }
}
```

### 6. Add Context Menu Option

In `lib/widgets/modern_reminder_card.dart`, add to long-press menu:

```dart
PopupMenuItem(
  value: 'snooze',
  child: Row(
    children: [
      Icon(Icons.snooze, color: AppColors.accent),
      const SizedBox(width: 8),
      Text(t.snooze),
    ],
  ),
)
```

### 7. Handle in RemindersScreen

```dart
void _handleSnooze(Reminder reminder) {
  showModalBottomSheet(
    context: context,
    builder: (context) => SnoozeSheet(
      reminder: reminder,
      onSnooze: (newTime) async {
        await notificationService.snoozeReminder(reminder.id, newTime);
        setState(() {});
      },
    ),
  );
}
```

## Database Changes

No database schema changes required. The `scheduledAt` field stores the new time.

## Testing Checklist

- [ ] Snooze options display correctly
- [ ] One hour/two hour snooze calculates correct time
- [ ] Tomorrow morning/evening sets correct date and time
- [ ] Custom picker allows full date/time selection
- [ ] Notification is cancelled and rescheduled
- [ ] Card UI updates immediately after snooze
- [ ] Snooze persists after app restart
- [ ] Edge case: snooze time already passed today → next day

## Edge Cases

1. **Snooze past midnight**: Automatically schedule for next occurrence
2. **Notification permission denied**: Show in-app alert instead
3. **Multiple snoozes**: Keep updating to latest snooze time
4. **Snooze during snooze**: Replace previous snooze time

## Related Features

- [Remind Later](./remind_later.md) - Similar but with different UX
- [Undo Delete](./undo_delete.md) - Toast-based undo for all destructive actions
