// Shared rescheduling policy used by both the foreground
// (OverdueReminderService) and background (WorkManager) reschedule paths,
// so the two routes cannot drift apart.

/// Maximum number of auto-reschedule attempts per reminder by importance.
int maxReschedulesFor(String importance) {
  switch (importance) {
    case 'Day':
      return 1;
    case 'Week':
      return 2;
    case 'Month':
      return 3;
    default:
      return 2;
  }
}

/// Absolute deadline for a rescheduled reminder by importance.
DateTime reschedulingDeadline(DateTime currentTime, String importance) {
  switch (importance) {
    case 'Day':
      return currentTime.add(const Duration(days: 1));
    case 'Week':
      return currentTime.add(const Duration(days: 7));
    case 'Month':
      return currentTime.add(const Duration(days: 30));
    default:
      return currentTime.add(const Duration(days: 7));
  }
}

/// Clamps [newTime] to be within `(currentTime, deadline]`.
///
/// - A time not after [currentTime] falls back to `currentTime + 1 hour`.
/// - A time past [deadline] clamps to `deadline - 30 minutes`; if that is
///   not after [currentTime] either, falls back to `currentTime + 1 hour`.
DateTime clampRescheduleTime(
  DateTime newTime,
  DateTime currentTime,
  DateTime deadline,
) {
  if (!newTime.isAfter(currentTime)) {
    return currentTime.add(const Duration(hours: 1));
  }
  if (newTime.isAfter(deadline)) {
    final clamped = deadline.subtract(const Duration(minutes: 30));
    if (clamped.isAfter(currentTime)) {
      return clamped;
    }
    return currentTime.add(const Duration(hours: 1));
  }
  return newTime;
}