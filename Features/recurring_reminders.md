# Feature: Recurring Reminders

## Overview

Allows users to set reminders that automatically repeat on a schedule (daily, weekly, monthly). Useful for periodic content like newsletters, weekly digests, or regular check-ins.

## User Experience

### Recurrence Options
| Option | Description |
|--------|-------------|
| Daily | Repeat every day at scheduled time |
| Weekly | Repeat on same day each week |
| Monthly | Repeat on same date each month |
| Custom | Custom interval (every N days/weeks) |

### UI Flow
1. User creates/edits reminder
2. Toggle "Repeat" option
3. Select recurrence pattern
4. Optionally set end date
5. Save → Creates recurring reminder series

### Visual Indicator
- Recurring reminders show a repeat icon
- Series share a common identifier

## Implementation Guide

### 1. Add Recurrence Fields to Reminder

Update `lib/models/reminder.dart`:

```dart
@Entity()
class Reminder {
  @Id()
  int id = 0;
  
  // ... existing fields ...
  
  // Recurrence fields
  String? recurrenceRule;  // RRULE format: FREQ=DAILY;INTERVAL=1
  DateTime? recurrenceEndDate;
  String? recurrenceSeriesId;  // Groups recurring reminders
  bool isRecurrenceException = false;  // Skipped instance
  
  bool get isRecurring => recurrenceRule != null;
}
```

### 2. Add RRULE Parser (or use package)

```bash
flutter pub add rrule
```

### 3. Update Repository

```dart
// In reminder_repository.dart

List<Reminder> getRecurringReminders() {
  final query = _box.query(Reminder_.recurrenceRule.notNull()).build();
  final results = query.find();
  query.close();
  return results;
}

List<Reminder> getReminderSeries(String seriesId) {
  final query = _box.query(
    Reminder_.recurrenceSeriesId.equals(seriesId)
  ).build();
  final results = query.find();
  query.close();
  return results;
}

void generateNextOccurrence(Reminder template) {
  if (template.recurrenceRule == null) return;
  
  final rrule = RRule.fromString(template.recurrenceRule!);
  final nextDate = rrule.getNextOccurrence(
    after: template.scheduledAt,
    includeAfter: false,
  );
  
  if (nextDate == null) return;
  if (template.recurrenceEndDate != null && 
      nextDate.isAfter(template.recurrenceEndDate!)) return;
  
  // Create new reminder instance
  final newReminder = Reminder(
    url: template.url,
    title: template.title,
    description: template.description,
    imageUrl: template.imageUrl,
    categoryEn: template.categoryEn,
    complexityEn: template.complexityEn,
    importance: template.importance,
    scheduledAt: nextDate,
    createdAt: DateTime.now(),
    recurrenceRule: template.recurrenceRule,
    recurrenceSeriesId: template.recurrenceSeriesId,
  );
  
  save(newReminder);
}
```

### 4. Create RecurrencePicker Widget

```dart
class RecurrencePicker extends StatefulWidget {
  final String? initialRule;
  final DateTime? endDate;
  final Function(String rule, DateTime? endDate) onChanged;

  const RecurrencePicker({
    super.key,
    this.initialRule,
    this.endDate,
    required this.onChanged,
  });

  @override
  State<RecurrencePicker> createState() => _RecurrencePickerState();
}

class _RecurrencePickerState extends State<RecurrencePicker> {
  String _frequency = 'none';
  int _interval = 1;
  DateTime? _endDate;

  @override
  void initState() {
    super.initState();
    if (widget.initialRule != null) {
      _parseExistingRule(widget.initialRule!);
    }
  }

  String _buildRule() {
    if (_frequency == 'none') return '';
    return 'FREQ=${_frequency.toUpperCase()};INTERVAL=$_interval';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          title: Text(Translations.of(context).repeat),
          value: _frequency != 'none',
          onChanged: (value) {
            setState(() {
              _frequency = value ? 'daily' : 'none';
            });
            widget.onChanged(_buildRule(), _endDate);
          },
        ),
        if (_frequency != 'none') ...[
          const Divider(),
          _buildFrequencySelector(),
          const SizedBox(height: 16),
          _buildIntervalSelector(),
          const SizedBox(height: 16),
          _buildEndDateSelector(),
        ],
      ],
    );
  }

  Widget _buildFrequencySelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(Translations.of(context).frequency,
            style: Theme.of(context).textTheme.titleSmall),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'daily', label: Text('Daily')),
            ButtonSegment(value: 'weekly', label: Text('Weekly')),
            ButtonSegment(value: 'monthly', label: Text('Monthly')),
          ],
          selected: {_frequency},
          onSelectionChanged: (selected) {
            setState(() => _frequency = selected.first);
            widget.onChanged(_buildRule(), _endDate);
          },
        ),
      ],
    );
  }

  Widget _buildIntervalSelector() {
    return Row(
      children: [
        Text(Translations.of(context).every),
        const SizedBox(width: 8),
        DropdownButton<int>(
          value: _interval,
          items: List.generate(30, (i) => i + 1)
              .map((i) => DropdownMenuItem(
                    value: i,
                    child: Text('$i'),
                  ))
              .toList(),
          onChanged: (value) {
            setState(() => _interval = value!);
            widget.onChanged(_buildRule(), _endDate);
          },
        ),
        Text(' ${_getIntervalUnit()}'),
      ],
    );
  }

  String _getIntervalUnit() {
    switch (_frequency) {
      case 'daily': return Translations.of(context).days;
      case 'weekly': return Translations.of(context).weeks;
      case 'monthly': return Translations.of(context).months;
      default: return '';
    }
  }
}
```

### 5. Update NotificationService

```dart
// When reminder is marked complete, generate next occurrence
Future<void> onReminderOpened(int id) async {
  final reminder = reminderRepository.getById(id);
  if (reminder == null) return;
  
  if (reminder.isRecurring && !reminder.isRecurrenceException) {
    // Mark current as completed
    reminder.isOpened = true;
    reminder.openedAt = DateTime.now();
    reminderRepository.save(reminder);
    
    // Generate and schedule next occurrence
    reminderRepository.generateNextOccurrence(reminder);
  } else {
    // Normal single reminder handling
    reminder.isOpened = true;
    reminder.openedAt = DateTime.now();
    reminderRepository.save(reminder);
  }
}
```

### 6. Add UI Toggle in SavePostSheet

```dart
// In save_post_sheet.dart, add recurrence picker
ExpansionTile(
  title: Text(Translations.of(context).repeat),
  leading: Icon(Icons.repeat),
  children: [
    Padding(
      padding: const EdgeInsets.all(16),
      child: RecurrencePicker(
        initialRule: _recurrenceRule,
        endDate: _recurrenceEndDate,
        onChanged: (rule, endDate) {
          setState(() {
            _recurrenceRule = rule;
            _recurrenceEndDate = endDate;
          });
        },
      ),
    ),
  ],
)
```

### 7. Visual Indicator in Card

```dart
// In modern_reminder_card.dart, add repeat icon
Row(
  children: [
    Text(reminder.title),
    if (reminder.isRecurring)
      Padding(
        padding: const EdgeInsets.only(left: 4),
        child: Icon(Icons.repeat, size: 16, color: AppColors.accent),
      ),
  ],
)
```

## Dependencies

```yaml
dependencies:
  rrule: ^5.0.0
```

## Testing Checklist

- [ ] Recurrence toggle appears in edit screen
- [ ] Frequency selection works
- [ ] Interval selection works
- [ ] End date selection works
- [ ] Next occurrence generated on completion
- [ ] Series grouping works
- [ ] Recurrence icon shows on cards
- [ ] End date stops generation

## Edge Cases

1. **Endless recurrence**: Generate indefinitely until app closes
2. **Past end date**: Stop generating
3. **Edit one in series**: Creates exception
4. **Delete one in series**: Only deletes that instance
5. **Time zone changes**: Recalculate all instances
