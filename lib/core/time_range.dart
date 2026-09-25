/// A time range expressed in minutes from midnight.
class TimeRange {
  final int start;
  final int end;

  const TimeRange(this.start, this.end);

  /// True when two ranges overlap or merely touch (one ends where the other
  /// begins), e.g. 09:00-12:00 and 12:00-15:00.
  bool overlapsOrTouches(TimeRange other) =>
      start <= other.end && end >= other.start;

  /// Smallest range covering both.
  TimeRange union(TimeRange other) => TimeRange(
    start < other.start ? start : other.start,
    end > other.end ? end : other.end,
  );

  /// True when this range fully covers [other].
  bool contains(TimeRange other) => start <= other.start && end >= other.end;

  @override
  bool operator ==(Object other) =>
      other is TimeRange && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => 'TimeRange($start-$end)';
}

/// Merges every range that overlaps or touches another into the union,
/// returning the disjoint ranges sorted by start time.
///
/// [08:00-10:00], [16:00-18:00], [09:30-17:00] -> one [08:00-18:00] range.
List<TimeRange> mergeTimeRanges(Iterable<TimeRange> ranges) {
  final sorted = ranges.toList()
    ..sort(
      (a, b) => a.start != b.start
          ? a.start.compareTo(b.start)
          : a.end.compareTo(b.end),
    );

  final merged = <TimeRange>[];
  for (final range in sorted) {
    if (merged.isNotEmpty && merged.last.overlapsOrTouches(range)) {
      merged[merged.length - 1] = merged.last.union(range);
    } else {
      merged.add(range);
    }
  }
  return merged;
}
