import 'package:flutter_test/flutter_test.dart';
import 'package:smart_pocket/core/time_range.dart';

TimeRange _range(String start, String end) {
  int minutes(String hhmm) {
    final parts = hhmm.split(':');
    return int.parse(parts[0]) * 60 + int.parse(parts[1]);
  }

  return TimeRange(minutes(start), minutes(end));
}

void main() {
  group('mergeTimeRanges', () {
    test('keeps disjoint ranges separate', () {
      final merged = mergeTimeRanges([
        _range('09:00', '11:00'),
        _range('14:00', '16:00'),
      ]);

      expect(merged, [_range('09:00', '11:00'), _range('14:00', '16:00')]);
    });

    test('identical ranges collapse into one', () {
      final merged = mergeTimeRanges([
        _range('09:00', '11:00'),
        _range('09:00', '11:00'),
      ]);

      expect(merged, [_range('09:00', '11:00')]);
    });

    test('touching ranges are joined', () {
      final merged = mergeTimeRanges([
        _range('09:00', '12:00'),
        _range('12:00', '15:00'),
      ]);

      expect(merged, [_range('09:00', '15:00')]);
    });

    test('overlapping ranges collapse to their union', () {
      final merged = mergeTimeRanges([
        _range('10:00', '13:00'),
        _range('11:00', '12:00'),
      ]);

      expect(merged, [_range('10:00', '13:00')]);
    });

    test('a bridging range joins several separate ones', () {
      final merged = mergeTimeRanges([
        _range('08:00', '10:00'),
        _range('16:00', '18:00'),
        _range('09:30', '17:00'),
      ]);

      expect(merged, [_range('08:00', '18:00')]);
    });

    test('results are sorted by start time', () {
      final merged = mergeTimeRanges([
        _range('20:00', '22:00'),
        _range('08:00', '09:00'),
        _range('09:00', '10:00'), // touches 08:00-09:00
      ]);

      expect(merged, [_range('08:00', '10:00'), _range('20:00', '22:00')]);
    });

    test('empty input yields no ranges', () {
      expect(mergeTimeRanges(const []), isEmpty);
    });
  });

  group('TimeRange', () {
    test('overlapsOrTouches detects strict overlap and touching', () {
      expect(
        const TimeRange(540, 720).overlapsOrTouches(const TimeRange(720, 900)),
        isTrue,
      );
      expect(
        const TimeRange(540, 720).overlapsOrTouches(const TimeRange(719, 900)),
        isTrue,
      );
      expect(
        const TimeRange(540, 720).overlapsOrTouches(const TimeRange(721, 900)),
        isFalse,
      );
    });

    test('contains only when fully covering', () {
      expect(
        const TimeRange(540, 900).contains(const TimeRange(600, 700)),
        isTrue,
      );
      expect(
        const TimeRange(540, 900).contains(const TimeRange(600, 901)),
        isFalse,
      );
    });
  });
}
