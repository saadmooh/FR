import 'package:objectbox/objectbox.dart';

@Entity()
class FreeTimeSlot {
  @Id()
  int id = 0;

  int dayOfWeek;
  String startTime;
  String endTime;

  FreeTimeSlot({
    this.id = 0,
    required this.dayOfWeek,
    required this.startTime,
    required this.endTime,
  });
}
