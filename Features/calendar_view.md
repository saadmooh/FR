# Feature: Calendar View

## Overview

Provides a visual calendar display showing all scheduled reminders. Users can view their reading schedule at a glance and tap on dates to see reminders for that day.

## User Experience

### Calendar Display Modes
1. **Monthly Calendar** - Overview with dot indicators for reminder days
2. **Daily List** - Click date to see reminders for that day

### UI Layout
```
┌─────────────────────────────────────────┐
│ ← March 2026                    [≡]     │
├─────────────────────────────────────────┤
│     < February    March    April >      │
├─────────────────────────────────────────┤
│ Su   Mo   Tu   We   Th   Fr   Sa        │
│  1    2    3    4    5    6    7       │
│  8    9   [10] 11   12   13   14       │
│ 15   16   17   18   19   20   21       │
│ 22   23   24   25   26  [27]  28       │
│ 29   30   31                            │
├─────────────────────────────────────────┤
│  Reminders for March 27                 │
├─────────────────────────────────────────┤
│ ┌─────────────────────────────────────┐ │
│ │ [IMG] Title                         │ │
│ │         Category • 9:00 AM          │ │
│ └─────────────────────────────────────┘ │
│ ┌─────────────────────────────────────┐ │
│ │ [IMG] Title                         │ │
│ │         Category • 7:00 PM          │ │
│ └─────────────────────────────────────┘ │
└─────────────────────────────────────────┘
```

### Indicators
- **Colored dots**: Show number of reminders per day
- **Different colors**: Category or importance level
- **Today highlight**: Current date highlighted
- **Selected date**: Outlined or filled

## Implementation Guide

### 1. Add Calendar Package

```bash
flutter pub add table_calendar
```

### 2. Create CalendarScreen

Create `lib/screens/calendar_screen.dart`:

```dart
import 'package:table_calendar/table_calendar.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  CalendarFormat _calendarFormat = CalendarFormat.month;
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  Map<DateTime, List<Reminder>> _events = {};

  @override
  void initState() {
    super.initState();
    _selectedDay = _focusedDay;
    _loadEvents();
  }

  void _loadEvents() {
    final allReminders = reminderRepository.getPendingReminders();
    _events = _groupRemindersByDate(allReminders);
  }

  Map<DateTime, List<Reminder>> _groupRemindersByDate(List<Reminder> reminders) {
    final Map<DateTime, List<Reminder>> grouped = {};
    for (final reminder in reminders) {
      final date = DateTime(
        reminder.scheduledAt.year,
        reminder.scheduledAt.month,
        reminder.scheduledAt.day,
      );
      grouped.putIfAbsent(date, () => []).add(reminder);
    }
    return grouped;
  }

  List<Reminder> _getEventsForDay(DateTime day) {
    final normalizedDay = DateTime(day.year, day.month, day.day);
    return _events[normalizedDay] ?? [];
  }

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    
    return Scaffold(
      appBar: AppBar(
        title: Text(t.calendar),
        actions: [
          IconButton(
            icon: const Icon(Icons.today),
            onPressed: () {
              setState(() {
                _focusedDay = DateTime.now();
                _selectedDay = DateTime.now();
              });
            },
            tooltip: t.today,
          ),
        ],
      ),
      body: Column(
        children: [
          TableCalendar<Reminder>(
            firstDay: DateTime.utc(2020, 1, 1),
            lastDay: DateTime.utc(2030, 12, 31),
            focusedDay: _focusedDay,
            calendarFormat: _calendarFormat,
            selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
            eventLoader: _getEventsForDay,
            startingDayOfWeek: StartingDayOfWeek.sunday,
            calendarStyle: CalendarStyle(
              todayDecoration: BoxDecoration(
                color: AppColors.accent.withOpacity(0.3),
                shape: BoxShape.circle,
              ),
              selectedDecoration: const BoxDecoration(
                color: AppColors.accent,
                shape: BoxShape.circle,
              ),
              markerDecoration: const BoxDecoration(
                color: AppColors.accent,
                shape: BoxShape.circle,
              ),
              markersMaxCount: 3,
              outsideDaysVisible: false,
            ),
            headerStyle: HeaderStyle(
              formatButtonVisible: true,
              titleCentered: true,
              formatButtonDecoration: BoxDecoration(
                border: Border.all(color: AppColors.accent),
                borderRadius: BorderRadius.zero,
              ),
              formatButtonTextStyle: const TextStyle(color: AppColors.accent),
            ),
            onDaySelected: (selectedDay, focusedDay) {
              setState(() {
                _selectedDay = selectedDay;
                _focusedDay = focusedDay;
              });
            },
            onFormatChanged: (format) {
              setState(() {
                _calendarFormat = format;
              });
            },
            onPageChanged: (focusedDay) {
              _focusedDay = focusedDay;
            },
            calendarBuilders: CalendarBuilders(
              markerBuilder: (context, date, events) {
                if (events.isEmpty) return null;
                return Positioned(
                  bottom: 1,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: events.take(3).map((event) {
                      return Container(
                        margin: const EdgeInsets.symmetric(horizontal: 1),
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _getImportanceColor(event.importance),
                        ),
                      );
                    }).toList(),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _buildEventsList(t),
          ),
        ],
      ),
    );
  }

  Widget _buildEventsList(AppTranslations t) {
    final dayReminders = _getEventsForDay(_selectedDay ?? _focusedDay);
    
    if (dayReminders.isEmpty) {
      return EmptyState(
        icon: Icons.event_busy,
        title: t.noRemindersForDay,
        subtitle: t.tapDateToView,
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: dayReminders.length,
      itemBuilder: (context, index) {
        final reminder = dayReminders[index];
        return ModernReminderCard(
          reminder: reminder,
          onTap: () => context.push('/post/${reminder.id}'),
        );
      },
    );
  }

  Color _getImportanceColor(String importance) {
    switch (importance.toLowerCase()) {
      case 'day':
        return AppColors.warning;
      case 'week':
        return AppColors.accent;
      case 'month':
        return AppColors.success;
      default:
        return AppColors.accent;
    }
  }
}
```

### 3. Add to Router

Update `lib/core/app_router.dart`:

```dart
GoRoute(
  path: '/calendar',
  builder: (context, state) => const CalendarScreen(),
),
```

### 4. Add Calendar to Navigation

Add calendar icon to bottom navigation or drawer:

```dart
// In MainShell or wherever bottom nav is defined
BottomNavigationBarItem(
  icon: Icon(Icons.calendar_month),
  label: t.calendar,
),
```

### 5. Add Translations

```dart
// In translations
String get calendar => 'Calendar';
String get today => 'Today';
String get noRemindersForDay => 'No reminders for this day';
String get tapDateToView => 'Tap a date to view reminders';
String get remindersFor => 'Reminders for {date}';
```

### 6. Enhanced: Add Month Stats

Add below calendar header:

```dart
Widget _buildMonthStats() {
  final monthStart = DateTime(_focusedDay.year, _focusedDay.month, 1);
  final monthEnd = DateTime(_focusedDay.year, _focusedDay.month + 1, 0);
  final monthReminders = _getRemindersInRange(monthStart, monthEnd);
  
  return Container(
    padding: const EdgeInsets.all(16),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        _buildStatItem(Icons.bookmark, monthReminders.length, 'Scheduled'),
        _buildStatItem(Icons.check_circle, _getOpenedCount(monthReminders), 'Opened'),
        _buildStatItem(Icons.pending, _getPendingCount(monthReminders), 'Pending'),
      ],
    ),
  );
}
```

### 7. Enhanced: Category Filter

Add filter chips above calendar:

```dart
Wrap(
  spacing: 8,
  children: [
    FilterChip(
      label: Text(t.allCategories),
      selected: _selectedCategory == null,
      onSelected: (_) => _filterByCategory(null),
    ),
    for (final category in _categories)
      FilterChip(
        label: Text(category),
        selected: _selectedCategory == category,
        onSelected: (_) => _filterByCategory(category),
      ),
  ],
)
```

## Dependencies

```yaml
dependencies:
  table_calendar: ^3.1.0
```

## Testing Checklist

- [ ] Calendar renders correctly
- [ ] Reminders appear on correct dates
- [ ] Dot markers show per day
- [ ] Date selection updates list
- [ ] Month navigation works
- [ ] Today button jumps to current date
- [ ] Format toggle (month/week) works
- [ ] Empty days show empty state

## Edge Cases

1. **No reminders**: Show empty calendar with message
2. **Many reminders (20+)**: Limit markers, show count
3. **Past dates**: Show as dimmed
4. **Time zones**: Use local timezone consistently
5. **Leap year**: February handling correct

## Performance Considerations

- Load events lazily per month
- Cache calendar events for current view
- Limit event markers to 3 per day
- Use `const` for static calendar config

## Related Features

- [Statistics Screen](./statistics_screen.md) - Existing analytics
- [Bulk Actions](./bulk_actions.md) - Select multiple from calendar
