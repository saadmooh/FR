# Feature: Undo Delete

## Overview

Shows a snackbar with undo option after deleting reminders. The deleted item remains recoverable for a few seconds before permanent deletion.

## Implementation

### 1. Create UndoService

```dart
class UndoService {
  Reminder? _lastDeleted;
  Timer? _undoTimer;
  final Duration _undoWindow = const Duration(seconds: 5);

  void setDeleted(Reminder reminder) {
    _lastDeleted = reminder;
    _undoTimer?.cancel();
    _undoTimer = Timer(_undoWindow, () {
      _lastDeleted = null;
    });
  }

  Reminder? get lastDeleted => _lastDeleted;
  bool get canUndo => _lastDeleted != null;

  void clear() {
    _undoTimer?.cancel();
    _lastDeleted = null;
  }
}
```

### 2. Update RemindersScreen Delete

```dart
void _deleteReminder(Reminder reminder) {
  // Store for undo
  undoService.setDeleted(reminder);
  
  // Perform delete
  reminderRepository.delete(reminder.id);
  notificationService.cancelReminder(reminder.id);
  
  setState(() {});
  
  // Show undo snackbar
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(Translations.of(context).deleted),
      duration: const Duration(seconds: 5),
      action: SnackBarAction(
        label: Translations.of(context).undo,
        onPressed: () => _undoDelete(),
      ),
    ),
  );
}

void _undoDelete() {
  final reminder = undoService.lastDeleted;
  if (reminder != null) {
    reminderRepository.save(reminder);
    notificationService.scheduleReminder(reminder);
    undoService.clear();
    setState(() {});
  }
}
```

### 3. Update Bulk Delete

```dart
Future<void> _deleteSelected() async {
  final toDelete = _selectedIds.map((id) => reminderRepository.getById(id))
      .whereType<Reminder>()
      .toList();
  
  // Store all for undo
  for (final reminder in toDelete) {
    undoService.setDeleted(reminder);
  }
  
  // Delete all
  await bulkActionsService.deleteReminders(_selectedIds.toList());
  _toggleSelectionMode();
  setState(() {});
  
  // Show snackbar
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(Translations.of(context).deletedCount(toDelete.length)),
      action: SnackBarAction(
        label: Translations.of(context).undo,
        onPressed: _undoBulkDelete,
      ),
    ),
  );
}
```

## Testing Checklist

- [ ] Snackbar appears after delete
- [ ] Undo restores reminder
- [ ] Undo restores notification
- [ ] Snackbar auto-dismisses
- [ ] Bulk delete shows undo
- [ ] Undo clears after timeout

## Edge Cases

1. **Delete during undo**: Replace undo item
2. **Multiple deletes**: Keep only last
3. **App killed**: Undo data lost
