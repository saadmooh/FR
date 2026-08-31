# Algorithmic Statistics Implementation Plan

## Goal
Replace AI-based statistics analysis in `StatisticsScreen` with on-device algorithmic computations that run in the background after each post rescheduling.

## Decisions Made
1. **Scope**: Fully replace AI analysis (remove `AIService.analyzeStats` and `analyzeCategoryStatistics` calls)
2. **Analyses**: All 6 types - peak activity, category patterns, trends, time-to-open, missed patterns, recommendations
3. **Computation**: Background service triggered after post rescheduling
4. **Storage**: Extend `CategoryStatistic` entity with new fields

## Implementation Steps

### 1. Extend CategoryStatistic Entity (`lib/models/category_statistic.dart`)
Add new fields for algorithmic results:
```dart
// Algorithmic analysis results
String? preferredTimesJson;           // JSON array of "HH:00-HH:59" strings
String? insightsJson;                 // JSON array of insight strings
double? algorithmicConfidenceScore;   // 0.0-1.0 confidence in analysis
String? peakActivityHoursJson;        // Global peak hours
String? peakActivityDaysJson;         // Global peak days
String? missedPatternsJson;           // Missed reminder patterns
String? recommendationsJson;          // Scheduling recommendations
@Property(type: PropertyType.date)
DateTime? lastAlgorithmicAnalysis;    // When analysis was last run
```

### 2. Create AlgorithmicAnalysisService (`lib/services/algorithmic_analysis_service.dart`)
New service with methods:
- `analyzeAllCategories(Box<CategoryStatistic>, Box<Reminder>)` - Main entry point
- `analyzeGlobalPatterns(List<Reminder>)` - Peak hours/days, trends
- `analyzeCategory(CategoryStatistic, List<Reminder>)` - Per-category analysis
- `computeTimeToOpenStats(List<Reminder>)` - Avg seconds to open by category/complexity
- `computeMissedPatterns(List<Reminder>)` - When reminders expire unread
- `generateRecommendations(CategoryStatistic, globalPatterns)` - Optimal scheduling times

**Algorithm Details:**
- **Peak Activity**: Frequency analysis on `openedAt.hour` and `weekday` across all opened reminders
- **Category Patterns**: Use existing `openedHoursJson`/`openedDaysJson` maps, find top 3 hours/days
- **Trends**: Compare open rates over rolling 7-day windows
- **Time-to-Open**: Group by category+complexity, compute median (not mean to resist outliers)
- **Missed Patterns**: Frequency on `scheduledAt.hour`/`weekday` for expired unread reminders
- **Recommendations**: Cross-reference peak activity with user's free time slots

### 3. Background Trigger Integration
Find where rescheduling happens (likely in `ReminderRepository` or a service) and call:
```dart
// After successful reschedule
await AlgorithmicAnalysisService.instance.analyzeAllCategories();
```

Consider using `Isolate` or `compute()` for heavy computation to avoid UI jank.

### 4. Update CategoryStatisticRepository
Add methods to save algorithmic results:
- `saveAlgorithmicAnalysis(CategoryStatistic stat, AlgorithmicResults results)`
- `getAlgorithmicAnalysis(int statId)` - Returns parsed results

### 5. Update StatisticsScreen (`lib/screens/statistics_screen.dart`)
- Remove `AIService` dependency and `_loadAIAnalysis`, `_analyzeCategory` methods
- Remove AI Insights card (lines 199-259)
- Replace category analysis button (line 391-398) with display of pre-computed algorithmic results
- Show `preferredTimesJson`, `insightsJson`, `algorithmicConfidenceScore` from `CategoryStatistic`
- Add "Last analyzed: {date}" indicator

### 6. Update main.dart / Dependency Injection
- Register `AlgorithmicAnalysisService` as singleton
- Remove `AIService` from `StatisticsScreen` constructor

### 7. Run Code Generation
```bash
dart run build_runner build --delete-conflicting-outputs
```

### 8. Migration Strategy
- Deploy entity changes first
- Existing `CategoryStatistic` records will have null algorithmic fields
- Background service populates them on next run
- UI handles null gracefully (shows "Not yet analyzed" or computes on-demand as fallback)

## Files to Modify
1. `lib/models/category_statistic.dart` - Add new fields
2. `lib/services/algorithmic_analysis_service.dart` - NEW FILE
3. `lib/repositories/category_statistic_repository.dart` - Add save/get methods
4. `lib/screens/statistics_screen.dart` - Remove AI, show algorithmic results
5. `lib/main.dart` - Update DI

## Validation
- Run `flutter analyze` and `flutter test`
- Test with sample data: create reminders across different hours/days, verify analysis correctness
- Verify background computation doesn't block UI
- Confirm null handling for un-analyzed categories

## Risks
- ObjectBox schema migration: new fields are nullable, so backward compatible
- Background computation timing: ensure it runs after reschedule completes
- Large dataset performance: use Isolate if processing >1000 reminders