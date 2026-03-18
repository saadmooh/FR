import 'package:objectbox/objectbox.dart';

@Entity()
class Reminder {
  @Id()
  int id = 0;

  String url;
  String title;
  String? description;
  String? imageUrl;

  // AI-generated classification
  String? categoryEn;
  String? categoryAr;
  String? complexityEn;
  String? complexityAr;
  bool isEthical = true;
  String? ethicalReasoning;

  String importance;
  
  @Property(type: PropertyType.date)
  DateTime scheduledAt;

  @Property(type: PropertyType.date)
  DateTime createdAt;

  @Property(type: PropertyType.date)
  DateTime? openedAt;

  bool isOpened = false;
  String? aiExplanation;

  Reminder({
    this.id = 0,
    required this.url,
    required this.title,
    this.description,
    this.imageUrl,
    this.categoryEn,
    this.categoryAr,
    this.complexityEn,
    this.complexityAr,
    this.isEthical = true,
    this.ethicalReasoning,
    required this.importance,
    required this.scheduledAt,
    required this.createdAt,
    this.openedAt,
    this.isOpened = false,
    this.aiExplanation,
  });
}
