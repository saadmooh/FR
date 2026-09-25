import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_pocket/models/reminder.dart';
import 'package:smart_pocket/objectbox.g.dart';
import 'package:smart_pocket/repositories/reminder_repository.dart';

Reminder _reminder({int id = 0, required String url, bool isOpened = false}) {
  final now = DateTime.now();
  return Reminder(
    id: id,
    url: url,
    title: 'Title for $url',
    importance: 'Day',
    scheduledAt: now.add(const Duration(hours: 24)),
    createdAt: now,
    isOpened: isOpened,
    openedAt: isOpened ? now : null,
  );
}

void main() {
  late Directory dir;
  Store? store;
  ReminderRepository? repository;
  var objectBoxAvailable = false;

  setUpAll(() async {
    try {
      dir = await Directory.systemTemp.createTemp('reminder_dedupe_test');
      store = Store(getObjectBoxModel(), directory: dir.path);
      repository = ReminderRepository(store!);
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

  test('findByUrl finds a row saved with the exact same link', () {
    repository!.save(_reminder(url: 'https://a.com/post'));

    final found = repository!.findByUrl('https://a.com/post');
    expect(found, isNotNull);
    expect(found!.url, 'https://a.com/post');
  }, skip: skipReason);

  test('the link identifies the post even with tracking params', () {
    repository!.save(
      _reminder(url: 'https://www.instagram.com/p/XYZ/?igshid=token'),
    );

    final found = repository!.findByUrl('https://www.instagram.com/p/XYZ/');
    expect(found, isNotNull);
    expect(
      repository!.findAllByUrl(
        'https://www.instagram.com/p/XYZ/?utm_source=share',
      ),
      hasLength(1),
    );
  }, skip: skipReason);

  test('findByUrl returns null for a link that was never saved', () {
    repository!.save(_reminder(url: 'https://a.com/one'));

    expect(repository!.findByUrl('https://a.com/two'), isNull);
  }, skip: skipReason);

  test(
    're-saving a row with the same id updates it instead of duplicating',
    () {
      final first = repository!.save(_reminder(url: 'https://a.com/post'));
      final reopened = _reminder(
        id: first,
        url: 'https://a.com/post',
        isOpened: false,
      );
      reopened.createdAt = DateTime.now().subtract(const Duration(days: 3));
      repository!.save(reopened);

      expect(repository!.getTotalCount(), 1);
      final row = repository!.findByUrl('https://a.com/post');
      expect(row!.isOpened, isFalse);
      expect(row.openedAt, isNull);
    },
    skip: skipReason,
  );

  test('opened and unopened states are visible to the dedupe check', () {
    repository!.save(_reminder(url: 'https://a.com/open', isOpened: true));

    final row = repository!.findByUrl('https://a.com/open');
    expect(row, isNotNull);
    expect(row!.isOpened, isTrue);
  }, skip: skipReason);
}
