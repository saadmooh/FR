# Feature: Dark/Light Mode Toggle

## Overview

Provides an in-app theme toggle allowing users to switch between dark and light modes regardless of system settings. The preference is persisted across app restarts.

## User Experience

### Theme Toggle Locations
1. **Settings Screen** - Dedicated toggle switch
2. **Quick Settings** - Optional app bar icon in main screens

### Toggle UI
```
┌─────────────────────────────────────────┐
│ Theme                                   │
├─────────────────────────────────────────┤
│ ○ System Default                        │
│ ● Dark                                  │
│ ○ Light                                 │
└─────────────────────────────────────────┘
```

### Behavior
- **System Default**: Follows device settings
- **Dark**: Forces dark theme regardless of system
- **Light**: Forces light theme regardless of system
- Selection persists in SharedPreferences
- Instant theme change without app restart

## Implementation Guide

### 1. Add ThemeMode to AppSettings

Update `lib/core/constants.dart`:

```dart
class AppConstants {
  // ... existing constants ...
  static const String themeModeKey = 'theme_mode';
  static const String themeModeSystem = 'system';
  static const String themeModeDark = 'dark';
  static const String themeModeLight = 'light';
}
```

### 2. Update AppSettingsRepository

Update `lib/repositories/app_settings_repository.dart`:

```dart
class AppSettingsRepository {
  // ... existing code ...
  
  String getThemeMode() {
    return _prefs.getString(AppConstants.themeModeKey) 
        ?? AppConstants.themeModeSystem;
  }
  
  Future<void> setThemeMode(String mode) async {
    await _prefs.setString(AppConstants.themeModeKey, mode);
  }
  
  ThemeMode getThemeModeEnum() {
    final mode = getThemeMode();
    switch (mode) {
      case AppConstants.themeModeDark:
        return ThemeMode.dark;
      case AppConstants.themeModeLight:
        return ThemeMode.light;
      default:
        return ThemeMode.system;
    }
  }
}
```

### 3. Create ThemeProvider

Create `lib/services/theme_provider.dart`:

```dart
import 'package:flutter/material.dart';
import '../repositories/app_settings_repository.dart';
import '../core/constants.dart';

class ThemeProvider extends ChangeNotifier {
  final AppSettingsRepository _settings;
  
  ThemeProvider(this._settings);
  
  ThemeMode get themeMode => _settings.getThemeModeEnum();
  
  bool get isDarkMode => themeMode == ThemeMode.dark;
  bool get isLightMode => themeMode == ThemeMode.light;
  bool get isSystemMode => themeMode == ThemeMode.system;
  
  Future<void> setThemeMode(String mode) async {
    await _settings.setThemeMode(mode);
    notifyListeners();
  }
  
  String get currentModeString => _settings.getThemeMode();
}
```

### 4. Update Main.dart

Update `lib/main.dart`:

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // ... existing initialization ...
  
  // Initialize theme provider
  final themeProvider = ThemeProvider(settingsRepository);
  
  runApp(FlexReminderApp(
    initialSharedUrl: initialSharedUrl,
    themeProvider: themeProvider,
  ));
}

class FlexReminderApp extends StatelessWidget {
  final String? initialSharedUrl;
  final ThemeProvider themeProvider;
  
  const FlexReminderApp({
    super.key,
    this.initialSharedUrl,
    required this.themeProvider,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: themeProvider,
      builder: (context, _) {
        return MaterialApp.router(
          title: AppConstants.appName,
          debugShowCheckedModeBanner: false,
          theme: buildWhiteTheme(),           // Light theme
          darkTheme: buildTheme(),            // Dark theme
          themeMode: themeProvider.themeMode, // Dynamic mode
          routerConfig: appRouter.router,
          locale: LocaleManager.instance.currentAppLocale,
          supportedLocales: LocaleManager.supportedLocales,
        );
      },
    );
  }
}
```

### 5. Create ThemeToggleWidget

Create `lib/widgets/theme_toggle.dart`:

```dart
class ThemeToggle extends StatelessWidget {
  const ThemeToggle({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    final currentMode = themeProvider.currentModeString;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildOption(
          context,
          title: Translations.of(context).systemDefault,
          value: AppConstants.themeModeSystem,
          currentValue: currentMode,
          icon: Icons.brightness_auto,
          onChanged: (value) => themeProvider.setThemeMode(value),
        ),
        _buildOption(
          context,
          title: Translations.of(context).dark,
          value: AppConstants.themeModeDark,
          currentValue: currentMode,
          icon: Icons.dark_mode,
          onChanged: (value) => themeProvider.setThemeMode(value),
        ),
        _buildOption(
          context,
          title: Translations.of(context).light,
          value: AppConstants.themeModeLight,
          currentValue: currentMode,
          icon: Icons.light_mode,
          onChanged: (value) => themeProvider.setThemeMode(value),
        ),
      ],
    );
  }
  
  Widget _buildOption(
    BuildContext context, {
    required String title,
    required String value,
    required String currentValue,
    required IconData icon,
    required String Function(String) onChanged,
  }) {
    final isSelected = value == currentValue;
    
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      trailing: Radio<String>(
        value: value,
        groupValue: currentValue,
        onChanged: (v) => onChanged(v!),
      ),
      onTap: () => onChanged(value),
    );
  }
}
```

### 6. Add to Settings Screen

Update `lib/screens/settings_screen.dart`:

```dart
// In the settings form, add:
Card(
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          Translations.of(context).appearance,
          style: Theme.of(context).textTheme.titleMedium,
        ),
      ),
      const ThemeToggle(),
    ],
  ),
),
```

### 7. Add Optional Quick Toggle to AppBar

Update `lib/core/app_router.dart` - pass themeProvider to screens:

```dart
GoRoute(
  path: '/',
  builder: (context, state) => RemindersScreen(
    themeProvider: Provider.of<ThemeProvider>(context),
  ),
),
```

Or add to MainShell bottom nav:

```dart
// In main_shell.dart or wherever bottom nav is defined
BottomNavigationBar(
  items: [
    BottomNavigationBarItem(icon: Icon(Icons.bookmark), label: t.posts),
    BottomNavigationBarItem(icon: Icon(Icons.bar_chart), label: t.stats),
    BottomNavigationBarItem(icon: Icon(Icons.access_time), label: t.freeTime),
    BottomNavigationBarItem(icon: Icon(Icons.dark_mode), label: t.theme),
  ],
  onTap: (index) {
    if (index == 3) {
      _showThemeDialog(context);
    }
  },
)
```

### 8. Add Translations

```dart
// In translations
String get appearance => 'Appearance';
String get theme => 'Theme';
String get systemDefault => 'System Default';
String get dark => 'Dark';
String get light => 'Light';
```

## Database Changes

None required. Theme preference stored in SharedPreferences.

## Testing Checklist

- [ ] Theme toggle visible in settings
- [ ] Selecting dark applies dark theme immediately
- [ ] Selecting light applies light theme immediately
- [ ] Selecting system follows device setting
- [ ] Theme persists after app restart
- [ ] Both main app themes (dark/light) render correctly
- [ ] No flash of wrong theme on app start

## Edge Cases

1. **System → Dark while system is light**: Smooth transition
2. **Rapid toggle**: Debounce to prevent flicker
3. **App killed during toggle**: Persist before applying
4. **Widget tests**: Mock theme provider

## Performance Considerations

- Theme data is pre-built in `buildTheme()` and `buildWhiteTheme()`
- No rebuild of entire widget tree on theme change
- Use `const` constructors for theme values

## Related Features

- [App Theme](./app_theme.md) - Existing theme implementation
