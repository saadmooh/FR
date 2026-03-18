import 'package:objectbox/objectbox.dart';

@Entity()
class CategoryStatistic {
  @Id()
  int id = 0;

  String categoryEn;
  String complexityEn;
  int totalCount = 0;
  int openedCount = 0;
  int notOpenedCount = 0;
  double avgSecondsToOpen = 0;
  String? openedHoursJson;
  String? openedDaysJson;
  String? notOpenedHoursJson;
  String? notOpenedDaysJson;

  @Property(type: PropertyType.date)
  DateTime lastUpdated;

  CategoryStatistic({
    this.id = 0,
    required this.categoryEn,
    required this.complexityEn,
    this.totalCount = 0,
    this.openedCount = 0,
    this.notOpenedCount = 0,
    this.avgSecondsToOpen = 0,
    this.openedHoursJson,
    this.openedDaysJson,
    this.notOpenedHoursJson,
    this.notOpenedDaysJson,
    DateTime? lastUpdated,
  }) : lastUpdated = lastUpdated ?? DateTime.now();
}
