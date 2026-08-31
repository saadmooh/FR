import 'package:objectbox/objectbox.dart';

@Entity()
class RescheduleLock {
  @Id()
  int id = 0;

  @Unique()
  int reminderId = 0;

  int timestamp = 0;

  RescheduleLock({
    this.id = 0,
    required this.reminderId,
    required this.timestamp,
  });
}