# Feature: Reading Streaks

## Overview

Gamification feature that tracks consecutive days of reading saved posts. Motivates users to maintain daily reading habits with visual streak indicators and milestone celebrations.

## User Experience

### Streak Display
- Current streak count prominently displayed
- Longest streak record
- Streak fire icon animation
- Milestone celebrations (7, 14, 30, 100 days)

### UI Components

**Streak Card on Home:**
```
┌─────────────────────────────────────────┐
│ 🔥 12 Day Streak!                       │
│    Best: 28 days                        │
│    ████████████░░░░░░░░ 12/14          │
└─────────────────────────────────────────┘
```

**Milestone Celebration:**
- Confetti animation
- Achievement badge
- Share option

## Implementation Guide

### 1. Add Streak Fields to AppSettings

Update `lib/repositories/app_settings_repository.dart`:

```dart
class AppSettingsRepository {
  static const String streakCountKey = 'streak_count';
  static const String longestStreakKey = 'longest_streak';
  static const String lastOpenDateKey = 'last_open_date';
  static const String currentStreakStartKey = 'current_streak_start';

  int getStreakCount() => _prefs.getInt(streakCountKey) ?? 0;
  
  int getLongestStreak() => _prefs.getInt(longestStreakKey) ?? 0;
  
  String? getLastOpenDate() => _prefs.getString(lastOpenDateKey);
  
  DateTime? getCurrentStreakStart() {
    final dateStr = _prefs.getString(currentStreakStartKey);
    return dateStr != null ? DateTime.parse(dateStr) : null;
  }

  Future<void> updateStreak() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final lastOpen = getLastOpenDate();
    
    if (lastOpen == null) {
      // First time
      await _prefs.setInt(streakCountKey, 1);
      await _prefs.setString(lastOpenDateKey, today.toIso8601String());
      await _prefs.setString(currentStreakStartKey, today.toIso8601String());
      return;
    }
    
    final lastOpenDate = DateTime.parse(lastOpen);
    final daysDiff = today.difference(lastOpenDate).inDays;
    
    if (daysDiff == 0) {
      // Same day, no update needed
      return;
    } else if (daysDiff == 1) {
      // Consecutive day, increment streak
      final currentStreak = getStreakCount() + 1;
      await _prefs.setInt(streakCountKey, currentStreak);
      await _prefs.setInt(longestStreakKey, 
          max(getLongestStreak(), currentStreak));
      await _prefs.setString(lastOpenDateKey, today.toIso8601String());
    } else {
      // Streak broken, reset to 1
      await _prefs.setInt(streakCountKey, 1);
      await _prefs.setString(lastOpenDateKey, today.toIso8601String());
      await _prefs.setString(currentStreakStartKey, today.toIso8601String());
    }
  }
}
```

### 2. Create StreakService

Create `lib/services/streak_service.dart`:

```dart
class StreakService {
  final AppSettingsRepository _settings;

  StreakService(this._settings);

  int get currentStreak => _settings.getStreakCount();
  int get longestStreak => _settings.getLongestStreak();
  
  bool get isStreakActive {
    final lastOpen = _settings.getLastOpenDate();
    if (lastOpen == null) return false;
    
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final lastOpenDate = DateTime.parse(lastOpen);
    
    return today.difference(lastOpenDate).inDays <= 1;
  }
  
  bool get canIncreaseStreak {
    final lastOpen = _settings.getLastOpenDate();
    if (lastOpen == null) return true;
    
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final lastOpenDate = DateTime.parse(lastOpen);
    
    return today.difference(lastOpenDate).inDays == 0;
  }
  
  List<int> get milestones => [7, 14, 30, 60, 100, 180, 365];
  
  int? getNextMilestone() {
    final streak = currentStreak;
    for (final milestone in milestones) {
      if (streak < milestone) return milestone;
    }
    return null;
  }
  
  bool isMilestone(int days) => milestones.contains(days);
  
  double progressToNextMilestone() {
    final next = getNextMilestone();
    if (next == null) return 1.0;
    
    final prev = milestones.lastWhere((m) => m < currentStreak, orElse: () => 0);
    final range = next - prev;
    final progress = currentStreak - prev;
    
    return (progress / range).clamp(0.0, 1.0);
  }

  Future<void> recordOpen() async {
    await _settings.updateStreak();
  }
}
```

### 3. Create StreakCard Widget

Create `lib/widgets/streak_card.dart`:

```dart
class StreakCard extends StatelessWidget {
  final StreakService streakService;
  final VoidCallback? onTap;

  const StreakCard({
    super.key,
    required this.streakService,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final streak = streakService.currentStreak;
    final longest = streakService.longestStreak;
    final progress = streakService.progressToNextMilestone();
    final nextMilestone = streakService.getNextMilestone();

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: streak > 0
                ? [AppColors.accent, AppColors.accent.withOpacity(0.7)]
                : [AppColors.surface, AppColors.surfaceLight],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (streak > 0) ...[
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0.8, end: 1.0),
                    duration: const Duration(milliseconds: 500),
                    curve: Curves.easeInOut,
                    builder: (context, value, child) {
                      return Transform.scale(
                        scale: value,
                        child: const Text('🔥', style: TextStyle(fontSize: 32)),
                      );
                    },
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$streak ${streak == 1 ? t.day : t.days}',
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        t.streakActive,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.8),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Icon(Icons.emoji_events, 
                    color: Colors.amber[300], size: 16),
                const SizedBox(width: 4),
                Text(
                  '${t.best}: $longest ${t.days}',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.7),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            if (nextMilestone != null) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.zero,
                      child: LinearProgressIndicator(
                        value: progress,
                        backgroundColor: Colors.white.withOpacity(0.3),
                        valueColor: AlwaysStoppedAnimation(Colors.white),
                        minHeight: 8,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '$streak/$nextMilestone',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.8),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
```

### 4. Add Milestone Celebration

Create `lib/widgets/milestone_celebration.dart`:

```dart
class MilestoneCelebration extends StatefulWidget {
  final int milestone;

  const MilestoneCelebration({super.key, required this.milestone});

  @override
  State<MilestoneCelebration> createState() => _MilestoneCelebrationState();
}

class _MilestoneCelebrationState extends State<MilestoneCelebration>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    )..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.zero,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🏆', style: TextStyle(fontSize: 64)),
            const SizedBox(height: 16),
            Text(
              '${widget.milestone} Day Streak!',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppColors.accent,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              Translations.of(context).milestoneMessage(widget.milestone),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              child: Text(Translations.of(context).awesome),
            ),
          ],
        ),
      ),
    );
  }
}
```

### 5. Integrate with PostDetailScreen

Update `lib/screens/post_detail_screen.dart`:

```dart
// After marking reminder as opened
void _markAsOpened(Reminder reminder) async {
  final previousStreak = streakService.currentStreak;
  
  reminder.isOpened = true;
  reminder.openedAt = DateTime.now();
  reminderRepository.save(reminder);
  
  // Update streak
  if (streakService.canIncreaseStreak) {
    await streakService.recordOpen();
    
    // Check for milestone
    final newStreak = streakService.currentStreak;
    if (streakService.isMilestone(newStreak) && newStreak > previousStreak) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => MilestoneCelebration(milestone: newStreak),
        );
      }
    }
  }
}
```

### 6. Add to RemindersScreen

```dart
// In RemindersScreen, add streak card at top
class RemindersScreenState extends State<RemindersScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: StreakCard(streakService: streakService),
          ),
          // ... existing list
        ],
      ),
    );
  }
}
```

### 7. Add Translations

```dart
String get streak => 'Streak';
String get currentStreak => 'Current Streak';
String get longestStreak => 'Longest Streak';
String get day => 'day';
String get days => 'days';
String get best => 'Best';
String get streakActive => 'Keep it going!';
String get streakBroken => 'Start a new streak!';
String get milestoneMessage => 'You\'ve reached an amazing {days} day streak!';
String get awesome => 'Awesome!';
```

## Testing Checklist

- [ ] Streak increments on consecutive days
- [ ] Streak resets after gap day
- [ ] Longest streak updates correctly
- [ ] Progress bar shows correct percentage
- [ ] Milestone celebration shows at correct times
- [ ] Streak persists across app restarts
- [ ] Timezone changes handled correctly

## Edge Cases

1. **Open multiple posts same day**: Only increment once
2. **Midnight crossing**: Use local date consistently
3. **Timezone travel**: Detect date changes on app resume
4. **Very long streaks (1000+)**: Handle large numbers

## Performance Considerations

- Cache streak values, update only on open
- Use simple integer operations
- No heavy animations on streak card
