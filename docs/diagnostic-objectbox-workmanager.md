# Diagnostic Report: ObjectBox + WorkManager (Flex Reminder)

This file is designed to be passed to an AI CLI tool (e.g., Claude Code) for analyzing the actual codebase and answering each question based on real files, not guesses. The goal: build an accurate picture of the current architecture, then identify every location that needs modification to transition from the "close/reopen" pattern to the `Store.attach()` pattern.

---

## 0. Instructions for the Tool (AI CLI)

- Read every referenced file before answering; do not assume its content.
- For each question: mention the file name and line number(s) you relied on.
- If a contradiction exists between what is described here and what is actually in the code, state the difference explicitly.
- The final deliverable after answering all questions: a precise list of changes (file + line + required change) to transition to `Store.attach()`.

---

## 1. General Architecture Understanding

### Q1. Full file tree of `lib/services/`, `lib/repositories/`, and `lib/core/`

```
lib/services/
├── ai_proxy_service.dart
├── ai_reschedule_parser.dart
├── ai_service.dart
├── auth_service.dart
├── backup_service.dart
├── integrity_service.dart
├── local_timezone.dart
├── metadata_service.dart
├── notification_scheduler.dart
├── notification_service.dart
├── overdue_reminder_service.dart
├── reschedule_lock_service.dart
├── reschedule_policy.dart
├── revenuecat_service.dart
├── session_token_service.dart
├── workmanager_service.dart
└── youtube_service.dart

lib/repositories/
├── app_settings_repository.dart
├── category_statistic_repository.dart
├── free_time_repository.dart
├── playlist_repository.dart
└── reminder_repository.dart

lib/core/
├── api_credential_store.dart
├── app_config.dart
├── app_router.dart
├── app_theme.dart
├── app_translations.dart
├── constants.dart
├── integrity_snackbar.dart
├── locale_manager.dart
├── store_busy_guard.dart
├── translations.dart
└── ui_messenger.dart
```

### Q2. Actual ObjectBox versions

**`pubspec.yaml` (lines 37-38):**
```yaml
objectbox: ^5.2.0
objectbox_flutter_libs: ^5.2.0
```

**`pubspec.lock` (lines 795-810):**
```
objectbox: 5.3.2
objectbox_flutter_libs: 5.3.2
objectbox_generator: 5.3.2
```

The resolved version is 5.3.2, which satisfies the declared minimum `^5.2.0`.

### Q3. Is `Store.attach()` available in the installed version?

**Yes.** `Store.attach()` is defined in the ObjectBox 5.3.2 native library:

- **File:** `/home/user/.pub-cache/hosted/pub.dev/objectbox-5.3.2/lib/src/native/store.dart`
- **Line:** 414
- **Signature:**

```dart
Store.attach(ModelDefinition modelDefinition, String? directoryPath,
    {bool queriesCaseSensitiveDefault = true})
```

Documentation from the source (lines 403-413):
> "Use this to access an open store from other isolates. This results in each isolate having access to the same underlying native store. The returned store is a new instance with its own lifetime and must also be closed. The actual underlying store is only closed when the last store instance is closed."

### Q4. All locations calling `openStore()` explicitly

| # | File | Line | Context |
|---|------|------|---------|
| 1 | `lib/main.dart` | 176 | `tempStore = await openStore();` — initial app startup |
| 2 | `lib/main.dart` | 442 | `store = await openStore();` — reopen on app resume |
| 3 | `lib/services/workmanager_service.dart` | 165 | `return openStore(directory: directoryPath);` — background task, with directory |
| 4 | `lib/services/workmanager_service.dart` | 169 | `return openStore();` — background task, default directory |

### Q5. All locations calling `Store.fromReference()`

**None found.** `Store.fromReference()` is not used anywhere in the codebase.

### Q6. Any other locations opening/closing the Store

Beyond the 4 `openStore()` calls, the following `store.close()` calls exist:

| File | Line | Context |
|------|------|---------|
| `lib/main.dart` | 427 | `store.close();` — in `_closeMainStoreForBackground()` |
| `lib/services/workmanager_service.dart` | 309 | `store.close();` — reminder not found |
| `lib/services/workmanager_service.dart` | 315 | `store.close();` — reminder already opened |
| `lib/services/workmanager_service.dart` | 322 | `store.close();` — max reschedules reached |
| `lib/services/workmanager_service.dart` | 329 | `store.close();` — reminder too old |
| `lib/services/workmanager_service.dart` | 363 | `store.close();` — lock acquisition failed |
| `lib/services/workmanager_service.dart` | 412 | `store.close();` — AI returned null time |
| `lib/services/workmanager_service.dart` | 456 | `store.close();` — new time already passed |
| `lib/services/workmanager_service.dart` | 535 | `store.close();` — success path |
| `lib/services/workmanager_service.dart` | 544 | `store?.close();` — error/catch path |

No test files, no other isolates, no `background_fetch` for iOS open or close the Store.

---

## 2. Store Lifecycle in the Main Isolate

### Q7. `_closeMainStoreForBackground()` and `_reopenMainStoreIfNeeded()` (main.dart lines 415-491)

**`_closeMainStoreForBackground()` (lines 415-433):**

```dart
Future<void> _closeMainStoreForBackground() async {
  if (!_storeInitialized) return;
  const maxBusyAttempts = 5;
  for (int attempt = 0; attempt < maxBusyAttempts; attempt++) {
    if (!StoreBusyGuard.isBusy) break;
    debugPrint(
      '[Lifecycle] Store busy, deferring close (attempt ${attempt + 1}/$maxBusyAttempts)...',
    );
    await Future.delayed(const Duration(milliseconds: 500));
    if (!_storeInitialized) return;
  }
  try {
    store.close();
    _storeInitialized = false;
    debugPrint('Store closed on app background');
  } catch (e) {
    debugPrint('Failed to close store on background: $e');
  }
}
```

**`_reopenMainStoreIfNeeded()` (lines 435-491):**

```dart
Future<void> _reopenMainStoreIfNeeded() async {
  if (_storeInitialized) return;
  const maxRetries = 3;
  const retryDelay = Duration(seconds: 1);

  for (int attempt = 0; attempt < maxRetries; attempt++) {
    try {
      store = await openStore();
      _storeInitialized = true;

      reminderRepository = ReminderRepository(store);
      freeTimeRepository = FreeTimeRepository(store);
      categoryStatRepository = CategoryStatisticRepository(store);
      settingsRepository.setRepositories(
        reminderRepository,
        freeTimeRepository,
      );

      notificationService.setReminderRepository(reminderRepository);
      notificationService.setCategoryStatRepository(categoryStatRepository);
      notificationService.setFreeTimeRepository(freeTimeRepository);

      overdueReminderService = OverdueReminderService(
        reminderRepository: reminderRepository,
        freeTimeRepository: freeTimeRepository,
        aiService: aiService,
        notificationService: notificationService,
        lockService: RescheduleLockService(store),
      );

      appRouter = AppRouter(
        reminderRepository: reminderRepository,
        freeTimeRepository: freeTimeRepository,
        categoryStatRepository: categoryStatRepository,
        notificationService: notificationService,
        aiService: aiService,
        settingsRepository: settingsRepository,
        pendingSharedUrl: pendingSharedUrl,
        aiRescheduleError: aiRescheduleError,
        authService: authService,
        revenueCatService: revenueCatService,
      );
      notificationService.setRouter(appRouter.router);

      storeReopenSignal.value++;
      debugPrint('Store reopened on app resume');
      return;
    } catch (e) {
      if (attempt < maxRetries - 1) {
        debugPrint('Store reopen attempt ${attempt + 1} failed, retrying...');
        await Future.delayed(retryDelay);
      } else {
        rethrow;
      }
    }
  }
}
```

### Q8. Where are these two functions called from?

Both are called from `WidgetsBindingObserver.didChangeAppLifecycleState`:

**`lib/main.dart` lines 397-412:**

```dart
@override
void didChangeAppLifecycleState(AppLifecycleState state) async {
  switch (state) {
    case AppLifecycleState.paused:
    case AppLifecycleState.detached:
      await _closeMainStoreForBackground();    // line 401
      break;
    case AppLifecycleState.resumed:
      await _reopenMainStoreIfNeeded();        // line 403
      await _runOverdueCheck();
      final prefs = await SharedPreferences.getInstance();
      await _showQueuedBgLogs(prefs);
      flushPendingUiLogs();
      break;
    default:
      break;
  }
}
```

These are the **only** call sites. No other code invokes these methods.

### Q9. Is there any read/write on the Store that could happen after `_closeMainStoreForBackground()` and before confirming successful close?

**Yes, there is a race window.** The sequence is:

1. `StoreBusyGuard.isBusy` is checked in a loop (up to 5 × 500ms = 2.5s max).
2. Once `isBusy` is false (no active `beginWrite`), `store.close()` is called immediately.
3. Read operations (`getById()`, `getAll()`, `getUnread()`, etc.) do NOT go through `StoreBusyGuard`. Only `save()` and `delete()` in the repositories are guarded.
4. Between the last `endWrite()` and `store.close()`, any ongoing read operation could still be in flight.

Any `Stream` listener, `Timer`, or widget rebuild that reads from a Box after the busy check passes but before `store.close()` completes could encounter a closed-store error.

### Q10. Are Boxes rebuilt after `_reopenMainStoreIfNeeded()`, or are old Box references reused?

**Boxes ARE properly rebuilt.** In `_reopenMainStoreIfNeeded()` (lines 444-463):

```dart
reminderRepository = ReminderRepository(store);    // new Box from new Store
freeTimeRepository = FreeTimeRepository(store);    // new Box from new Store
categoryStatRepository = CategoryStatisticRepository(store);  // new Box from new Store
// ... and so on for all services
```

Every repository and service receives the new `store` instance, so new `Box` objects are created. Old Box references from before the close are replaced.

If any widget or listener captured a reference to the old `reminderRepository` before the reopen, it would still point to the old (closed) store's Box. The `storeReopenSignal` (line 479) triggers a full `setState` rebuild to mitigate this.

---

## 3. Store Lifecycle in the WorkManager Isolate

### Q11. `_openStoreInBackground()` (workmanager_service.dart lines 155-181)

```dart
Future<Store> _openStoreInBackground(String? directoryPath) async {
  const maxRetries = 5;
  const retryDelay = Duration(seconds: 30);

  for (int attempt = 0; attempt < maxRetries; attempt++) {
    try {
      if (directoryPath != null && directoryPath.isNotEmpty) {
        final dir = Directory(directoryPath);
        if (await dir.exists()) {
          debugPrint('Opening store at: $directoryPath (attempt ${attempt + 1})');
          return openStore(directory: directoryPath);
        }
      }
      debugPrint('Opening store with default directory (attempt ${attempt + 1})');
      return openStore();
    } catch (e) {
      if (e.toString().contains('another store is still open') && attempt < maxRetries - 1) {
        debugPrint('Store locked, waiting for release... (attempt ${attempt + 1}/$maxRetries)');
        await Future.delayed(retryDelay);
      } else {
        debugPrint('Failed to open store: $e');
        rethrow;
      }
    }
  }
  throw Exception('Failed to open store after $maxRetries attempts');
}
```

### Q12. Store initialization inside the WorkManager callback (lines 275-300)

```dart
Store? store;
RescheduleLockService? lockService;
try {
  await _log('Initializing background services...');
  await _initBackgroundServices();

  await _log('Initializing timezone...');
  await initLocalTimeZone();

  if (apiKey == null || apiKey.isEmpty) {
    await _log('No API key available in WorkManager task');
    return true;
  }

  await _log('Creating AI service...');
  final aiService = await _createAIService(
    apiKey: apiKey,
    provider: provider,
    model: model,
  );

  await _log('Initializing notifications...');
  await _initNotificationsInBackground();

  await _log('Opening store...');
  store = await _openStoreInBackground(storeDirectoryPath);
```

### Q13. How is `storeDirectory` passed from `NotificationService` to WorkManager via `inputData`?

**Sending side** — `lib/services/notification_service.dart` lines 560-592:

```dart
Future<void> _scheduleMonitoringWorkManager(Reminder reminder) async {
  if (!Platform.isAndroid && !Platform.isIOS) return;
  try {
    await Workmanager().cancelByTag('reminder_${reminder.id}');
    final inputData = <String, String>{
      'reminderId': reminder.id.toString(),
      'provider': _provider,
    };
    if (_storeDirectoryPath != null) {
      inputData['storeDirectory'] = _storeDirectoryPath!;   // line 569
    }
    if (_model.isNotEmpty) {
      inputData['model'] = _model;
    }
    // ...
    await Workmanager().registerOneOffTask(
      'reminder_monitoring_${reminder.id}',
      _monitoringTaskName,
      initialDelay: monitoringDelay,
      inputData: inputData,
      tag: 'reminder_${reminder.id}',
      existingWorkPolicy: ExistingWorkPolicy.replace,
    );
  } catch (e) {
    debugPrint('Failed to schedule monitoring WorkManager: $e');
  }
}
```

**Receiving side** — `lib/services/workmanager_service.dart` line 266:

```dart
final storeDirectoryPath = inputData?['storeDirectory'] as String?;
```

**Origin of the path** — `lib/main.dart` lines 246-247:

```dart
final storeDir = await defaultStoreDirectory();
notificationService.setStoreDirectoryPath(storeDir.path);
```

The path flows: `main.dart` → `NotificationService._storeDirectoryPath` → WorkManager `inputData` → `_openStoreInBackground()`.

`NotificationService._storeDirectoryPath` is a nullable `String?` field (line 542), set once via `setStoreDirectoryPath()` (line 546).

### Q14. Is the Store closed at the end of a WorkManager task?

**Yes.** The Store is closed in every exit path:

| Path | Line | Code |
|------|------|------|
| Reminder not found | 309 | `store.close();` |
| Reminder already opened | 315 | `store.close();` |
| Max reschedules reached | 322 | `store.close();` |
| Reminder too old | 329 | `store.close();` |
| Lock acquisition failed | 363 | `store.close();` |
| AI returned null time | 412 | `store.close();` |
| New time already passed | 456 | `store.close();` |
| Success (after notification) | 535 | `store.close();` |
| Error/catch block | 544 | `store?.close();` |

### Q15. Retry logic (30s × 5 attempts) — is it within `executeTask` or via WorkManager rescheduling?

**It is within the same `executeTask` call.** The retry loop in `_openStoreInBackground()` (lines 159-179) uses `Future.delayed(Duration(seconds: 30))` between attempts, all within a single invocation of the WorkManager callback.

Maximum time: 5 attempts × 30s delay = 150s ≈ 2.5 minutes. WorkManager on Android has a default timeout of 10 minutes for `executeTask`, so this is within limits.

There is NO explicit rescheduling on failure — the function throws, and the error handler (lines 539-607) catches it. WorkManager may automatically retry based on its own policies, but the code does not explicitly reschedule on store-open failure.

### Q16. Is `android:process` configured in `AndroidManifest.xml`?

**No.** The `AndroidManifest.xml` (`android/app/src/main/AndroidManifest.xml`) does NOT contain any `android:process` attribute on any `<service>`, `<receiver>`, or `<application>` tag.

WorkManager runs in the **same process** as the main Flutter app on modern Android (API 26+), which is the default when no `android:process` is specified.

---

## 4. StoreBusyGuard

### Q17. Full `lib/core/store_busy_guard.dart` code

```dart
/// Tracks whether an ObjectBox write operation is currently in flight on the
/// main isolate. Used by the app lifecycle to defer closing the main store
/// (on background) while a save/write is still running, instead of force
/// closing it in the middle of a transaction.
class StoreBusyGuard {
  static int _activeWrites = 0;

  static bool get isBusy => _activeWrites > 0;

  static void beginWrite() {
    _activeWrites++;
  }

  static void endWrite() {
    if (_activeWrites > 0) {
      _activeWrites--;
    }
  }
}
```

(19 lines total)

### Q18. Every location in `lib/repositories/*` using `StoreBusyGuard.beginWrite()` and `endWrite()`

| Repository | Method | beginWrite Line | endWrite Line | try/finally? |
|------------|--------|----------------|---------------|--------------|
| `reminder_repository.dart` | `save()` | 11 | 15 | Yes |
| `reminder_repository.dart` | `delete()` | 56 | 60 | Yes |
| `free_time_repository.dart` | `save()` | 11 | 15 | Yes |
| `free_time_repository.dart` | `delete()` | 35 | 39 | Yes |
| `category_statistic_repository.dart` | `save()` | 31 | 35 | Yes |
| `category_statistic_repository.dart` | `delete()` | 139 | 143 | Yes |

All 6 usages use `try/finally` correctly. Every `beginWrite()` has a corresponding `endWrite()` in the `finally` block.

### Q19. Is there any write operation that bypasses `StoreBusyGuard`?

**Yes.** The following write operations do NOT go through `StoreBusyGuard`:

1. **`RescheduleLockService`** — `lib/services/reschedule_lock_service.dart`:
   - `acquireLock()` (line 21): Uses `_store.runInTransaction(TxMode.write, ...)` — no `StoreBusyGuard`
   - `releaseLock()` (line 42): Uses `_store.runInTransaction(TxMode.write, ...)` — no `StoreBusyGuard`
   - `cleanupExpiredLocks()` (line 65): Uses `_store.runInTransaction(TxMode.write, ...)` — no `StoreBusyGuard`

2. **`workmanager_service.dart`** — Direct `_box.put(reminder)` at line 435 (inside WorkManager isolate, which doesn't use `StoreBusyGuard` since it's a different isolate).

3. **`CategoryStatisticRepository.recordSaved()`, `recordOpened()`, `recordNotOpened()`** — These call `save()` which IS guarded, but they also call `findByCategoryAndComplexity()` which does reads (reads are not guarded, but don't need guarding).

### Q20. Maximum wait time when `isBusy == true` during close attempt

In `_closeMainStoreForBackground()` (lines 417-425):

```dart
const maxBusyAttempts = 5;
for (int attempt = 0; attempt < maxBusyAttempts; attempt++) {
  if (!StoreBusyGuard.isBusy) break;
  await Future.delayed(const Duration(milliseconds: 500));
  if (!_storeInitialized) return;
}
```

**Maximum wait = 5 × 500ms = 2500ms = 2.5 seconds.**

---

## 5. Actual Failure Scenario Trace

### Q21. Step-by-step trace of the failure

**Scenario:** App is in foreground (Store open), a notification triggers a WorkManager task, WorkManager tries to open a new Store.

**Step 1:** App is in foreground. `store` global variable holds an open `Store` instance. `_storeInitialized = true`.

**Step 2:** A notification fires. `NotificationService._scheduleMonitoringWorkManager()` (`notification_service.dart:560`) schedules a WorkManager one-off task with `initialDelay`.

**Step 3:** WorkManager executes `callbackDispatcher()` (`workmanager_service.dart:231`), which calls `_workmanagerCallback()` (line 240).

**Step 4:** Inside the callback, `_openStoreInBackground(storeDirectoryPath)` is called (line 300).

**Step 5:** `_openStoreInBackground()` calls `openStore(directory: directoryPath)` (line 165) or `openStore()` (line 169).

**Step 6:** `openStore()` (`objectbox.g.dart:462`) calls `obx.Store(getObjectBoxModel(), directory: ...)` (line 472).

**Step 7:** The ObjectBox native library detects that the store directory is already locked by another Store instance (the one in the main isolate). It throws an exception with the message: `"another store is still open"`.

**Step 8:** The catch block in `_openStoreInBackground()` (line 171) catches this:
```dart
if (e.toString().contains('another store is still open') && attempt < maxRetries - 1) {
  await Future.delayed(retryDelay);  // waits 30 seconds
}
```

**Step 9:** After 5 failed attempts (or if the error is not retryable), the function throws. The outer catch block in `_workmanagerCallback()` (line 539) catches it.

**Step 10:** The error handler (lines 556-558) detects the store-lock error:
```dart
if (e.toString().contains('another store is still open')) {
  await _log('App is in foreground, store locked — task failed, will retry');
  return false;  // tells WorkManager the task failed
}
```

**Step 11:** WorkManager receives `false` (task failed). On Android, WorkManager may retry the task based on its internal backoff policy. The next retry will face the same problem if the app is still in the foreground.

**Source of the exception:** The `"another store is still open"` error originates from the **ObjectBox C library** (the native layer), not from application code. It is triggered when a second `openStore()` call attempts to access a store directory that is already locked by an active `Store` instance.

### Q22. Is there logging/monitoring to confirm this scenario in production?

**Yes.** There is a comprehensive remote logging system:

1. **`_remoteLog()` function** (`workmanager_service.dart:55-76`): Logs to Supabase `debug_logs` table
2. **Specific log events:**
   - `workmanager_task_started` (line 245) — logged when task begins
   - `workmanager_task_success` (line 537) — logged on success
   - `workmanager_task_error` (line 542) — logged on any error
3. **Local UI logging** via `_log()` (line 48-51) and `_queueUiLog()` (line 34-45) — queued to SharedPreferences and shown as SnackBars on next app open
4. **Specific store-lock detection** (line 557): `await _log('App is in foreground, store locked — task failed, will retry');`

Query the `debug_logs` Supabase table for `workmanager_task_error` events where the error message contains "another store is still open" to confirm this scenario.

### Q23. What happens to `RescheduleLock` when the task fails?

**Analysis of the failure path (`workmanager_service.dart` lines 539-607):**

```dart
} catch (e, stackTrace) {
  await _log('WorkManager monitoring callback failed: $e');
  try {
    store?.close();
  } catch (_) {}
  // Release race guard lock on error (via ObjectBox if store is open)
  if (store != null && lockService != null) {
    try {
      lockService.releaseLock(reminderId);
    } catch (_) {}
  }
  if (e.toString().contains('another store is still open')) {
    return false;
  }
  // ...
}
```

When the store-open fails (line 300 throws), `store` is still `null` (the assignment never completed). Therefore:
- `store?.close()` does nothing (store is null)
- `lockService` is also `null` (it was declared on line 276 but only assigned on line 360, AFTER the store is opened)

When the task fails due to "another store is still open", the `RescheduleLock` is **NOT released** by the WorkManager task. The lock was never acquired in the first place (acquisition happens at line 361, which was never reached).

The lock's TTL (180 seconds / 3 minutes, from `reschedule_lock_service.dart:20`) ensures it expires automatically if a lock were ever orphaned.

---

## 6. Verification of Proposed Solution (`Store.attach()`)

### Q24. Are all Entities defined in the same `objectbox.g.dart`?

**Yes.** All 5 entities are defined in a single `lib/objectbox.g.dart`:

| Entity | IdUid | Line |
|--------|-------|------|
| `FreeTimeSlot` | (1, ...) | 26 |
| `Reminder` | (2, ...) | 60 |
| `CategoryStatistic` | (3, ...) | 256 |
| `Playlist` | (4, ...) | 338 |
| `RescheduleLock` | (5, ...) | 420 |

The `getObjectBoxModel()` function is defined at line 486. It is accessible from both `main.dart` and `workmanager_service.dart` via the import `import '../objectbox.g.dart';`.

### Q25. Is `callbackDispatcher` a top-level or static function?

**Yes, it is a top-level function** (`workmanager_service.dart:230-237`):

```dart
@pragma('vm:entry-point')
void callbackDispatcher() {
  WidgetsFlutterBinding.ensureInitialized();
  _workmanagerCallback();
}
```

It has the `@pragma('vm:entry-point')` annotation, is a top-level function (not inside any class), and has no parameters.

### Q26. Does replacing `openStore()` with `Store.attach()` cause any conflicts?

**Analysis of all code that depends on the return value of `openStore()`:**

1. **`main.dart` line 176:** `tempStore = await openStore();` — assigns to `tempStore`, then to `store`.
2. **`main.dart` line 442:** `store = await openStore();` — assigns directly to `store`.
3. **`workmanager_service.dart` line 165:** `return openStore(directory: directoryPath);` — returned to caller.
4. **`workmanager_service.dart` line 169:** `return openStore();` — returned to caller.

Observations:

- **`loadObjectBoxLibraryAndroidCompat()`**: The `openStore()` wrapper in `objectbox.g.dart` (line 471) calls `await loadObjectBoxLibraryAndroidCompat()` before creating the Store. `Store.attach()` does NOT call this. The native library must already be loaded.

- **`defaultStoreDirectory()`**: The `openStore()` wrapper resolves the default directory if none is provided (line 474). With `Store.attach()`, the directory path must be explicitly provided. `main.dart` already calls `defaultStoreDirectory()` at line 246.

- **`Future` vs synchronous**: All callers `await` the result of `openStore()`. `Store.attach()` is a synchronous constructor.

- **Store instance reuse**: Both `openStore()` and `Store.attach()` return a new `Store` instance. `Store.attach()` wraps the same underlying native store.

### Q27. After transitioning to `Store.attach()`, is there still a need for any of: `_closeMainStoreForBackground`, `_reopenMainStoreIfNeeded`, `StoreBusyGuard`?

**`_closeMainStoreForBackground()`:**
- Called from `didChangeAppLifecycleState` on `paused`/`detached` (line 401).
- Its purpose: close the Store so WorkManager can open it.
- With `Store.attach()`, the Store is shared, not opened exclusively. The close is what triggers the "another store is still open" conflict.

**`_reopenMainStoreIfNeeded()`:**
- Called from `didChangeAppLifecycleState` on `resumed` (line 403).
- Its purpose: reopen the Store after it was closed on background.
- Recreates all repositories, services, and the router.

**`StoreBusyGuard`:**
- Used in 6 repository methods (`save()` and `delete()` in 3 repositories).
- Also checked in `_closeMainStoreForBackground()` (line 419).
- Its purpose: prevent closing the Store during an active write transaction.

---

## 7. Required Deliverable

*(To be filled after all questions are answered — the final list of code changes, deletions, and edge cases.)*
