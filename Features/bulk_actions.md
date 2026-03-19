# Feature: Bulk Actions

## Overview

Enables users to select multiple reminders simultaneously and perform batch operations like delete, reschedule, or mark as read. Essential for users managing large numbers of saved posts.

## User Experience

### Selection Mode
1. User taps "Select" button or long-press any card
2. Checkboxes appear on all reminder cards
3. Selection count badge updates in real-time
4. Floating action bar appears at bottom with actions

### Batch Operations Available
| Action | Icon | Description |
|--------|------|-------------|
| Select All | select_all | Toggle all selections |
| Delete | delete | Remove selected reminders |
| Mark as Read | check_circle | Mark all as opened |
| Reschedule | schedule | Change time for all |
| Cancel | close | Exit selection mode |

### UI Components

**Selection FAB Bar:**
```
┌─────────────────────────────────────────────────────┐
│  [✓ 3 selected]                    [Delete] [Menu] │
└─────────────────────────────────────────────────────┘
```

**Multi-select Card State:**
```
┌──────────────────────────────────────┐
│ ☐  [Image]  Title                    │
│         Category • 9:00 AM           │
└──────────────────────────────────────┘
```

## Implementation Guide

### 1. Add Selection State to RemindersScreen

```dart
class RemindersScreenState extends State<RemindersScreen> {
  bool _isSelectionMode = false;
  final Set<int> _selectedIds = {};
  
  void _toggleSelectionMode() {
    setState(() {
      _isSelectionMode = !_isSelectionMode;
      if (!_isSelectionMode) {
        _selectedIds.clear();
      }
    });
  }
  
  void _toggleSelection(int id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
      if (_selectedIds.isEmpty) {
        _isSelectionMode = false;
      }
    });
  }
  
  void _selectAll() {
    setState(() {
      _selectedIds.addAll(_filteredReminders.map((r) => r.id));
    });
  }
}
```

### 2. Modify ReminderCard for Selection

Update `lib/widgets/modern_reminder_card.dart`:

```dart
class ModernReminderCard extends StatelessWidget {
  // Add these parameters
  final bool isSelectionMode;
  final bool isSelected;
  final VoidCallback? onSelectionToggle;
  
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isSelectionMode ? onSelectionToggle : onTap,
      onLongPress: isSelectionMode ? null : onLongPress,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        child: Row(
          children: [
            if (isSelectionMode) ...[
              Checkbox(
                value: isSelected,
                onChanged: (_) => onSelectionToggle?.call(),
              ),
            ],
            // Existing card content
            Expanded(child: _buildCardContent()),
          ],
        ),
      ),
    );
  }
}
```

### 3. Create BulkActionsService

```dart
// lib/services/bulk_actions_service.dart

class BulkActionsService {
  final ReminderRepository _reminderRepository;
  final NotificationService _notificationService;
  
  BulkActionsService(this._reminderRepository, this._notificationService);
  
  Future<int> deleteReminders(List<int> ids) async {
    int deleted = 0;
    for (final id in ids) {
      if (_reminderRepository.delete(id)) {
        await _notificationService.cancelReminder(id);
        deleted++;
      }
    }
    return deleted;
  }
  
  Future<void> markAsRead(List<int> ids) async {
    for (final id in ids) {
      final reminder = _reminderRepository.getById(id);
      if (reminder != null && !reminder.isOpened) {
        reminder.isOpened = true;
        reminder.openedAt = DateTime.now();
        _reminderRepository.save(reminder);
      }
    }
  }
  
  Future<void> rescheduleAll(List<int> ids, DateTime newTime) async {
    for (final id in ids) {
      final reminder = _reminderRepository.getById(id);
      if (reminder != null) {
        await _notificationService.cancelReminder(id);
        reminder.scheduledAt = newTime;
        _reminderRepository.save(reminder);
        await _notificationService.scheduleReminder(reminder);
      }
    }
  }
}
```

### 4. Create BulkActionsBottomBar Widget

```dart
// lib/widgets/bulk_actions_bottom_bar.dart

class BulkActionsBottomBar extends StatelessWidget {
  final int selectedCount;
  final VoidCallback onSelectAll;
  final VoidCallback onDelete;
  final VoidCallback onMarkRead;
  final VoidCallback? onReschedule;
  final VoidCallback onCancel;

  const BulkActionsBottomBar({
    super.key,
    required this.selectedCount,
    required this.onSelectAll,
    required this.onDelete,
    required this.onMarkRead,
    this.onReschedule,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            Text(
              '$selectedCount selected',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.select_all),
              onPressed: onSelectAll,
              tooltip: 'Select All',
            ),
            IconButton(
              icon: const Icon(Icons.check_circle_outline),
              onPressed: selectedCount > 0 ? onMarkRead : null,
              tooltip: 'Mark as Read',
            ),
            if (onReschedule != null)
              IconButton(
                icon: const Icon(Icons.schedule),
                onPressed: onReschedule,
                tooltip: 'Reschedule',
              ),
            IconButton(
              icon: const Icon(Icons.delete_outline, color: AppColors.error),
              onPressed: selectedCount > 0 ? onDelete : null,
              tooltip: 'Delete',
            ),
          ],
        ),
      ),
    );
  }
}
```

### 5. Update RemindersScreen Layout

```dart
@override
Widget build(BuildContext context) {
  final t = Translations.of(context);
  
  return Scaffold(
    appBar: _isSelectionMode
        ? _buildSelectionAppBar(t)
        : _buildNormalAppBar(t),
    body: Stack(
      children: [
        // Existing reminder list
        _buildRemindersList(),
        
        // Bulk actions bar
        if (_isSelectionMode)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: BulkActionsBottomBar(
              selectedCount: _selectedIds.length,
              onSelectAll: _selectAll,
              onDelete: () => _showDeleteConfirmation(context),
              onMarkRead: () => _markSelectedAsRead(),
              onReschedule: () => _showRescheduleDialog(),
              onCancel: _toggleSelectionMode,
            ),
          ),
      ],
    ),
  );
}

PreferredSizeWidget _buildSelectionAppBar(AppTranslations t) {
  return AppBar(
    leading: IconButton(
      icon: const Icon(Icons.close),
      onPressed: _toggleSelectionMode,
    ),
    title: Text('${_selectedIds.length} selected'),
    actions: [
      IconButton(
        icon: const Icon(Icons.select_all),
        onPressed: _selectAll,
      ),
    ],
  );
}
```

### 6. Add Delete Confirmation Dialog

```dart
Future<void> _showDeleteConfirmation(BuildContext context) async {
  final t = Translations.of(context);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(t.deleteSelectedTitle),
      content: Text(t.deleteSelectedMessage(_selectedIds.length)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(t.cancel),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          style: TextButton.styleFrom(foregroundColor: AppColors.error),
          child: Text(t.delete),
        ),
      ],
    ),
  );
  
  if (confirmed == true) {
    await _bulkActionsService.deleteReminders(_selectedIds.toList());
    _toggleSelectionMode();
    setState(() {});
  }
}
```

### 7. Add Reschedule Dialog

```dart
Future<void> _showRescheduleDialog() async {
  final t = Translations.of(context);
  final newTime = await showDateTimePicker(context: context);
  
  if (newTime != null) {
    await _bulkActionsService.rescheduleAll(
      _selectedIds.toList(),
      newTime,
    );
    _toggleSelectionMode();
    setState(() {});
  }
}
```

## Database Changes

None required. Operations use existing repository methods.

## Testing Checklist

- [ ] Selection mode activates on long-press
- [ ] Checkboxes toggle correctly
- [ ] Selection count updates in real-time
- [ ] Select all toggles all items
- [ ] Delete removes all selected items
- [ ] Mark as read updates all selected
- [ ] Reschedule changes all selected times
- [ ] Exit selection mode clears selection
- [ ] Empty selection auto-exits selection mode

## Edge Cases

1. **Delete last selected item**: Auto-exit selection mode
2. **Select while filtering**: Only select visible items
3. **Rapid toggle**: Debounce checkbox updates
4. **Large selection (100+)**: Batch database operations

## Performance Considerations

- Use `const` for checkbox widgets
- Batch database operations in transactions
- Lazy load card images during selection
- Debounce selection state updates
