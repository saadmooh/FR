# Feature: Tags/Labels

## Overview

Allows users to create custom tags and assign them to reminders for flexible organization beyond AI-generated categories. Tags enable personal categorization and filtering.

## User Experience

### Tag Management
- Create tags with custom names and colors
- Assign multiple tags per reminder
- Filter reminders by tag
- View all tags in settings

### UI Components

**Tag Chip (in cards):**
```
[🏷️ Work] [🏷️ Important]
```

**Tag Selector (in edit):**
```
Tags
├── 🔴 Work
├── 🔵 Personal
├── 🟢 Urgent
├── 🟡 Read Later
└── [+ Add New Tag]
```

**Filter by Tag:**
```
Filter: [All ▼]
       [Work]
       [Personal]
       [Important]
```

## Implementation Guide

### 1. Create Tag Model

Create `lib/models/tag.dart`:

```dart
@Entity()
class Tag {
  @Id()
  int id = 0;
  
  String name;
  int colorValue;  // Color.value
  
  @Property(type: PropertyType.date)
  DateTime createdAt;
  
  Tag({
    this.id = 0,
    required this.name,
    required this.colorValue,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();
  
  Color get color => Color(colorValue);
  
  @Backlink('reminders')
  final queries: ToMany<Reminder> = ToMany<Reminder>();
}
```

### 2. Update Reminder Model

```dart
@Entity()
class Reminder {
  // ... existing fields ...
  
  final tags = ToMany<Tag>();
}
```

### 3. Create TagRepository

Create `lib/repositories/tag_repository.dart`:

```dart
class TagRepository {
  final Box<Tag> _box;
  
  TagRepository(Store store) : _box = store.box<Tag>();
  
  int save(Tag tag) => _box.put(tag);
  
  Tag? getById(int id) => _box.get(id);
  
  List<Tag> getAll() => _box.getAll();
  
  List<Tag> getByName(String name) {
    final query = _box.query(Tag_.name.equals(name)).build();
    final results = query.find();
    query.close();
    return results;
  }
  
  bool delete(int id) => _box.remove(id);
  
  List<Tag> getTagsForReminder(int reminderId) {
    final reminder = store.box<Reminder>().get(reminderId);
    return reminder?.tags.toList() ?? [];
  }
}
```

### 4. Update ReminderRepository

```dart
class ReminderRepository {
  // ... existing code ...
  
  void addTagToReminder(int reminderId, int tagId) {
    final reminder = _box.get(reminderId);
    final tag = tagRepository.getById(tagId);
    if (reminder != null && tag != null) {
      reminder.tags.add(tag);
      _box.put(reminder);
    }
  }
  
  void removeTagFromReminder(int reminderId, int tagId) {
    final reminder = _box.get(reminderId);
    if (reminder != null) {
      reminder.tags.removeWhere((t) => t.id == tagId);
      _box.put(reminder);
    }
  }
  
  List<Reminder> getByTag(int tagId) {
    final tag = tagRepository.getById(tagId);
    if (tag == null) return [];
    return tag.reminders.toList();
  }
}
```

### 5. Create TagChip Widget

Create `lib/widgets/tag_chip.dart`:

```dart
class TagChip extends StatelessWidget {
  final Tag tag;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;
  final bool selected;

  const TagChip({
    super.key,
    required this.tag,
    this.onTap,
    this.onDelete,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: selected 
              ? tag.color.withOpacity(0.3)
              : tag.color.withOpacity(0.1),
          borderRadius: BorderRadius.zero,
          border: Border.all(
            color: tag.color,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              tag.name,
              style: TextStyle(
                color: tag.color,
                fontSize: 12,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            if (onDelete != null)
              GestureDetector(
                onTap: onDelete,
                child: Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Icon(Icons.close, size: 14, color: tag.color),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
```

### 6. Create TagSelector Widget

Create `lib/widgets/tag_selector.dart`:

```dart
class TagSelector extends StatelessWidget {
  final List<Tag> selectedTags;
  final Function(Tag) onTagAdded;
  final Function(Tag) onTagRemoved;
  final VoidCallback onCreateTag;

  const TagSelector({
    super.key,
    required this.selectedTags,
    required this.onTagAdded,
    required this.onTagRemoved,
    required this.onCreateTag,
  });

  @override
  Widget build(BuildContext context) {
    final allTags = tagRepository.getAll();
    final unselectedTags = allTags
        .where((t) => !selectedTags.any((s) => s.id == t.id))
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ...selectedTags.map((tag) => TagChip(
                  tag: tag,
                  selected: true,
                  onDelete: () => onTagRemoved(tag),
                )),
            ActionChip(
              label: Text(Translations.of(context).addTag),
              avatar: const Icon(Icons.add, size: 18),
              onPressed: onCreateTag,
            ),
          ],
        ),
        if (unselectedTags.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            Translations.of(context).availableTags,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: unselectedTags
                .map((tag) => TagChip(tag: tag, onTap: () => onTagAdded(tag)))
                .toList(),
          ),
        ],
      ],
    );
  }
}
```

### 7. Create TagManagerScreen

Create `lib/screens/tag_manager_screen.dart`:

```dart
class TagManagerScreen extends StatelessWidget {
  const TagManagerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final tags = tagRepository.getAll();

    return Scaffold(
      appBar: AppBar(
        title: Text(t.manageTags),
      ),
      body: tags.isEmpty
          ? EmptyState(
              icon: Icons.label_outline,
              title: t.noTagsTitle,
              subtitle: t.noTagsSubtitle,
            )
          : ListView.builder(
              itemCount: tags.length,
              itemBuilder: (context, index) {
                final tag = tags[index];
                return ListTile(
                  leading: Container(
                    width: 24,
                    height: 24,
                    color: tag.color,
                  ),
                  title: Text(tag.name),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _confirmDelete(context, tag),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showCreateDialog(context),
        child: const Icon(Icons.add),
      ),
    );
  }

  void _showCreateDialog(BuildContext context) {
    final nameController = TextEditingController();
    Color selectedColor = Colors.red;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(Translations.of(context).createTag),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: InputDecoration(
                labelText: Translations.of(context).tagName,
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              children: _availableColors.map((color) {
                return GestureDetector(
                  onTap: () {
                    selectedColor = color;
                  },
                  child: Container(
                    width: 32,
                    height: 32,
                    color: color,
                  ),
                );
              }).toList(),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(Translations.of(context).cancel),
          ),
          TextButton(
            onPressed: () {
              if (nameController.text.isNotEmpty) {
                tagRepository.save(Tag(
                  name: nameController.text,
                  colorValue: selectedColor.value,
                ));
                Navigator.pop(context);
              }
            },
            child: Text(Translations.of(context).create),
          ),
        ],
      ),
    );
  }
}
```

### 8. Add Tag Filter to RemindersScreen

```dart
// Add filter option
DropdownButton<String>(
  value: _selectedTagFilter,
  hint: Text(t.allTags),
  items: [
    DropdownMenuItem(value: null, child: Text(t.allTags)),
    ...tagRepository.getAll().map((tag) =>
      DropdownMenuItem(
        value: tag.id.toString(),
        child: Row(
          children: [
            Container(width: 12, height: 12, color: tag.color),
            const SizedBox(width: 8),
            Text(tag.name),
          ],
        ),
      ),
    ),
  ],
  onChanged: (value) {
    setState(() => _selectedTagFilter = value);
    _applyFilters();
  },
)
```

### 9. Add Translations

```dart
String get tags => 'Tags';
String get manageTags => 'Manage Tags';
String get addTag => 'Add Tag';
String get createTag => 'Create Tag';
String get tagName => 'Tag name';
String get noTagsTitle => 'No tags yet';
String get noTagsSubtitle => 'Create tags to organize your reminders';
String get availableTags => 'Available tags';
```

## Testing Checklist

- [ ] Tags can be created with name and color
- [ ] Tags can be assigned to reminders
- [ ] Tags appear on reminder cards
- [ ] Filter by tag works
- [ ] Tags persist across restarts
- [ ] Tags can be deleted
- [ ] Multiple tags per reminder work

## Edge Cases

1. **Delete tag with reminders**: Remove tag from reminders, not reminders
2. **Duplicate tag names**: Prevent or allow with warning
3. **Long tag names**: Truncate with ellipsis
4. **Many tags (50+)**: Scrollable list in selector
