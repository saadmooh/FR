# Feature: AI Summaries

## Overview

Uses AI to generate TL;DR summaries of article content when metadata is insufficient. Helps users decide if they want to read the full article.

## Implementation

### 1. Add Summary Field to Reminder

```dart
class Reminder {
  // ... existing fields ...
  String? aiSummary;
  String? aiSummaryAr;
  String? aiSummaryFr;
}
```

### 2. Create SummaryService

```dart
class SummaryService {
  final AIService _aiService;

  Future<String?> generateSummary(String url) async {
    try {
      final response = await _aiService.generateContent(
        'Summarize this article in 2-3 sentences: $url',
      );
      return response;
    } catch (e) {
      return null;
    }
  }
}
```

### 3. Add in SavePostSheet

```dart
// After fetching metadata, generate summary
final summary = await summaryService.generateSummary(url);
if (summary != null) {
  reminder.aiSummary = summary;
}
```

### 4. Display in PostDetailScreen

```dart
if (reminder.aiSummary != null) ...[
  Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.summarize, color: AppColors.accent),
              const SizedBox(width: 8),
              Text(
                Translations.of(context).summary,
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(reminder.aiSummary!),
        ],
      ),
    ),
  ),
],
```

## AI Prompt for Summaries

```
You are a helpful assistant. Read the following article and provide a 2-3 sentence summary that captures the main points and key takeaways.

Article URL: {url}

Provide your summary in the same language as the article content if possible.
```
