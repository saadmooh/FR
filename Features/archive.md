# Feature: Archive

## Overview

Provides a soft-delete mechanism where users can archive reminders instead of permanently removing them. Archived items can be viewed in an archive section and optionally restored or permanently deleted.

## User Experience

### Archive vs Delete
| Action | Location | Recovery | Permanence |
|--------|----------|----------|------------|
| Delete | Immediate removal | Undo toast (5 sec) | Permanent |
| Archive | Archive section | Restore anytime | Manual delete |

### User Flow
1. **Archive**: Swipe left on card → "Archive" button → Item moves to archive
2. **View Archive**: Bottom nav or menu → "Archive" section
3. **Restore**: In archive → Swipe right → "Restore" → Returns to main list
4. **Permanent Delete**: In archive → Swipe left → "Delete" → Confirmation → Gone forever

### Archive Screen UI
```
┌─────────────────────────────────────────┐
│ ← Archive                      [Empty]  │
├─────────────────────────────────────────┤
│ [Card] Title                           │
│ Category • Archived 3 days ago           │
│                      [Restore] [Delete] │
├─────────────────────────────────────────┤
│ [Card] Title                           │
│ Category • Archived 1 week ago           │
│                      [Restore] [Delete] │
├─────────────────────────────────────────┤
│                                         │
│          📦 Archive is empty            │
│                                         │
└─────────────────────────────────────────┘
```

## Implementation Guide

### 1. Add ArchivedAt Field to Reminder Model

Update `lib/models/reminder.dart`:

```dart
@Entity()
class Reminder {
  @Id()
  int id = 0;
  
  // ... existing fields ...
  
  // Archive fields
  @Property(type: PropertyType.date)
  DateTime? archivedAt;
  
  bool get isArchived => archivedAt != null;
  
  // Optional: original scheduled time before archive
  @Property(type: PropertyType.date)
  DateTime? originalScheduledAt;
}
```

### 2. Run ObjectBox Code Generation

```bash
dart run build_runner build --delete-conflicting-outputs
```

### 3. Add Repository Methods

Update `lib/repositories/reminder_repository.dart`:

```dart
class ReminderRepository {
  // ... existing methods ...
  
  // Archive operations
  void archive(int id) {
    final reminder = _box.get(id);
    if (reminder != null) {
      reminder.originalScheduledAt = reminder.scheduledAt;
      reminder.archivedAt = DateTime.now();
      _box.put(reminder);
    }
  }
  
  void restore(int id) {
    final reminder = _box.get(id);
    if (reminder != null) {
      reminder.archivedAt = null;
      // Optionally restore original scheduled time
      if (reminder.originalScheduledAt != null) {
        reminder.scheduledAt = reminder.originalScheduledAt!;
        reminder.originalScheduledAt = null;
      }
      _box.put(reminder);
    }
  }
  
  List<Reminder> getArchived() {
    final query = _box.query(Reminder_.archivedAt.notNull()).build();
    final results = query.find();
    query.close();
    results.sort((a, b) => 
        (b.archivedAt ?? DateTime.now())
            .compareTo(a.archivedAt ?? DateTime.now()));
    return results;
  }
  
  void permanentlyDelete(int id) {
    _box.remove(id);
  }
  
  int getArchivedCount() {
    final query = _box.query(Reminder_.archivedAt.notNull()).build();
    final count = query.count();
    query.close();
    return count;
  }
}
```

### 4. Update NotificationService

```dart
// When archiving, cancel notification
Future<void> archiveReminder(int id) async {
  await cancelReminder(id);
  reminderRepository.archive(id);
}

// When restoring, reschedule notification
Future<void> restoreReminder(int id) async {
  final reminder = reminderRepository.getById(id);
  if (reminder != null) {
    reminderRepository.restore(id);
    await scheduleReminder(reminder);
  }
}
```

### 5. Create ArchiveScreen

Create `lib/screens/archive_screen.dart`:

```dart
class ArchiveScreen extends StatefulWidget {
  const ArchiveScreen({super.key});

  @override
  State<ArchiveScreen> createState() => _ArchiveScreenState();
}

class _ArchiveScreenState extends State<ArchiveScreen> {
  late List<Reminder> _archivedReminders;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadArchived();
  }

  void _loadArchived() {
    setState(() {
      _archivedReminders = reminderRepository.getArchived();
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    
    return Scaffold(
      appBar: AppBar(
        title: Text(t.archive),
        actions: [
          if (_archivedReminders.isNotEmpty)
            TextButton(
              onPressed: _showEmptyArchiveConfirmation,
              child: Text(t.emptyArchive, style: TextStyle(color: AppColors.error)),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _archivedReminders.isEmpty
              ? EmptyState(
                  icon: Icons.archive_outlined,
                  title: t.archiveEmptyTitle,
                  subtitle: t.archiveEmptySubtitle,
                )
              : ListView.builder(
                  itemCount: _archivedReminders.length,
                  itemBuilder: (context, index) {
                    final reminder = _archivedReminders[index];
                    return _ArchivedReminderItem(
                      reminder: reminder,
                      onRestore: () => _restoreReminder(reminder),
                      onDelete: () => _confirmPermanentDelete(reminder),
                    );
                  },
                ),
    );
  }

  Future<void> _restoreReminder(Reminder reminder) async {
    await notificationService.restoreReminder(reminder.id);
    _loadArchived();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(Translations.of(context).restored),
          action: SnackBarAction(
            label: Translations.of(context).view,
            onPressed: () => context.pop(),
          ),
        ),
      );
    }
  }

  Future<void> _confirmPermanentDelete(Reminder reminder) async {
    final confirmed = await showDialog<bool>(...);
    if (confirmed == true) {
      await notificationService.permanentlyDelete(reminder.id);
      _loadArchived();
    }
  }
}
```

### 6. Create ArchivedReminderItem Widget

```dart
// lib/widgets/archived_reminder_item.dart

class ArchivedReminderItem extends StatelessWidget {
  final Reminder reminder;
  final VoidCallback onRestore;
  final VoidCallback onDelete;

  const ArchivedReminderItem({
    super.key,
    required this.reminder,
    required this.onRestore,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final archivedDays = DateTime.now().difference(reminder.archivedAt!).inDays;
    
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            // Thumbnail
            ClipRRect(
              borderRadius: BorderRadius.zero,
              child: reminder.imageUrl != null
                  ? Image.network(reminder.imageUrl!, width: 60, height: 60, fit: BoxFit.cover)
                  : Container(width: 60, height: 60, color: AppColors.surfaceLight),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(reminder.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text(
                    '${reminder.categoryEn} • ${t.archivedDaysAgo(archivedDays)}',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: onRestore,
              child: Text(t.restore),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, color: AppColors.error),
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}
```

### 7. Add Swipe Actions to ReminderCard

Update `lib/widgets/modern_reminder_card.dart`:

```dart
// Add archive action to existing swipe or long-press menu
case 'archive':
  await notificationService.archiveReminder(reminder.id);
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(Translations.of(context).archived),
        action: SnackBarAction(
          label: Translations.of(context).undo,
          onPressed: () => notificationService.restoreReminder(reminder.id),
        ),
      ),
    );
  }
  break;
```

### 8. Add Archive to Navigation

Update `lib/core/app_router.dart`:

```dart
GoRoute(
  path: '/archive',
  builder: (context, state) => const ArchiveScreen(),
),
```

### 9. Add Translations

```dart
// In translations
String get archive => 'Archive';
String get archived => 'Archived';
String get restore => 'Restore';
String get restored => 'Restored';
String get archiveEmptyTitle => 'Archive is empty';
String get archiveEmptySubtitle => 'Archived items will appear here';
String get archivedDaysAgo => 'Archived {days} days ago';
String get emptyArchive => 'Empty Archive';
String get emptyArchiveConfirm => 'Delete all archived items permanently?';
String get deleteFromArchive => 'Delete from archive';
```

## Database Changes

```sql
-- After ObjectBox regeneration, new columns will be:
-- archived_at DATETIME NULL
-- original_scheduled_at DATETIME NULL
```

## Testing Checklist

- [ ] Archive moves item from main list
- [ ] Archive cancels scheduled notification
- [ ] Archive screen shows archived items
- [ ] Restore returns item to main list
- [ ] Restore reschedules notification
- [ ] Permanent delete removes from database
- [ ] Archive badge shows count in navigation
- [ ] Empty archive shows empty state

## Edge Cases

1. **Restore expired reminder**: Keep as unread, set new scheduled time
2. **Archive already opened**: Mark as unread when restored
3. **Empty archive**: Show confirmation with count
4. **Restore while app closed**: Notification rescheduled on restore

## Related Features

- [Bulk Actions](./bulk_actions.md) - Bulk archive support
- [Undo Delete](./undo_delete.md) - Toast-based undo
