import '../core/time_range.dart';
import '../models/free_time_slot.dart';
import '../objectbox.g.dart';

class FreeTimeRepository {
  final Box<FreeTimeSlot> _box;

  FreeTimeRepository(Store store) : _box = store.box<FreeTimeSlot>();

  int save(FreeTimeSlot slot) {
    return _box.put(slot);
  }

  FreeTimeSlot? getById(int id) {
    return _box.get(id);
  }

  List<FreeTimeSlot> getAll() {
    return _box.getAll();
  }

  List<FreeTimeSlot> getByDay(int dayOfWeek) {
    final query = _box.query(FreeTimeSlot_.dayOfWeek.equals(dayOfWeek)).build();
    final results = query.find();
    query.close();
    return results;
  }

  bool delete(int id) {
    return _box.remove(id);
  }

  /// Saves [slot], joining it with every same-day slot it overlaps or touches.
  ///
  /// Example: existing 09:00-12:00 + new 12:00-15:00 -> one 09:00-15:00 slot.
  /// Absorbed rows are removed, so no duplicate or overlapping slots remain.
  /// Returns the id of the stored (possibly joined) slot.
  int saveMerged(FreeTimeSlot slot) {
    final newRange = _parse(slot);
    if (newRange == null || newRange.end <= newRange.start) {
      // Not a usable range: store as-is rather than guessing.
      return _box.put(slot);
    }

    final existing = <FreeTimeSlot>[];
    final existingRanges = <TimeRange>[];
    for (final row in getByDay(slot.dayOfWeek)) {
      final range = _parse(row);
      if (range == null) continue;
      existing.add(row);
      existingRanges.add(range);
    }

    final merged = mergeTimeRanges([...existingRanges, newRange]);

    // The group the new range belongs to after joining.
    final group = merged.firstWhere(
      (range) => range.contains(newRange),
      orElse: () => newRange,
    );

    final absorbed = <int>[];
    for (var i = 0; i < existing.length; i++) {
      if (group.contains(existingRanges[i])) absorbed.add(i);
    }

    if (absorbed.isEmpty) {
      // The new range is isolated: nothing to join with.
      return _box.put(slot);
    }

    for (final index in absorbed) {
      _box.remove(existing[index].id);
    }

    return _box.put(
      FreeTimeSlot(
        dayOfWeek: slot.dayOfWeek,
        startTime: _format(group.start),
        endTime: _format(group.end),
      ),
    );
  }

  /// Joins duplicate/overlapping slots already stored, per day. Safe to call
  /// on every app start; a no-op when nothing overlaps.
  void normalizeAll() {
    final Map<int, List<FreeTimeSlot>> grouped = {};
    for (final slot in _box.getAll()) {
      grouped.putIfAbsent(slot.dayOfWeek, () => []).add(slot);
    }

    for (final entry in grouped.entries) {
      final parseable = <FreeTimeSlot>[];
      final ranges = <TimeRange>[];
      for (final slot in entry.value) {
        final range = _parse(slot);
        if (range == null || range.end <= range.start) continue;
        parseable.add(slot);
        ranges.add(range);
      }
      if (parseable.isEmpty) continue;

      final merged = mergeTimeRanges(ranges);
      if (merged.length == ranges.length) continue; // Nothing overlaps.

      for (final slot in parseable) {
        _box.remove(slot.id);
      }
      for (final range in merged) {
        _box.put(
          FreeTimeSlot(
            dayOfWeek: entry.key,
            startTime: _format(range.start),
            endTime: _format(range.end),
          ),
        );
      }
    }
  }

  List<Map<String, dynamic>> getAllAsJson() {
    final slots = getAll();
    return slots
        .map(
          (slot) => {
            'dayOfWeek': slot.dayOfWeek,
            'startTime': slot.startTime,
            'endTime': slot.endTime,
          },
        )
        .toList();
  }

  Map<int, List<FreeTimeSlot>> getGroupedByDay() {
    final all = getAll();
    final Map<int, List<FreeTimeSlot>> grouped = {};
    for (final slot in all) {
      if (!grouped.containsKey(slot.dayOfWeek)) {
        grouped[slot.dayOfWeek] = [];
      }
      grouped[slot.dayOfWeek]!.add(slot);
    }
    return grouped;
  }

  static TimeRange? _parse(FreeTimeSlot slot) {
    final start = _toMinutes(slot.startTime);
    final end = _toMinutes(slot.endTime);
    if (start == null || end == null) return null;
    return TimeRange(start, end);
  }

  static int? _toMinutes(String hhmm) {
    final parts = hhmm.split(':');
    if (parts.length != 2) return null;
    final hour = int.tryParse(parts[0].trim());
    final minute = int.tryParse(parts[1].trim());
    if (hour == null || minute == null) return null;
    return hour * 60 + minute;
  }

  static String _format(int total) {
    final hour = (total ~/ 60).clamp(0, 23);
    final minute = total % 60;
    return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
  }
}
