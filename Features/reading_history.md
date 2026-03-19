# Feature: Reading History

## Overview

Maintains a log of all opened posts with timestamps. Users can browse their reading history and see their reading patterns over time.

## Implementation

### 1. Enhance CategoryStatistic Model

Already partially implemented with `openedAt` tracking. Expand to include:

```dart
class ReadingHistoryEntry {
  final int reminderId;
  final String title;
  final DateTime openedAt;
  final int secondsToOpen;  // From scheduled to opened
  final String category;
}
```

### 2. Create ReadingHistoryRepository

```dart
class ReadingHistoryRepository {
  final Box<Reminder> _box;

  ReadingHistoryRepository(Store store) : _box = store.box<Reminder>();

  List<Reminder> getReadReminders({int limit = 50, int offset = 0}) {
    final query = _box.query(Reminder_.isOpened.equals(true))
        .order(Reminder_.openedAt, flags: Order.descending)
        .build();
    
    final results = query.find();
    query.close();
    
    return results.skip(offset).take(limit).toList();
  }

  List<Reminder> getReadRemindersByDateRange(DateTime start, DateTime end) {
    final query = _box.query(
      Reminder_.isOpened.equals(true) &
      Reminder_.openedAt.betweenDates(start, end)
    ).build();
    
    final results = query.find();
    query.close();
    return results;
  }

  int getTotalReadCount() {
    final query = _box.query(Reminder_.isOpened.equals(true)).build();
    final count = query.count();
    query.close();
    return count;
  }

  Map<int, int> getReadCountByHour() {
    final read = getReadReminders(limit: 10000);
    final Map<int, int> hourCounts = {};
    
    for (final reminder in read) {
      if (reminder.openedAt != null) {
        final hour = reminder.openedAt!.hour;
        hourCounts[hour] = (hourCounts[hour] ?? 0) + 1;
      }
    }
    
    return hourCounts;
  }
}
```

### 3. Create ReadingHistoryScreen

```dart
class ReadingHistoryScreen extends StatelessWidget {
  const ReadingHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final history = historyRepository.getReadReminders(limit: 100);

    return Scaffold(
      appBar: AppBar(
        title: Text(t.readingHistory),
      ),
      body: history.isEmpty
          ? EmptyState(
              icon: Icons.history,
              title: t.noHistoryTitle,
              subtitle: t.noHistorySubtitle,
            )
          : ListView.builder(
              itemCount: history.length,
              itemBuilder: (context, index) {
                final reminder = history[index];
                return _HistoryItem(reminder: reminder);
              },
            ),
    );
  }
}

class _HistoryItem extends StatelessWidget {
  final Reminder reminder;

  const _HistoryItem({required this.reminder});

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final openedAt = reminder.openedAt!;
    
    return ListTile(
      leading: reminder.imageUrl != null
          ? Image.network(reminder.imageUrl!, width: 50, height: 50)
          : Container(width: 50, height: 50),
      title: Text(reminder.title),
      subtitle: Text(
        '${reminder.categoryEn} • ${_formatDate(openedAt)}',
      ),
      trailing: Text(_formatTime(openedAt)),
      onTap: () => context.push('/post/${reminder.id}'),
    );
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
      return 'Today';
    }
    // ... format appropriately
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  String _formatTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
```

### 4. Add to Navigation

```dart
// In settings or drawer
ListTile(
  leading: const Icon(Icons.history),
  title: Text(Translations.of(context).readingHistory),
  onTap: () => context.push('/history'),
),
```

### 5. Add Translations

```dart
String get readingHistory => 'Reading History';
String get noHistoryTitle => 'No reading history';
String get noHistorySubtitle => 'Posts you open will appear here';
```
