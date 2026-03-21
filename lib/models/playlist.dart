import 'package:objectbox/objectbox.dart';

@Entity()
class Playlist {
  @Id()
  int id = 0;

  String playlistId;
  String title;
  String description;
  String? thumbnailUrl;
  String channelName;
  String channelUrl;
  int totalItems;

  int currentIndex = 0;

  @Property(type: PropertyType.date)
  DateTime createdAt;

  @Property(type: PropertyType.date)
  DateTime lastAccessedAt;

  bool isCompleted = false;

  Playlist({
    this.id = 0,
    required this.playlistId,
    required this.title,
    required this.description,
    this.thumbnailUrl,
    required this.channelName,
    required this.channelUrl,
    required this.totalItems,
    this.currentIndex = 0,
    required this.createdAt,
    required this.lastAccessedAt,
    this.isCompleted = false,
  });
}
