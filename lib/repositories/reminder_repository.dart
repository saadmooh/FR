import '../models/reminder.dart';
import '../objectbox.g.dart';

class ReminderRepository {
  final Box<Reminder> _box;

  ReminderRepository(Store store) : _box = store.box<Reminder>();

  int save(Reminder reminder) {
    return _box.put(reminder);
  }

  Reminder? getById(int id) {
    return _box.get(id);
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
    return unread.where((r) => r.scheduledAt.millisecondsSinceEpoch < now).toList();
  }

  bool delete(int id) {
    return _box.remove(id);
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
}
