import '../core/url_normalizer.dart';
import '../models/reminder.dart';
import '../objectbox.g.dart';
import 'package:flutter/foundation.dart';

class ReminderRepository {
  final Box<Reminder> _box;

  ReminderRepository(Store store) : _box = store.box<Reminder>();

  int save(Reminder reminder) {
    return _box.put(reminder);
  }

  Reminder? getById(int id) {
    return _box.get(id);
  }

  /// Finds a reminder whose [url] matches [targetUrl], treating the link as
  /// the identity of the post (tracking params / trailing slash ignored).
  Reminder? findByUrl(String targetUrl) {
    final normalizedTarget = normalizeUrl(targetUrl);

    // Fast path: exact match on the stored value.
    final query = _box.query(Reminder_.url.equals(targetUrl)).build();
    final exact = query.find();
    query.close();
    if (exact.isNotEmpty) return exact.first;

    // Fallback: compare normalized forms (stored rows may contain variants).
    for (final reminder in _box.getAll()) {
      if (normalizeUrl(reminder.url) == normalizedTarget) {
        return reminder;
      }
    }
    return null;
  }

  /// All reminders sharing the same (normalized) link — used for cleanup of
  /// duplicates created before URL-based dedupe existed.
  List<Reminder> findAllByUrl(String targetUrl) {
    final normalizedTarget = normalizeUrl(targetUrl);
    return _box
        .getAll()
        .where((r) => normalizeUrl(r.url) == normalizedTarget)
        .toList();
  }

  List<Reminder> getAll() {
    return _box.getAll();
  }

  List<Reminder> getUnread() {
    final query = _box.query(Reminder_.isOpened.equals(false)).build();
    final results = query.find();
    query.close();
    // Sort by scheduledAt ascending
    results.sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
    return results;
  }

  List<Reminder> getRead() {
    final query = _box.query(Reminder_.isOpened.equals(true)).build();
    final results = query.find();
    query.close();
    // Sort by openedAt descending
    results.sort((a, b) {
      final aTime = a.openedAt ?? DateTime(1970);
      final bTime = b.openedAt ?? DateTime(1970);
      return bTime.compareTo(aTime);
    });
    return results;
  }

  List<Reminder> getMissed() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final unread = getUnread();
    return unread
        .where((r) => r.scheduledAt.millisecondsSinceEpoch < now)
        .toList();
  }

  bool delete(int id) {
    return _box.remove(id);
  }

  /// Deletes a reminder and cancels its associated notification and WorkManager task.
  /// Pass a callback to cancel the notification (e.g., `notificationService.cancelReminder`).
  Future<void> deleteWithCleanup(
    int id,
    Future<void> Function(int) cancelNotification,
  ) async {
    debugPrint('[ReminderRepository] deleteWithCleanup called for id=$id');
    await cancelNotification(id);
    debugPrint(
      '[ReminderRepository] Notification cancelled, removing from box',
    );
    _box.remove(id);
    debugPrint('[ReminderRepository] Removed from box');
  }

  int getTotalCount() {
    return _box.count();
  }

  int getOpenedCount() {
    final query = _box.query(Reminder_.isOpened.equals(true)).build();
    final count = query.count();
    query.close();
    return count;
  }

  List<Reminder> getByCategory(String category) {
    final query = _box.query(Reminder_.categoryEn.equals(category)).build();
    final results = query.find();
    query.close();
    return results;
  }

  Map<String, List<Reminder>> getRemindersGroupedByCategory() {
    final all = getAll();
    final Map<String, List<Reminder>> grouped = {};
    for (final reminder in all) {
      final category = reminder.categoryEn ?? 'Uncategorized';
      if (!grouped.containsKey(category)) {
        grouped[category] = [];
      }
      grouped[category]!.add(reminder);
    }
    return grouped;
  }

  List<Reminder> getPendingReminders() {
    final now = DateTime.now();
    final query = _box.query(Reminder_.isOpened.equals(false)).build();
    final results = query.find();
    query.close();
    return results.where((r) => r.scheduledAt.isAfter(now)).toList();
  }

  /// Returns all unread reminders (not opened), regardless of scheduled time.
  /// Used for overdue detection.
  List<Reminder> getAllUnread() {
    final query = _box.query(Reminder_.isOpened.equals(false)).build();
    final results = query.find();
    query.close();
    // Sort by scheduledAt ascending
    results.sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
    return results;
  }

  List<Reminder> getReminderHistory(int id) {
    final reminder = _box.get(id);
    if (reminder == null) return [];
    final query = _box
        .query(
          Reminder_.url
              .equals(reminder.url)
              .and(
                Reminder_.createdAt.lessThan(
                  reminder.createdAt.millisecondsSinceEpoch + 1,
                ),
              ),
        )
        .build();
    final results = query.find();
    query.close();
    return results;
  }
}
