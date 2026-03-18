import 'dart:convert';
import '../models/category_statistic.dart';
import '../models/reminder.dart';
import '../objectbox.g.dart';

class CategoryStatisticRepository {
  final Box<CategoryStatistic> _box;

  CategoryStatisticRepository(Store store) : _box = store.box<CategoryStatistic>();

  CategoryStatistic? getById(int id) {
    return _box.get(id);
  }

  List<CategoryStatistic> getAll() {
    return _box.getAll();
  }

  CategoryStatistic? findByCategoryAndComplexity(String categoryEn, String complexityEn) {
    final query = _box.query(
      CategoryStatistic_.categoryEn.equals(categoryEn) &
      CategoryStatistic_.complexityEn.equals(complexityEn)
    ).build();
    final result = query.findFirst();
    query.close();
    return result;
  }

  int save(CategoryStatistic stat) {
    return _box.put(stat);
  }

  void recordSaved(Reminder reminder) {
    final categoryEn = reminder.categoryEn ?? 'Other';
    final complexityEn = reminder.complexityEn ?? 'Medium';

    var stat = findByCategoryAndComplexity(categoryEn, complexityEn);
    if (stat == null) {
      stat = CategoryStatistic(
        categoryEn: categoryEn,
        complexityEn: complexityEn,
        totalCount: 1,
      );
    } else {
      stat.totalCount++;
      stat.lastUpdated = DateTime.now();
    }
    save(stat);
  }

  void recordOpened(Reminder reminder) {
    final categoryEn = reminder.categoryEn ?? 'Other';
    final complexityEn = reminder.complexityEn ?? 'Medium';

    var stat = findByCategoryAndComplexity(categoryEn, complexityEn);
    if (stat == null) {
      stat = CategoryStatistic(
        categoryEn: categoryEn,
        complexityEn: complexityEn,
        openedCount: 1,
      );
    } else {
      stat.openedCount++;
      stat.lastUpdated = DateTime.now();

      // Update average time to open
      if (reminder.openedAt != null) {
        final secondsToOpen = reminder.openedAt!.difference(reminder.scheduledAt).inSeconds;
        if (secondsToOpen > 0) {
          final totalSeconds = stat.avgSecondsToOpen * (stat.openedCount - 1) + secondsToOpen;
          stat.avgSecondsToOpen = totalSeconds / stat.openedCount;
        }
      }

      // Update opened hours
      if (reminder.openedAt != null) {
        final hour = reminder.openedAt!.hour.toString().padLeft(2, '0');
        final hoursMap = stat.openedHoursJson != null 
            ? Map<String, int>.from(json.decode(stat.openedHoursJson!))
            : <String, int>{};
        hoursMap[hour] = (hoursMap[hour] ?? 0) + 1;
        stat.openedHoursJson = json.encode(hoursMap);

        // Update opened days
        final days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
        final day = days[reminder.openedAt!.weekday - 1];
        final daysMap = stat.openedDaysJson != null
            ? Map<String, int>.from(json.decode(stat.openedDaysJson!))
            : <String, int>{};
        daysMap[day] = (daysMap[day] ?? 0) + 1;
        stat.openedDaysJson = json.encode(daysMap);
      }
    }
    save(stat);
  }

  void recordNotOpened(Reminder reminder) {
    final categoryEn = reminder.categoryEn ?? 'Other';
    final complexityEn = reminder.complexityEn ?? 'Medium';

    var stat = findByCategoryAndComplexity(categoryEn, complexityEn);
    if (stat == null) {
      stat = CategoryStatistic(
        categoryEn: categoryEn,
        complexityEn: complexityEn,
        notOpenedCount: 1,
      );
    } else {
      stat.notOpenedCount++;
      stat.lastUpdated = DateTime.now();

      // Update not opened hours
      final hour = reminder.scheduledAt.hour.toString().padLeft(2, '0');
      final hoursMap = stat.notOpenedHoursJson != null
          ? Map<String, int>.from(json.decode(stat.notOpenedHoursJson!))
          : <String, int>{};
      hoursMap[hour] = (hoursMap[hour] ?? 0) + 1;
      stat.notOpenedHoursJson = json.encode(hoursMap);

      // Update not opened days
      final days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
      final day = days[reminder.scheduledAt.weekday - 1];
      final daysMap = stat.notOpenedDaysJson != null
          ? Map<String, int>.from(json.decode(stat.notOpenedDaysJson!))
          : <String, int>{};
      daysMap[day] = (daysMap[day] ?? 0) + 1;
      stat.notOpenedDaysJson = json.encode(daysMap);
    }
    save(stat);
  }

  bool delete(int id) {
    return _box.remove(id);
  }
}
