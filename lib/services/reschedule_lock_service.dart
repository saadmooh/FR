import 'package:objectbox/objectbox.dart';

import '../models/reschedule_lock.dart';
import '../objectbox.g.dart';

class RescheduleLockService {
  final Store _store;
  final Box<RescheduleLock> _box;

  RescheduleLockService(Store store)
      : _store = store,
        _box = store.box<RescheduleLock>();

  /// Attempts to acquire a reschedule lock for the given reminder.
  ///
  /// Uses an atomic ObjectBox transaction to prevent TOCTOU race conditions.
  /// Returns true if lock acquired, false if another process holds a valid lock.
  ///
  /// [ttl] - Time-to-live for the lock in milliseconds (default: 180000 = 3 minutes)
  bool acquireLock(int reminderId, {int ttl = 180000}) {
    return _store.runInTransaction(TxMode.write, () {
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final query = _box.query(RescheduleLock_.reminderId.equals(reminderId)).build();
      final existing = query.findFirst();
      query.close();

      if (existing != null && nowMs - existing.timestamp < ttl) {
        return false;
      }

      if (existing != null) {
        existing.timestamp = nowMs;
        _box.put(existing);
      } else {
        _box.put(RescheduleLock(reminderId: reminderId, timestamp: nowMs));
      }
      return true;
    });
  }

  /// Releases the reschedule lock for the given reminder.
  void releaseLock(int reminderId) {
    _store.runInTransaction(TxMode.write, () {
      final query = _box.query(RescheduleLock_.reminderId.equals(reminderId)).build();
      final existing = query.findFirst();
      query.close();
      if (existing != null) {
        _box.remove(existing.id);
      }
    });
  }

  /// Checks if a valid lock exists (without acquiring).
  bool hasValidLock(int reminderId, {int ttl = 180000}) {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final query = _box.query(RescheduleLock_.reminderId.equals(reminderId)).build();
    final existing = query.findFirst();
    query.close();

    if (existing == null) return false;
    return nowMs - existing.timestamp < ttl;
  }

  /// Cleans up all expired locks.
  void cleanupExpiredLocks({int ttl = 180000}) {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final query = _box.query(RescheduleLock_.reminderId.greaterThan(0)).build();
    final allLocks = query.find();
    query.close();

    _store.runInTransaction(TxMode.write, () {
      for (final lock in allLocks) {
        if (nowMs - lock.timestamp >= ttl) {
          _box.remove(lock.id);
        }
      }
    });
  }

  /// Gets the store instance for transaction access.
  Store get store => _store;
}