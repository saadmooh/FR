# Feature: Reading Time Estimate

## Overview

Uses AI to estimate how long it will take to read an article. Helps users plan their reading sessions.

## Implementation

### 1. Add Reading Time Fields

```dart
class Reminder {
  // ... existing fields ...
  int? estimatedReadTimeMinutes;
}
```

### 2. Update AIService

```dart
// In ai_service.dart

Future<int?> estimateReadTime(String content) async {
  try {
    final prompt = '''
Analyze the following content and estimate the reading time in minutes.
Consider the length, complexity, and density of the content.
Return only a number (no text).

Content preview: ${content.substring(0, min(1000, content.length))}
''';

    final response = await _generateContent(prompt);
    final minutes = int.tryParse(response.trim());
    return minutes;
  } catch (e) {
    return null;
  }
}
```

### 3. Create ReadTimeEstimate Widget

```dart
class ReadTimeEstimate extends StatelessWidget {
  final int minutes;

  const ReadTimeEstimate({super.key, required this.minutes});

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    
    String formattedTime;
    if (minutes < 1) {
      formattedTime = '< 1 min';
    } else if (minutes == 1) {
      formattedTime = '1 ${t.minute}';
    } else if (minutes < 60) {
      formattedTime = '$minutes ${t.minutes}';
    } else {
      final hours = minutes ~/ 60;
      final mins = minutes % 60;
      formattedTime = '${hours}h ${mins}m';
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.timer_outlined, size: 16, color: AppColors.textSecondary),
        const SizedBox(width: 4),
        Text(
          formattedTime,
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}
```

### 4. Display in Card

```dart
// In ModernReminderCard
Row(
  children: [
    // ... existing chips
    if (reminder.estimatedReadTimeMinutes != null)
      Padding(
        padding: const EdgeInsets.only(left: 8),
        child: ReadTimeEstimate(
          minutes: reminder.estimatedReadTimeMinutes!,
        ),
      ),
  ],
)
```

### 5. Add Translations

```dart
String get minute => 'min';
String get minutes => 'mins';
String get readingTime => 'Reading time';
```

## Testing Checklist

- [ ] Reading time estimate shows on cards
- [ ] Format correct for various durations
- [ ] Falls back gracefully on error
- [ ] Updates when content changes
