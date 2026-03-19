# Feature: Reminder Templates

## Overview

Save frequently used reminder settings as templates for quick creation. Useful for recurring content types.

## Implementation

### 1. Create ReminderTemplate Model

```dart
@Entity()
class ReminderTemplate {
  @Id()
  int id = 0;
  
  String name;
  String importance;  // day, week, month
  String? preferredCategory;
  String? preferredTimeOfDay;  // morning, afternoon, evening
  String? notes;
  
  @Property(type: PropertyType.date)
  DateTime createdAt;
  
  ReminderTemplate({
    this.id = 0,
    required this.name,
    required this.importance,
    this.preferredCategory,
    this.preferredTimeOfDay,
    this.notes,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();
}
```

### 2. Create TemplateRepository

```dart
class TemplateRepository {
  final Box<ReminderTemplate> _box;
  
  TemplateRepository(Store store) : _box = store.box<ReminderTemplate>();
  
  List<ReminderTemplate> getAll() => _box.getAll();
  
  int save(ReminderTemplate template) => _box.put(template);
  
  bool delete(int id) => _box.remove(id);
}
```

### 3. Create Template Selector Widget

```dart
class TemplateSelector extends StatelessWidget {
  final Function(ReminderTemplate?) onSelected;

  const TemplateSelector({super.key, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final templates = templateRepository.getAll();

    return PopupMenuButton<ReminderTemplate?>(
      icon: const Icon(Icons.bookmark_border),
      tooltip: t.useTemplate,
      onSelected: onSelected,
      itemBuilder: (context) => [
        PopupMenuItem(
          value: null,
          child: Text(t.noTemplate),
        ),
        const PopupMenuDivider(),
        ...templates.map((template) => PopupMenuItem(
          value: template,
          child: Row(
            children: [
              Icon(_getImportanceIcon(template.importance)),
              const SizedBox(width: 8),
              Expanded(child: Text(template.name)),
            ],
          ),
        )),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'manage',
          child: Row(
            children: [
              const Icon(Icons.settings),
              const SizedBox(width: 8),
              Text(t.manageTemplates),
            ],
          ),
        ),
      ],
    );
  }

  IconData _getImportanceIcon(String importance) {
    switch (importance) {
      case 'day': return Icons.priority_high;
      case 'week': return Icons.date_range;
      case 'month': return Icons.calendar_month;
      default: return Icons.bookmark;
    }
  }
}
```

### 4. Update SavePostSheet

```dart
class SavePostSheetState extends State<SavePostSheet> {
  ReminderTemplate? _selectedTemplate;
  
  void _applyTemplate(ReminderTemplate template) {
    setState(() {
      _selectedTemplate = template;
      _importance = template.importance;
      // Apply other template settings
    });
  }
  
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // URL input
        Row(
          children: [
            Expanded(child: _urlInput),
            TemplateSelector(onSelected: (template) {
              if (template != null) {
                _applyTemplate(template);
              }
            }),
          ],
        ),
        // Importance dropdown - pre-filled from template
        DropdownButtonFormField<String>(
          value: _importance,
          items: [
            DropdownMenuItem(value: 'day', child: Text(t.dayPriority)),
            DropdownMenuItem(value: 'week', child: Text(t.weekPriority)),
            DropdownMenuItem(value: 'month', child: Text(t.monthPriority)),
          ],
          onChanged: (value) => setState(() => _importance = value!),
        ),
      ],
    );
  }
}
```

### 5. Create Template Manager Screen

```dart
class TemplateManagerScreen extends StatelessWidget {
  const TemplateManagerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final templates = templateRepository.getAll();

    return Scaffold(
      appBar: AppBar(title: Text(Translations.of(context).templates)),
      body: templates.isEmpty
          ? EmptyState(
              icon: Icons.bookmark_border,
              title: t.noTemplates,
              subtitle: t.createTemplateHint,
            )
          : ListView.builder(
              itemCount: templates.length,
              itemBuilder: (context, index) {
                final template = templates[index];
                return ListTile(
                  title: Text(template.name),
                  subtitle: Text(template.importance),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete),
                    onPressed: () => templateRepository.delete(template.id),
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
}
```

## Testing Checklist

- [ ] Templates can be created
- [ ] Template selector shows all templates
- [ ] Selecting template applies settings
- [ ] Templates persist across restarts
- [ ] Templates can be deleted
