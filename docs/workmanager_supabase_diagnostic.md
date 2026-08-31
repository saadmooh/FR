# WorkManager + Supabase Rescheduling Diagnostic Analysis

**Date**: 2026-08-28  
**Project**: Flex Reminder (Flutter)  
**Analysis Method**: Code inspection (not guessing)

---

## 1. WorkManager Initialization ✅

| Check | Status | Evidence |
|-------|--------|----------|
| Called once in `main()` before `runApp()` | ✅ | `main.dart:231-237` |
| `callbackDispatcher` is top-level/static | ✅ | `workmanager_service.dart:570-572` |
| Marked `@pragma('vm:entry-point')` | ✅ | `workmanager_service.dart:570` |
| `isInDebugMode` enabled | ❌ | `main.dart:233` — not passed (defaults to `false`) |

**Fix**: Add `isInDebugMode: true` for testing:
```dart
await Workmanager().initialize(callbackDispatcher, isInDebugMode: true);
```

---

## 2. Task Registration ⚠️

| Check | Status | Evidence |
|-------|--------|----------|
| Uses `registerOneOffTask` (not periodic) | ✅ | `notification_service.dart:570` |
| `existingWorkPolicy` specified | ⚠️ | Not passed — defaults to `keep` for deferred tasks |
| Explicit `Constraints` (network, charging) | ❌ | None — relies on WorkManager defaults |
| Minimum interval respects Android 15-min | ❌ | `initialDelay` calculated dynamically (`reminder.scheduledAt - now + 1min`) — **can be < 15 min** |
| Registration success verified | ⚠️ | `try/catch` exists but doesn't return/verify success |

**Critical Issue**: Lines 565-569 (`notification_service.dart`) + 466-472 (`workmanager_service.dart`) compute `initialDelay` that may be **less than 15 minutes** — Android will reject or defer.

---

## 3. Supabase Initialization in Background Isolate ✅/❌

| Check | Status | Evidence |
|-------|--------|----------|
| `Supabase.initialize()` called in callback | ✅ | `workmanager_service.dart:68-71` (inside `_initBackgroundServices()`) |
| Uses same `--dart-define` env vars | ✅ | `AppConfig.supabaseUrl` / `supabaseAnonKey` |
| Firebase auth state loaded first | ✅ | Line 55: `await firebase_auth.FirebaseAuth.instance.authStateChanges().first` |
| Session restored from Firebase if expired | ✅ | Lines 81-116 |
| `WidgetsFlutterBinding.ensureInitialized()` called | ❌ | **Missing** — may break SharedPreferences/Platform channels in isolate |

**Fix**: Add at start of `_initBackgroundServices()`:
```dart
WidgetsFlutterBinding.ensureInitialized();
```

---

## 4. Rescheduling Logic Execution ✅/⚠️

| Check | Status | Evidence |
|-------|--------|----------|
| Returns `Future<bool>` correctly | ✅ | `executeTask` returns `Future<bool>` (lines 251-567) |
| No missing `await` causing early exit | ✅ | All async calls awaited |
| Comprehensive try/catch with logging | ✅ | Lines 281-566 with `_log()` → `SharedPreferences` |
| Errors persisted for UI retrieval | ✅ | Line 522: saves to `last_ai_reschedule_error` |
| Uses local notifications (not Snackbars) | ✅ | Lines 484-501 (success), 546-563 (failure) |

---

## 5. Permissions & System Constraints ✅/⚠️

| Permission / Constraint | Status | Evidence |
|------------------------|--------|----------|
| `INTERNET` in Manifest | ✅ | `AndroidManifest.xml:2` |
| `SCHEDULE_EXACT_ALARM` | ✅ | `AndroidManifest.xml:6` |
| `USE_EXACT_ALARM` | ✅ | `AndroidManifest.xml:7` |
| `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` | ✅ | `AndroidManifest.xml:8` |
| Foreground Service (Android 14+) | ✅ | `AndroidManifest.xml:11-12` |
| Runtime permission requests | ✅ | `notification_service.dart:119-130` |
| iOS `BGTaskScheduler` limitations | ⚠️ | Known — no immediate execution guarantee |
| Tested on real device (not emulator) | ❓ | Not verified in code |

---

## 6. Why No Snackbars in Background ✅

| Check | Status | Evidence |
|-------|--------|----------|
| Code tries to show Snackbar in callback | ❌ | **No** — correctly avoided |
| Uses `SharedPreferences` as bridge | ✅ | `_queueUiLog()` (lines 29-40) → `_showQueuedBgLogs()` (main.dart:51-62) |
| Shows queued logs when app opens | ✅ | `main.dart:222`, `main.dart:418` |
| WorkManager guarantees immediate execution | ❌ | **No** — system schedules at its discretion |

**Conclusion**: Snackbar absence is **expected architecture**, not a bug.

---

## 7. Actual Execution Verification ❓

| Verification Method | Done? | Notes |
|--------------------|-------|-------|
| `adb shell dumpsys jobscheduler` | ❌ | Not in code — must run manually |
| `adb logcat` for background isolate errors | ❌ | Errors **don't appear in Flutter Debug Console** |
| Conflict with `OverdueReminderService` | ⚠️ | Both reschedule same reminders (main.dart:267, 431) |

---

## Most Likely Failure Points (Priority Order)

1. **`initialDelay < 15 minutes`** — Android minimum for `OneOffTask` (lines 565-569, 466-472)
2. **Missing `WidgetsFlutterBinding.ensureInitialized()`** in background isolate — breaks SharedPreferences
3. **`isInDebugMode: false`** — hides WorkManager logs in debug builds
4. **ObjectBox lock conflict** — Lines 516-518 silently return `true` on "another store open", masking failures
5. **Race with `OverdueReminderService`** — Both fight to reschedule same reminders on app resume

---

## Recommended Next Steps

```bash
# 1. Enable debug mode in main.dart:233
isInDebugMode: true

# 2. Add binding init in workmanager_service.dart:_initBackgroundServices()
WidgetsFlutterBinding.ensureInitialized();

# 3. Guard initialDelay minimum 15 min
final nextDelay = max(reminder.scheduledAt.difference(DateTime.now()) + const Duration(minutes: 1), 
                      const Duration(minutes: 15));

# 4. Monitor via adb
adb logcat -s WorkManager:V flutter:V *:S

# 5. Verify scheduled jobs
adb shell dumpsys jobscheduler | grep -i flex
```