# Feature: Search Enhancements

## Overview

Advanced search functionality with full-text search, date range filtering, and saved searches.

## Implementation

### 1. Add Search Methods to Repository

```dart
// In reminder_repository.dart

List<Reminder> search(String query) {
  final lowerQuery = query.toLowerCase();
  final all = getAll();
  
  return all.where((r) {
    return r.title.toLowerCase().contains(lowerQuery) ||
           (r.description?.toLowerCase().contains(lowerQuery) ?? false) ||
           (r.aiExplanation?.toLowerCase().contains(lowerQuery) ?? false) ||
           r.url.toLowerCase().contains(lowerQuery);
  }).toList();
}

List<Reminder> getByDateRange(DateTime start, DateTime end) {
  final query = _box.query(
    Reminder_.scheduledAt.betweenDates(start, end)
  ).build();
  
  final results = query.find();
  query.close();
  return results;
}
```

### 2. Create Advanced Search Dialog

```dart
class AdvancedSearchDialog extends StatefulWidget {
  final Function(SearchFilters) onSearch;

  const AdvancedSearchDialog({super.key, required this.onSearch});

  @override
  State<AdvancedSearchDialog> createState() => _AdvancedSearchDialogState();
}

class _AdvancedSearchDialogState extends State<AdvancedSearchDialog> {
  String _query = '';
  DateTimeRange? _dateRange;
  List<String> _selectedCategories = [];
  List<String> _selectedComplexities = [];
  bool _unreadOnly = true;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(Translations.of(context).advancedSearch),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              decoration: InputDecoration(
                labelText: Translations.of(context).searchQuery,
                prefixIcon: const Icon(Icons.search),
              ),
              onChanged: (value) => _query = value,
            ),
            const SizedBox(height: 16),
            ListTile(
              title: Text(Translations.of(context).dateRange),
              subtitle: Text(_dateRange != null
                  ? '${_formatDate(_dateRange!.start)} - ${_formatDate(_dateRange!.end)}'
                  : Translations.of(context).anyDate),
              trailing: const Icon(Icons.calendar_today),
              onTap: _selectDateRange,
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              children: _buildCategoryChips(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(Translations.of(context).cancel),
        ),
        ElevatedButton(
          onPressed: () {
            widget.onSearch(SearchFilters(
              query: _query,
              dateRange: _dateRange,
              categories: _selectedCategories,
              complexities: _selectedComplexities,
              unreadOnly: _unreadOnly,
            ));
            Navigator.pop(context);
          },
          child: Text(Translations.of(context).search),
        ),
      ],
    );
  }
}
```

### 3. Create SearchFilters Model

```dart
class SearchFilters {
  final String query;
  final DateTimeRange? dateRange;
  final List<String> categories;
  final List<String> complexities;
  final bool unreadOnly;

  List<Reminder> apply(List<Reminder> reminders) {
    return reminders.where((r) {
      if (query.isNotEmpty && !_matchesQuery(r)) return false;
      if (dateRange != null && !_inDateRange(r)) return false;
      if (categories.isNotEmpty && !categories.contains(r.categoryEn)) return false;
      if (complexities.isNotEmpty && !complexities.contains(r.complexityEn)) return false;
      if (unreadOnly && r.isOpened) return false;
      return true;
    }).toList();
  }
}
```

## Testing Checklist

- [ ] Text search works across all fields
- [ ] Date range filters correctly
- [ ] Category filter works
- [ ] Complexity filter works
- [ ] Unread filter works
- [ ] Combined filters work
