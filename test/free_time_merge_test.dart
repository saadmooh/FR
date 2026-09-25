import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_pocket/models/free_time_slot.dart';
import 'package:smart_pocket/objectbox.g.dart';
import 'package:smart_pocket/repositories/free_time_repository.dart';

FreeTimeSlot _slot({
  required int day,
  required String start,
  required String end,
}) {
  return FreeTimeSlot(dayOfWeek: day, startTime: start, endTime: end);
}

void main() {
  late Directory dir;
  Store? store;
  FreeTimeRepository? repository;
  var objectBoxAvailable = false;

  setUpAll(() async {
    try {
      dir = await Directory.systemTemp.createTemp('free_time_merge_test');
      store = Store(getObjectBoxModel(), directory: dir.path);
      repository = FreeTimeRepository(store!);
      objectBoxAvailable = true;
    } catch (_) {
      // ObjectBox native library unavailable in this environment; tests skip.
      objectBoxAvailable = false;
      store = null;
      repository = null;
    }
  });

  tearDown(() {
    if (!objectBoxAvailable) return;
    for (final existing in repository!.getAll()) {
      repository!.delete(existing.id);
    }
  });

  tearDownAll(() {
    store?.close();
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });

  final skipReason = objectBoxAvailable
      ? false
      : 'ObjectBox native library unavailable in this environment';

  test('a non-overlapping slot is stored as its own row', () {
    repository!.saveMerged(_slot(day: 1, start: '09:00', end: '11:00'));
    repository!.saveMerged(_slot(day: 1, start: '14:00', end: '16:00'));

    final slots = repository!.getByDay(1);
    expect(slots.length, 2);
  }, skip: skipReason);

  test('an exact duplicate does not create a second row', () {
    repository!.saveMerged(_slot(day: 2, start: '09:00', end: '11:00'));
    repository!.saveMerged(_slot(day: 2, start: '09:00', end: '11:00'));

    final slots = repository!.getByDay(2);
    expect(slots.length, 1);
    expect(slots.first.startTime, '09:00');
    expect(slots.first.endTime, '11:00');
  }, skip: skipReason);

  test(
    'touching slots are joined into one (09-12 + 12-15 => 09-15)',
    () {
      repository!.saveMerged(_slot(day: 3, start: '09:00', end: '12:00'));
      repository!.saveMerged(_slot(day: 3, start: '12:00', end: '15:00'));

      final slots = repository!.getByDay(3);
      expect(slots.length, 1);
      expect(slots.first.startTime, '09:00');
      expect(slots.first.endTime, '15:00');
    },
    skip: skipReason,
  );

  test('overlapping slots are joined into their union', () {
    repository!.saveMerged(_slot(day: 4, start: '10:00', end: '13:00'));
    repository!.saveMerged(_slot(day: 4, start: '11:00', end: '12:00'));

    final slots = repository!.getByDay(4);
    expect(slots.length, 1);
    expect(slots.first.startTime, '10:00');
    expect(slots.first.endTime, '13:00');
  }, skip: skipReason);

  test('merging is transitive across a chain of slots', () {
    repository!.saveMerged(_slot(day: 5, start: '08:00', end: '10:00'));
    repository!.saveMerged(_slot(day: 5, start: '16:00', end: '18:00'));
    // Bridges the two separate slots -> one 08:00-18:00 slot.
    repository!.saveMerged(_slot(day: 5, start: '09:30', end: '17:00'));

    final slots = repository!.getByDay(5);
    expect(slots.length, 1);
    expect(slots.first.startTime, '08:00');
    expect(slots.first.endTime, '18:00');
  }, skip: skipReason);

  test('slots on different days never merge', () {
    repository!.saveMerged(_slot(day: 6, start: '09:00', end: '12:00'));
    repository!.saveMerged(_slot(day: 7, start: '09:00', end: '12:00'));

    expect(repository!.getByDay(6).length, 1);
    expect(repository!.getByDay(7).length, 1);
  }, skip: skipReason);

  test('normalizeAll cleans up duplicates already stored', () {
    // Bypass saveMerged to simulate legacy/duplicated rows.
    repository!.save(_slot(day: 1, start: '18:00', end: '20:00'));
    repository!.save(_slot(day: 1, start: '19:00', end: '21:00'));
    repository!.save(_slot(day: 1, start: '21:00', end: '22:00'));

    repository!.normalizeAll();

    final dayOne = repository!.getByDay(1);
    expect(dayOne.length, 1);
    expect(dayOne.first.startTime, '18:00');
    expect(dayOne.first.endTime, '22:00');
  }, skip: skipReason);
}
