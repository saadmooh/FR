# Feature: Share Reminders

## Overview

Share reminder details or AI analysis with others via standard sharing mechanisms.

## Implementation

### 1. Create ShareService

```dart
import 'package:share_plus/share_plus.dart';

class ShareService {
  Future<void> shareReminder(Reminder reminder) async {
    final text = _buildShareText(reminder);
    await Share.share(text, subject: reminder.title);
  }

  String _buildShareText(Reminder reminder) {
    final buffer = StringBuffer();
    buffer.writeln(reminder.title);
    buffer.writeln();
    
    if (reminder.description != null) {
      buffer.writeln(reminder.description);
      buffer.writeln();
    }
    
    buffer.writeln('Category: ${reminder.categoryEn}');
    buffer.writeln('Complexity: ${reminder.complexityEn}');
    buffer.writeln();
    
    if (reminder.aiExplanation != null) {
      buffer.writeln('AI Analysis:');
      buffer.writeln(reminder.aiExplanation);
      buffer.writeln();
    }
    
    buffer.writeln('Link: ${reminder.url}');
    buffer.writeln();
    buffer.writeln('Shared via Flex Reminder');

    return buffer.toString();
  }

  Future<void> shareAnalysis(Reminder reminder) async {
    final text = '''
📊 AI Analysis: ${reminder.title}

Category: ${reminder.categoryEn}
Complexity: ${reminder.complexityEn}
Importance: ${reminder.importance}

${reminder.aiExplanation ?? ''}

${reminder.ethicalReasoning ?? ''}

Link: ${reminder.url}

Shared via Flex Reminder
''';

    await Share.share(text, subject: 'AI Analysis: ${reminder.title}');
  }
}
```

### 2. Add Share Button to PostDetailScreen

```dart
// In PostDetailScreen actions
IconButton(
  icon: const Icon(Icons.share),
  onPressed: () => shareService.shareReminder(reminder),
),

// For AI analysis share
PopupMenuButton(
  itemBuilder: (context) => [
    PopupMenuItem(
      value: 'share',
      child: Row(
        children: [
          const Icon(Icons.share),
          const SizedBox(width: 8),
          Text(Translations.of(context).share),
        ],
      ),
    ),
    PopupMenuItem(
      value: 'share_analysis',
      child: Row(
        children: [
          const Icon(Icons.analytics),
          const SizedBox(width: 8),
          Text(Translations.of(context).shareAnalysis),
        ],
      ),
    ),
  ],
  onSelected: (value) {
    switch (value) {
      case 'share':
        shareService.shareReminder(reminder);
        break;
      case 'share_analysis':
        shareService.shareAnalysis(reminder);
        break;
    }
  },
)
```

### 3. Add Translations

```dart
String get share => 'Share';
String get shareAnalysis => 'Share AI Analysis';
```

## Testing Checklist

- [ ] Share opens share sheet
- [ ] Text format correct
- [ ] URL included
- [ ] AI analysis share works
- [ ] Multiple share options work
