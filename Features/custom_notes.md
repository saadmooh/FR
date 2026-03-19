# Feature: Custom Notes

## Overview

Allows users to add personal notes to saved reminders. Useful for context, context about why something was saved, or action items.

## Implementation

### 1. Update Reminder Model

```dart
class Reminder {
  // ... existing fields ...
  String? userNote;
  String? userNoteAr;
  String? userNoteFr;
}
```

### 2. Add UI in PostDetailScreen

```dart
// Add expandable notes section
ExpansionTile(
  title: Text(Translations.of(context).myNotes),
  trailing: IconButton(
    icon: const Icon(Icons.edit),
    onPressed: () => _showNoteEditor(),
  ),
  children: [
    Padding(
      padding: const EdgeInsets.all(16),
      child: Text(reminder.userNote ?? t.noNotes),
    ),
  ],
)
```

### 3. Create NoteEditor Widget

```dart
class NoteEditor extends StatefulWidget {
  final String? initialNote;
  final Function(String) onSave;

  const NoteEditor({super.key, this.initialNote, required this.onSave});

  @override
  State<NoteEditor> createState() => _NoteEditorState();
}

class _NoteEditorState extends State<NoteEditor> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialNote);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(Translations.of(context).editNote),
      content: TextField(
        controller: _controller,
        maxLines: 5,
        decoration: InputDecoration(
          hintText: Translations.of(context).noteHint,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(Translations.of(context).cancel),
        ),
        ElevatedButton(
          onPressed: () {
            widget.onSave(_controller.text);
            Navigator.pop(context);
          },
          child: Text(Translations.of(context).save),
        ),
      ],
    );
  }
}
```
