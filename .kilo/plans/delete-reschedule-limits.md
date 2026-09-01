# Plan: Delete Hardcoded Rescheduling Limits

## Objective
Remove the hardcoded max rescheduling limits from the Flutter code. Only Supabase should enforce limits via its database functions.

## Files to Modify

### 1. Modify `lib/services/reschedule_policy.dart`
- Remove `maxReschedulesFor()` function
- Remove `reschedulingDeadline()` function
- Keep `clampRescheduleTime()` function (ensures times are always in the future)

### 2. Update `lib/services/workmanager_service.dart`
- Keep import of `reschedule_policy.dart` (for `clampRescheduleTime`)
- Remove the local check at line 299:
  ```dart
  if (reminder.rescheduleAttempts >= maxReschedules) {
    await _log('Reminder $reminderId reached max reschedules ($maxReschedules)');
    return;
  }
  ```
- Remove the `reschedulingDeadline` usage at lines 397-400
- Keep `clampRescheduleTime` usage to ensure future times
- Let Supabase handle all limit decisions

### 3. Update `lib/services/overdue_reminder_service.dart`
- Keep import of `reschedule_policy.dart` (for `clampRescheduleTime`)
- Remove the local check at line 147:
  ```dart
  if (reminder.rescheduleAttempts >= maxReschedules) {
    // ...
    return false;
  }
  ```
- Remove the `reschedulingDeadline` usage at line 268
- Keep `clampRescheduleTime` usage to ensure future times
- Let Supabase handle all limit decisions

### 4. Check other files
- Verify no other files import `reschedule_policy.dart`
- Update any remaining imports

## Verification
- Run `flutter analyze` to ensure no broken imports
- Run `flutter test` to verify no test failures
- Check that the app still compiles correctly

## Notes
- The `clampRescheduleTime` function is kept for ensuring times are always in the future
- The `rescheduleAttempts` field in the Reminder model can remain (Supabase may still need it)
- Lock service (`reschedule_lock_service.dart`) is separate and should remain