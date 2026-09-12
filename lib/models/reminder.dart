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

  // Monthly reschedule limit tracking
  int rescheduleAttemptsThisMonth = 0;
  int lastRescheduleMonth = 0; // Stores year * 100 + month (e.g., 202609 for Sep 2026)

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
    this.rescheduleAttemptsThisMonth = 0,
    this.lastRescheduleMonth = 0,
  });

  int get _currentMonthKey => DateTime.now().year * 100 + DateTime.now().month;

  bool canRescheduleThisMonth(int maxPerMonth) {
    final nowKey = _currentMonthKey;
    if (lastRescheduleMonth != nowKey) {
      return true; // New month, reset counter
    }
    return rescheduleAttemptsThisMonth < maxPerMonth;
  }

  void incrementMonthlyReschedule() {
    final nowKey = _currentMonthKey;
    if (lastRescheduleMonth != nowKey) {
      rescheduleAttemptsThisMonth = 1;
      lastRescheduleMonth = nowKey;
    } else {
      rescheduleAttemptsThisMonth++;
    }
  }
}
