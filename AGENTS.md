# AGENTS.md - Agentic Coding Guidelines

This file provides guidelines for agentic coding agents operating in this Flutter repository.

## Project Overview
- **Project Name**: Flex Reminder
- **Type**: Flutter mobile application (Android-focused)
- **SDK**: Dart 3.9.0, Flutter
- **Architecture**: Clean Architecture with Repository pattern
- **Database**: ObjectBox for local persistence
- **State Management**: Provider-based (ValueNotifier, StatefulWidget)
- **Routing**: go_router for declarative navigation
- **AI Integration**: Google Generative AI for content analysis

## Build, Lint, and Test Commands

### Running Tests
```bash
flutter test                              # Run all tests
flutter test test/widget_test.dart        # Run single test file
flutter test test/unit/                   # Run tests in directory
flutter test --coverage                   # Run with coverage report
```

### Linting and Analysis
```bash
flutter analyze                           # Run static analysis
flutter fix --apply .                     # Auto-fix fixable issues
flutter format .                          # Format code with dart format
```

### Building
```bash
flutter build apk --debug                 # Build debug APK
flutter build apk --release               # Build release APK
flutter run -d chrome                     # Run web version
```

### Dependency Management
```bash
flutter pub get                           # Get/update dependencies
flutter pub add <package>                  # Add regular dependency
flutter pub add dev:<package>              # Add dev dependency
dart run build_runner build --delete-conflicting-outputs  # ObjectBox code gen
```

## Code Style Guidelines

### Naming Conventions
- **Classes/Models**: PascalCase (e.g., `ReminderRepository`, `Reminder`)
- **Methods/Variables**: camelCase (e.g., `getUnread()`, `isOpened`)
- **Private members**: Leading underscore (e.g., `_box`, `_repository`)
- **Files**: snake_case (e.g., `reminder_repository.dart`, `app_theme.dart`)
- **Constants**: camelCase for runtime constants, SCREAMING_SNAKE for compile-time

### Import Organization
Order imports by priority, separated by blank lines:
1. External packages (`package:flutter/...`, `package:objectbox/...`)
2. Internal packages (`package:google_fonts/...`, `package:go_router/...`)
3. Generated files (`objectbox.g.dart`)
4. Project imports (`core/`, `models/`, `repositories/`, `services/`)

```dart
import 'package:flutter/material.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'objectbox.g.dart';
import 'core/app_theme.dart';
import 'core/app_router.dart';
import 'models/reminder.dart';
import 'repositories/reminder_repository.dart';
import 'services/notification_service.dart';
```

### Formatting
- Use trailing commas for better formatting
- Use single quotes for strings
- Use `const` constructors where possible
- Prefer zero border radius (`BorderRadius.zero`) for sharp edges per design
- Use `super.key` in StatelessWidget/StatefulWidget constructors

```dart
const Padding(
  padding: EdgeInsets.all(16.0),
  child: Text('Hello'),
);

OutlineInputBorder(
  borderRadius: BorderRadius.zero,
  borderSide: const BorderSide(color: AppColors.accent),
),
```

### Types and Null Safety
- Prefer explicit types for public APIs
- Use nullable types (`?`) for optional values
- Use `late` for dependencies initialized in initState or constructor

```dart
final List<Reminder> reminders = [];
String? title;
late ReminderRepository _repository;
```

### Error Handling
- Use try-catch for async operations
- Add `mounted` checks before setState
- Handle platform exceptions gracefully

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

## Project Structure
```
lib/
├── core/                    # App-wide configurations
│   ├── app_router.dart     # go_router configuration
│   ├── app_theme.dart      # ThemeData, AppColors
│   ├── constants.dart       # App constants
│   ├── locale_manager.dart  # Localization management
│   └── translations.dart    # i18n strings
├── models/                 # Data models (ObjectBox entities)
│   ├── reminder.dart
│   ├── free_time_slot.dart
│   └── category_statistic.dart
├── repositories/           # Data access layer
├── services/               # Business logic (AI, notifications)
├── screens/                # Full-screen pages
├── widgets/                # Reusable UI components
├── objectbox.g.dart        # Generated ObjectBox code
└── main.dart               # Entry point
```

## ObjectBox Guidelines
When modifying models in `lib/models/`:
1. Update entity class with ObjectBox annotations
2. Use `@Id()`, `@Property(type: PropertyType.date)` for special fields
3. Run: `dart run build_runner build --delete-conflicting-outputs`
4. Generated `objectbox.g.dart` updates automatically

Repository pattern for ObjectBox:
```dart
class ReminderRepository {
  final Box<Reminder> _box;
  
  ReminderRepository(Store store) : _box = store.box<Reminder>();
  
  List<Reminder> getUnread() {
    final query = _box.query(Reminder_.isOpened.equals(false)).build();
    final results = query.find();
    query.close();  // Always close queries
    return results;
  }
}
```

## Services
- **NotificationService**: Singleton pattern via `NotificationService.instance`. Initialize with required repositories.
- **AIService**: Handles AI content classification using `google_generative_ai`.

## Theme
- Dark theme default with teal accent (`0xFF00D4C8`)
- Light theme also available (`buildWhiteTheme()`)
- Uses `google_fonts` for typography (Space Grotesk, DM Sans, JetBrains Mono)
- Sharp edges (no border radius) per design spec

## Error Recovery
1. `flutter clean`
2. `flutter pub get`
3. `flutter analyze`
4. `flutter fix --apply .`

## Testing
Tests use `flutter_test`. Mock repositories/services for unit tests:
```dart
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('app test', (WidgetTester tester) async {
    expect(true, isTrue);
  });
}
```

## Firebase Studio Context
- `.idx/dev.nix` defines development environment
- Preview server provides hot reload
- Monitor console for runtime errors
