import 'package:objectbox/objectbox.dart';
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

  List<Map<String, dynamic>> getAllAsJson() {
    final slots = getAll();
    return slots.map((slot) => {
      'dayOfWeek': slot.dayOfWeek,
      'startTime': slot.startTime,
      'endTime': slot.endTime,
    }).toList();
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
}
