# AGENTS.md - Agentic Coding Guidelines

This file provides guidelines for agentic coding agents operating in this Flutter repository.

## Project Overview
- **Project Name**: Flex Reminder
- **Type**: Flutter mobile application (Android-focused)
- **SDK**: Dart 3.9.0, Flutter
- **Architecture**: Clean Architecture with Repository pattern
- **Database**: ObjectBox for local persistence
- **State Management**: Provider-based (ValueNotifier, StatefulWidget)

## Build, Lint, and Test Commands

### Running Tests
```bash
flutter test                              # Run all tests
flutter test test/widget_test.dart        # Run single test file
flutter test --coverage                   # Run with coverage
```

### Linting and Analysis
```bash
flutter analyze                           # Run static analysis
flutter fix --apply .                     # Auto-fix issues
flutter format .                          # Format code
```

### Building
```bash
flutter build apk --debug                 # Build debug APK
flutter build apk --release               # Build release APK
```

### Dependency Management
```bash
flutter pub get                           # Get dependencies
flutter pub add <package>                 # Add dependency
dart run build_runner build --delete-conflicting-outputs  # ObjectBox code gen
```

## Code Style Guidelines

### Naming Conventions
- **Classes**: PascalCase (e.g., `ReminderRepository`)
- **Methods/Variables**: camelCase (e.g., `getUnread()`, `isOpened`)
- **Files**: snake_case (e.g., `reminder_repository.dart`)

### Imports
Group in order: external packages, internal packages, project imports.
```dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../models/reminder.dart';
import '../services/notification_service.dart';
import '../core/app_theme.dart';
```

### Formatting
- Use trailing commas for better formatting
- Use single quotes for strings
- Use const constructors where possible

```dart
const Padding(
  padding: EdgeInsets.all(16.0),
  child: Text('Hello'),
);
```

### Types and Null Safety
- Prefer explicit types for public APIs
- Use nullable types (? ) for optional values
```dart
final List<Reminder> reminders = [];
String? title;
late ReminderRepository _repository;
```

### Error Handling
- Use try-catch for async operations
- Add mounted checks before setState
```dart
Future<void> _loadData() async {
  try {
    final data = await service.fetchData();
    if (mounted) setState(() => _data = data);
  } catch (e) {
    if (mounted) _showError('Failed: $e');
  }
}
```

### Widget Best Practices
- Extract widgets for reusable components
- Use const constructors for static widgets
```dart
class ReminderCard extends StatelessWidget {
  const ReminderCard({super.key, required this.reminder});
  final Reminder reminder;
  
  @override
  Widget build(BuildContext context) {
    return Card(child: ListTile(title: Text(reminder.title)));
  }
}
```

### State Management
- Use ValueNotifier for simple state
- Use StatefulWidget for widget-specific state
- Pass dependencies through constructors
- Clean up listeners in dispose()

## Project Structure
```
lib/
├── core/           # App-wide configurations
│   ├── app_router.dart
│   ├── app_theme.dart
│   └── constants.dart
├── models/         # Data models (ObjectBox entities)
├── repositories/  # Data access layer
├── services/      # Business logic
├── screens/       # Full-screen pages
├── widgets/       # Reusable UI components
└── main.dart      # Entry point
```

## Important Notes

### ObjectBox Models
When modifying `lib/models/`:
1. Update entity class with ObjectBox annotations
2. Run: `dart run build_runner build --delete-conflicting-outputs`
3. Generated file `objectbox.g.dart` updates automatically

### Notifications
Use `flutter_local_notifications` with singleton pattern via `NotificationService.instance`. Initialize with required repositories before use.

### Theme
Dark theme with teal accent (0xFF00D4C8). Colors in `lib/core/app_theme.dart`.

### Error Recovery
1. Run `flutter clean`
2. Run `flutter pub get`
3. Run `flutter analyze`
4. Run `flutter fix --apply .`

## Firebase Studio Context
- `.idx/dev.nix` defines development environment
- Preview server provides hot reload
- Use `flutter run -d chrome` for web preview
- Monitor console for runtime errors

Follow guidelines in `GEMINI.md` for AI-assisted development.
