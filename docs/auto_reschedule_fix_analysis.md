# Auto-Rescheduling Not Working — Root Cause Analysis & Suggested Fixes

> Status: Analysis only — **no code changes applied**. Fixes below are proposals with ready-to-paste code.

---

## TL;DR

Automatic rescheduling never runs for a missed reminder in **either** state:

| Scenario | Result | Root cause |
|----------|--------|------------|
| App open (foreground) | Nothing happens | `reviewOverdueReminders()` runs only on app **start** and **resume** — no periodic check. WorkManager's background task cannot open the store (locked by the foreground isolate). |
| App closed | "Monitoring Failed" notification, no reschedule | The background AI chain (Firebase → Supabase → session → Play Integrity → Pro token) is fragile; any failure `rethrow`s out of the task and aborts it. The "+1h fallback" only covers **parse** failures, not **AI-call** failures. |

The manual button works because it runs in the app's own isolate with a live session and an available Activity/Integrity context.

---

## 1. How the mechanism is supposed to work

### 1.1 Foreground path — `OverdueReminderService`

`reviewOverdueReminders()` (`lib/services/overdue_reminder_service.dart:43`):

1. Fetches all unread reminders (`getAllUnread`, `isOpened == false`).
2. Filters those past `scheduledAt - 2min` grace (`isOverdue`, line 233).
3. Processes up to `batchLimit = 5` per cycle.
4. For each: checks max attempts → checks age (< 30 days) → acquires the atomic reschedule lock → calls `_aiService.reschedulePost(...)` → re-reads the reminder from DB (opened/abort guard) → saves new time → re-schedules the notification.

In `lib/main.dart` this service is invoked only at:
- App start: `main.dart:267`
- App resume: `main.dart:431` (via `_AppLifecycleObserver._runOverdueCheck`)

### 1.2 Background path — WorkManager

`NotificationService.scheduleReminder()` (`notification_service.dart:263`) schedules a one-off WorkManager task `reminder_monitoring_<id>` delayed by `scheduledAt - now + 1min`, clamped to a 15-minute minimum (`notification_service.dart:552`).

The background callback (`lib/services/workmanager_service.dart:245`) must, in a headless isolate:
1. `WidgetsFlutterBinding.ensureInitialized()`
2. Init Firebase + Supabase + restore the session (`_initBackgroundServices`, line 78)
3. Read the API key from secure storage
4. `initLocalTimeZone()`
5. Open the ObjectBox store (`_openStoreInBackground`, line 155)
6. Fetch the reminder, run the guard checks, acquire the race-guard lock
7. Call `aiService.reschedulePostRaw(...)` → `AiProxyService.sendPrompt` → Supabase edge function `ai-proxy` (needs integrity token + Pro session token)
8. Parse, clamp, save, re-schedule the notification + re-register the WorkManager task

### 1.3 Manual path — works

`post_detail_screen.dart::_reschedule` calls the same `reschedulePost(...)` **directly in the app isolate**, where Supabase session and integrity context are available.

---

## 2. Root causes

### 2.1 App open — no periodic foreground check

`reviewOverdueReminders()` is triggered **only** by start/resume. If the app stays in the foreground past the reminder time, no Dart code runs the check.

At the same time the WorkManager task fires (~`scheduledAt + 1min`), but the main isolate holds the ObjectBox store open, so `openStore()` in the background throws:

```
another store is still open
```

`_openStoreInBackground` retries 5× (30s apart), then the task catches it and returns `false` (`workmanager_service.dart:556`), letting WorkManager retry with backoff — forever, as long as the app stays up. **Result: the reminder stays overdue indefinitely.**

### 2.2 App closed — fragile AI chain aborts the whole task

The AI call in the background isolate depends on:

```dart
// workmanager_service.dart:374-390
String rawResponse;
try {
  rawResponse = await aiService.reschedulePostRaw(...);
} catch (e, stackTrace) {
  await _log('❌ [Reschedule] AI call failed: $e');
  debugPrint('📋 Stack: $stackTrace');
  store.close();
  rethrow; // <-- aborts the task, no reschedule happens
}
```

Any of these fails in a cold headless isolate and the whole task aborts:
- Firebase.initializeApp / auth restore timing out
- Supabase session expired and the Firebase fallback has no user token
- Play Integrity token request failing (no Activity / Play Services hiccup) → `strictIntegrityCheck` → `AiProxyException 403`
- Pro session token unavailable → `SUBSCRIPTION_REQUIRED`
- Network / 10-minute WorkManager budget

The documented fallback ("AI fails → +1 hour") only wraps the **response parsing** step (lines 395-406), never the AI **call** itself. So any AI-call failure = no reschedule + a "Monitoring Failed" notification.

### 2.3 Risk — deleting `lock.mdb` in the background store open

```dart
// workmanager_service.dart:155-187 (current)
Future<Store> _openStoreInBackground(String? directoryPath) async {
  ...
  if (await dir.exists()) {
    // Clean up stale lock file if app was force-killed
    final lockFile = File('$directoryPath/lock.mdb');
    if (await lockFile.exists()) {
      debugPrint('Found stale lock file, removing...');
      await lockFile.delete(); // <-- deletes the file BEFORE attempting openStore
    }
    return openStore(directory: directoryPath);
  }
  ...
}
```

If the app is alive, `lock.mdb` belongs to the main isolate's open store. Deleting it while in use does **not** release the OS-held lock, so the reopen still fails — and it risks a split-brain / corrupted store (a new process would lock a *new* inode while the old fd is still open). On process death Android already releases all file locks, so the delete is both unnecessary and harmful.

---

## 3. Suggested fixes (with code)

### Fix A — periodic foreground overdue check (solves “app open”)

Add a 2-minute `Timer.periodic` that calls `reviewOverdueReminders()` while the app is in the foreground. The check is cheap (in-process DB query; AI touched only for actually-overdue items).

#### Change 1 — `lib/main.dart` imports

```dart
// BEFORE
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kDebugMode;

// AFTER
import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kDebugMode;
```

#### Change 2 — root state becomes a lifecycle observer and owns the timer

```dart
// BEFORE (main.dart:327-331)
class _FlexReminderAppState extends State<FlexReminderApp> {
  @override
  void initState() {
    super.initState();

// AFTER
class _FlexReminderAppState extends State<FlexReminderApp>
    with WidgetsBindingObserver {
  Timer? _overdueCheckTimer;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);
    _startOverdueCheckTimer();
```

#### Change 3 — dispose + lifecycle handling + timer helpers

```dart
// BEFORE (main.dart:366-371)
  @override
  void dispose() {
    LocaleManager.instance.localeNotifier.removeListener(_onLocaleChanged);
    storeReopenSignal.removeListener(_onStoreReopened);
    super.dispose();
  }

// AFTER
  @override
  void dispose() {
    _stopOverdueCheckTimer();
    WidgetsBinding.instance.removeObserver(this);
    LocaleManager.instance.localeNotifier.removeListener(_onLocaleChanged);
    storeReopenSignal.removeListener(_onStoreReopened);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startOverdueCheckTimer();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _stopOverdueCheckTimer();
    }
  }

  void _startOverdueCheckTimer() {
    _overdueCheckTimer?.cancel();
    _overdueCheckTimer = Timer.periodic(
      const Duration(minutes: 2),
      (_) => _runForegroundOverdueCheck(),
    );
  }

  void _stopOverdueCheckTimer() {
    _overdueCheckTimer?.cancel();
    _overdueCheckTimer = null;
  }

  void _runForegroundOverdueCheck() {
    if (!_storeInitialized) return; // store closed → skip
    Future.microtask(() async {
      try {
        final rescheduledCount =
            await overdueReminderService.reviewOverdueReminders();
        if (rescheduledCount > 0) {
          debugPrint(
            '[OverdueCheck] Rescheduled $rescheduledCount overdue reminders (periodic)',
          );
        }
      } catch (e, stackTrace) {
        debugPrint('[OverdueCheck] Periodic overdue review failed: $e');
        debugPrint('Stack trace: $stackTrace');
      }
    });
  }
```

Why this is safe:
- `reviewOverdueReminders()` already guards against concurrent calls (`_isProcessing`, 5s throttle) (`overdue_reminder_service.dart:44-58`).
- The atomic ObjectBox `RescheduleLockService` (180s TTL) prevents the timer and the WorkManager task from double-rescheduling the same reminder.

Why 2 minutes: the overdue test already includes a 2-minute grace (`isOverdue`, `overdue_reminder_service.dart:233`), so a 2-min poll guarantees rescheduling within ~4 minutes of the missed time.

---

### Fix B — +1h fallback on AI-call failure (solves “app closed”)

Make the AI **call** failure fall back to a deterministic `+1 hour` (same as the existing parse fallback) instead of `rethrow`ing out of the task.

```dart
// BEFORE (workmanager_service.dart:374-406)
      String rawResponse;
      try {
        rawResponse = await aiService.reschedulePostRaw(
          previousAttemptsJson: jsonEncode(previousAttempts),
          category: reminder.categoryEn ?? 'Other',
          complexity: reminder.complexityEn ?? 'Medium',
          importance: reminder.importance,
          userFreeTimesJson: freeTimes.isNotEmpty
              ? '{"free_times": $freeTimes}'
              : null,
          currentTime: DateTime.now(),
        );
      } catch (e, stackTrace) {
        await _log('❌ [Reschedule] AI call failed: $e');
        debugPrint('📋 Stack: $stackTrace');
        store.close();
        rethrow;
      }

      await _log('📥 [Reschedule] Raw AI response: $rawResponse');

      Map<String, dynamic> aiResult;
      try {
        aiResult = AiRescheduleParser.parse(rawResponse);
      } catch (e) { /* ... +1h parse fallback ... */ }

      await _log('Parsed AI result: $aiResult');
```

```dart
// AFTER
      late Map<String, dynamic> aiResult;
      String? rawResponse;
      try {
        rawResponse = await aiService.reschedulePostRaw(
          previousAttemptsJson: jsonEncode(previousAttempts),
          category: reminder.categoryEn ?? 'Other',
          complexity: reminder.complexityEn ?? 'Medium',
          importance: reminder.importance,
          userFreeTimesJson: freeTimes.isNotEmpty
              ? '{"free_times": $freeTimes}'
              : null,
          currentTime: DateTime.now(),
        );
        await _log('📥 [Reschedule] Raw AI response: $rawResponse');
      } catch (e, stackTrace) {
        await _log('❌ [Reschedule] AI call failed: $e — falling back to +1 hour');
        debugPrint('📋 Stack: $stackTrace');
        aiResult = {
          'newTime': reminder.scheduledAt.add(const Duration(hours: 1)),
          'reason': 'AI call failed ($e), rescheduled by 1 hour',
        };
      }

      if (rawResponse != null) {
        try {
          aiResult = AiRescheduleParser.parse(rawResponse);
        } catch (e) {
          await _log('Failed to parse AI response: $e, using fallback');
          final newTime = reminder.scheduledAt.add(const Duration(hours: 1));
          aiResult = {
            'newTime': newTime,
            'reason': 'AI response parse failed, rescheduled by 1 hour',
          };
        }
        await _log('Parsed AI result: $aiResult');
      } else {
        await _log('Using fallback result after AI call failure');
      }
```

The flow continues exactly as before — the shared `reschedulingDeadline` / `clampRescheduleTime` policy (`lib/services/reschedule_policy.dart`) still guarantees the fallback lands strictly in the future and within the importance deadline.

---

### Fix C — stop deleting `lock.mdb` in the background open

```dart
// BEFORE (workmanager_service.dart:155-187)
      if (directoryPath != null && directoryPath.isNotEmpty) {
        final dir = Directory(directoryPath);
        if (await dir.exists()) {
          // Clean up stale lock file if app was force-killed
          final lockFile = File('$directoryPath/lock.mdb');
          if (await lockFile.exists()) {
            debugPrint('Found stale lock file, removing...');
            await lockFile.delete();
          }
          debugPrint('Opening store at: $directoryPath (attempt ${attempt + 1})');
          return openStore(directory: directoryPath);
        }
      }

// AFTER
      if (directoryPath != null && directoryPath.isNotEmpty) {
        final dir = Directory(directoryPath);
        if (await dir.exists()) {
          debugPrint('Opening store at: $directoryPath (attempt ${attempt + 1})');
          return openStore(directory: directoryPath);
        }
      }
```

Locks are released automatically when the process dies, so the stale-lock workaround is unnecessary, and removing it eliminates the corruption risk when the app is still alive.

---

### Fix D — same +1h fallback in the foreground service (optional, for consistency)

Only if you want the foreground path to keep moving reminders when the AI fails too:

```dart
// BEFORE (overdue_reminder_service.dart:158-165)
      final result = await _aiService.reschedulePost(
        previousAttemptsJson: jsonEncode(previousAttempts),
        category: reminder.categoryEn ?? 'Other',
        complexity: reminder.complexityEn ?? 'Medium',
        importance: reminder.importance,
        userFreeTimesJson: freeTimes.isNotEmpty ? '{"free_times": $freeTimes}' : null,
        currentTime: currentTime,
      );

// AFTER
      Map<String, dynamic> result;
      try {
        result = await _aiService.reschedulePost(
          previousAttemptsJson: jsonEncode(previousAttempts),
          category: reminder.categoryEn ?? 'Other',
          complexity: reminder.complexityEn ?? 'Medium',
          importance: reminder.importance,
          userFreeTimesJson: freeTimes.isNotEmpty ? '{"free_times": $freeTimes}' : null,
          currentTime: currentTime,
        );
      } catch (e, stackTrace) {
        debugPrint('[OverdueReminderService] AI call failed for reminder ${reminder.id}: $e — falling back to +1 hour');
        debugPrint('Stack trace: $stackTrace');
        result = {
          'newTime': reminder.scheduledAt.add(const Duration(hours: 1)),
          'reason': 'AI call failed ($e), rescheduled by 1 hour',
        };
      }
```

Same caveat as Fix B — `clampRescheduleTime` keeps the fallback in the valid window, and `maxReschedulesFor` bounds how many times a reminder can be bumped.

---

## 4. Concurrency notes (why running both paths is safe)

- `RescheduleLockService` uses an atomic ObjectBox write transaction (`Store.runInTransaction(TxMode.write, ...)`) with a 180s TTL and per-reminder keys, so the periodic foreground timer (Fix A) and the WorkManager task can never reschedule the same reminder at the same time.
- Both paths re-read the reminder from the DB after the AI call and abort if it was opened/deleted meanwhile (`overdue_reminder_service.dart:167-174`, `workmanager_service.dart:319`).
- WorkManager reschedules use `ExistingWorkPolicy.replace` with a per-reminder tag (`notification_service.dart:577-584`), so duplicate tasks are replaced, not stacked.

---

## 5. Verification

```bash
flutter analyze   # expect 0 errors
flutter test      # expect all pass (4 lock tests skip when ObjectBox native lib is absent in the host env)
```

On-device:
1. **App open**: save a reminder for ~2 minutes from now, keep the app in the foreground. Expect it to reschedule within ~4 minutes of the missed time (periodic check), and the notification to move to the new time.
2. **App closed**: save a reminder, swipe the app away from recents, leave the screen on. Expect the reminder to be rescheduled (AI or +1h fallback) and the new notification to appear.
3. Regression: background/resume still triggers the check; the manual reschedule button still works.

---

## Files touched (proposed)

- `lib/main.dart` — Fix A
- `lib/services/workmanager_service.dart` — Fixes B and C
- `lib/services/overdue_reminder_service.dart` — Fix D (optional)