import 'package:objectbox/objectbox.dart';

@Entity()
class Reminder {
  @Id()
  int id = 0;

  String url;
  String title;
  String? description;
  String? imageUrl;

  // YouTube Playlist fields
  bool isPlaylist = false;
  String? playlistId;
  String? playlistTitle;
  String? playlistThumbnail;
  int? playlistCurrentIndex;
  int? playlistTotalItems;
  String? currentVideoUrl;

  // AI-generated classification
  String? categoryEn;
  String? categoryAr;
  String? categoryFr;
  String? complexityEn;
  String? complexityAr;
  String? complexityFr;
  bool isEthical = true;
  String? ethicalReasoning;
  String? ethicalReasoningAr;
  String? ethicalReasoningFr;

  String importance;

  @Property(type: PropertyType.date)
  DateTime scheduledAt;

  @Property(type: PropertyType.date)
  DateTime createdAt;

  @Property(type: PropertyType.date)
  DateTime? openedAt;

  bool isOpened = false;
  String? aiExplanation;
  String? aiExplanationAr;
  String? aiExplanationFr;

  int rescheduleAttempts = 0;

  Reminder({
    this.id = 0,
    required this.url,
    required this.title,
    this.description,
    this.imageUrl,
    this.categoryEn,
    this.categoryAr,
    this.categoryFr,
    this.complexityEn,
    this.complexityAr,
    this.complexityFr,
    this.isEthical = true,
    this.ethicalReasoning,
    this.ethicalReasoningAr,
    this.ethicalReasoningFr,
    required this.importance,
    required this.scheduledAt,
    required this.createdAt,
    this.openedAt,
    this.isOpened = false,
    this.aiExplanation,
    this.aiExplanationAr,
    this.aiExplanationFr,
    this.rescheduleAttempts = 0,
  });
}
