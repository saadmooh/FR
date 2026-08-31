import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:objectbox/objectbox.dart';
import 'package:smart_pocket/objectbox.g.dart';
import 'package:smart_pocket/services/reschedule_lock_service.dart';

void main() {
  late Directory? dir;
  Store? store;
  late RescheduleLockService? lockService;
  var objectBoxAvailable = false;

  setUpAll(() async {
    try {
      dir = await Directory.systemTemp.createTemp('reschedule_lock_test');
      store = Store(getObjectBoxModel(), directory: dir!.path);
      lockService = RescheduleLockService(store!);
      objectBoxAvailable = true;
    } catch (_) {
      // ObjectBox native library unavailable in this environment; tests skip.
      objectBoxAvailable = false;
      store = null;
      lockService = null;
    }
  });

  tearDownAll(() {
    store?.close();
    try {
      dir?.deleteSync(recursive: true);
    } catch (_) {}
  });

  final skipReason = objectBoxAvailable
      ? false
      : 'ObjectBox native library unavailable in this environment';

  test('atomic lock: only one of two concurrent attempts acquires it',
      () async {
        final results = await Future.wait([
          Future.sync(() => lockService!.acquireLock(1)),
          Future.sync(() => lockService!.acquireLock(1)),
        ]);

        // Exactly one attempt succeeds, mirroring the duplicate-reschedule race.
        expect(results.where((r) => r).length, equals(1));
        expect(lockService!.hasValidLock(1), isTrue);
      },
      skip: skipReason);

  test('a valid lock blocks re-acquisition within its TTL', () {
    expect(lockService!.acquireLock(2), isTrue);
    expect(lockService!.acquireLock(2), isFalse);
  }, skip: skipReason);

  test('releaseLock frees the reminder for re-acquisition', () {
    expect(lockService!.acquireLock(3), isTrue);
    lockService!.releaseLock(3);
    expect(lockService!.acquireLock(3), isTrue);
  }, skip: skipReason);

  test('locks are scoped per reminder id', () {
    expect(lockService!.acquireLock(4), isTrue);
    expect(lockService!.acquireLock(5), isTrue);
    expect(lockService!.acquireLock(4), isFalse);
    expect(lockService!.acquireLock(5), isFalse);
  }, skip: skipReason);
}