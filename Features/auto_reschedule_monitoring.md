# Auto Reschedule Monitoring System

## Overview

An intelligent monitoring system that automatically detects unopened reminders and reschedules them using AI to find better times. The system fires 5 minutes after the original notification time to check if the user has read the reminder.

## Architecture

### Components

1. **Monitoring Notification** - A silent, invisible notification scheduled 5 minutes after each reminder
2. **Background Callback** - A top-level function that runs when the monitoring notification fires
3. **AI Rescheduling** - Uses the existing `AIService.reschedulePost()` to find optimal new times
4. **Reschedule Limits** - Prevents infinite rescheduling based on reminder importance

## Flow

### 1. Scheduling Phase

When `scheduleReminder()` is called:

- The main reminder notification is scheduled at `reminder.scheduledAt`
- A silent monitoring notification is scheduled at `reminder.scheduledAt + 5 minutes`
- The monitoring notification has:
  - Empty title and body (invisible to user)
  - Low priority, no sound, no vibration
  - Secret visibility (hidden from lock screen)
  - Payload prefixed with `monitor:` containing the reminder ID

### 2. Monitoring Phase (5 minutes after notification)

When the monitoring notification fires, the background callback executes:

1. **Parse reminder ID** from the payload
2. **Check if already opened** - If `isOpened == true`, exit immediately
3. **Check reschedule limits** - Based on importance:
   - `Day` importance: max 1 reschedule
   - `Week` importance: max 2 reschedules
   - `Month` importance: max 3 reschedules
4. **Check deadline** - If the reminder is more than 30 days past due, stop rescheduling
5. **Gather context for AI**:
   - Previous scheduling attempts from reminder history
   - User's free time slots
   - Current reminder category, complexity, and importance
6. **Call AI rescheduling** - `AIService.reschedulePost()` analyzes why previous attempts failed and suggests a new time
7. **Update reminder** with:
   - New `scheduledAt` time
   - Incremented `rescheduleAttempts`
   - AI explanation for the reschedule reason (in English and Arabic)
   - Reset `isOpened` and `openedAt`
8. **Reschedule notifications** - Cancel old notifications and schedule new main + monitoring notifications

### 3. User Opens Reminder

When the user taps the main notification:

- The normal tap handler runs
- Marks reminder as opened
- The monitoring notification still fires but exits immediately because `isOpened == true`

## Permissions

### Android Manifest (already configured)

- `SCHEDULE_EXACT_ALARM` - Required for precise notification scheduling
- `USE_EXACT_ALARM` - Required for Android 12+ exact alarms
- `POST_NOTIFICATIONS` - Required for showing notifications
- `RECEIVE_BOOT_COMPLETED` - Restores notifications after device reboot
- `VIBRATE` - For notification vibration
- `INTERNET` - For AI API calls

### Runtime Permissions

Requested during service initialization:
- Android notification permission
- Android exact alarm permission
- iOS alert, badge, and sound permissions

## Data Model Changes

### Reminder Entity

New field added:
- `rescheduleAttempts` (int, default 0) - Tracks how many times the reminder has been auto-rescheduled

## Background Execution

The monitoring callback runs in a separate Dart isolate, which requires:

1. **Top-level function** - Must be declared outside any class with `@pragma('vm:entry-point')`
2. **Self-contained initialization** - Re-initializes ObjectBox store, SharedPreferences, AIService, and repositories from scratch
3. **No UI dependencies** - Cannot access Flutter widgets or navigation

## Safety Mechanisms

1. **Reschedule limits** - Prevents infinite loops based on importance level
2. **30-day deadline** - Stops rescheduling if the reminder is too old
3. **Time validation** - Only accepts new times that are in the future
4. **Error handling** - All failures are caught and logged, never crash the app
5. **Duplicate cancellation** - Old monitoring notifications are cancelled before scheduling new ones

## Notification ID Scheme

- Main notification: `reminder.id`
- Monitoring notification: `reminder.id + 1000000`

This offset ensures no ID collisions between main and monitoring notifications.

## Files Modified

- `lib/models/reminder.dart` - Added `rescheduleAttempts` field
- `lib/services/notification_service.dart` - Added monitoring callback, scheduling, and rescheduling logic
- `lib/repositories/reminder_repository.dart` - Added `getReminderHistory()` method
- `lib/main.dart` - Updated service initialization with new repositories
