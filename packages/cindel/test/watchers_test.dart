import 'dart:async';
import 'dart:io';

import 'package:cindel/cindel.dart';
import 'package:test/test.dart';

void main() {
  group('Cindel watchers', () {
    // Scenario: A document watcher observes a missing document, an insert, and a delete.
    // Covers:
    // - [CindelDatabase.watchDocument] initial snapshot emission.
    // - Local post-commit notifications after [CindelDatabase.put].
    // - Local post-commit notifications after [CindelDatabase.delete].
    // Expected: The stream emits null, the stored document, then null again.
    test('emits document snapshots after committed local changes.', () async {
      // Arrange.
      final directory = await _createDatabaseDirectory();
      addTearDown(() => directory.delete(recursive: true));
      final database = await Cindel.open(directory: directory.path);
      addTearDown(database.close);
      final events = <CindelDocument?>[];
      final subscription = database
          .watchDocument(
            'users',
            1,
            pollInterval: const Duration(milliseconds: 5),
          )
          .listen(events.add);
      addTearDown(subscription.cancel);

      // Act.
      await _waitUntil(() => events.length == 1);
      await database.put('users', 1, {'name': 'Ana'});
      await _waitUntil(() => events.length == 2);
      await database.delete('users', 1);
      await _waitUntil(() => events.length == 3);

      // Assert.
      expect(events, [
        null,
        {'name': 'Ana'},
        null,
      ]);
    });

    // Scenario: A collection watcher observes writes from a separate handle.
    // Covers:
    // - [CindelDatabase.watchCollection] reading snapshots in id order.
    // - Native collection revisions being visible across database handles.
    // - Polling-based notifications when no local Dart write occurs.
    // Expected: The watcher emits an empty collection and then both documents.
    test(
      'emits collection snapshots after committed external changes.',
      () async {
        // Arrange.
        final directory = await _createDatabaseDirectory();
        addTearDown(() => directory.delete(recursive: true));
        final watcherDatabase = await Cindel.open(directory: directory.path);
        addTearDown(watcherDatabase.close);
        final writerDatabase = await Cindel.open(directory: directory.path);
        addTearDown(writerDatabase.close);
        final events = <List<CindelDocument>>[];
        final subscription = watcherDatabase
            .watchCollection(
              'users',
              pollInterval: const Duration(milliseconds: 5),
            )
            .listen(events.add);
        addTearDown(subscription.cancel);

        // Act.
        await _waitUntil(() => events.length == 1);
        await writerDatabase.put('users', 2, {'name': 'Ben'});
        await writerDatabase.put('users', 1, {'name': 'Ana'});
        await _waitUntil(
          () => events.any((documents) => documents.length == 2),
        );
        final latestDocuments = events.lastWhere(
          (documents) => documents.length == 2,
        );

        // Assert.
        expect(events.first, isEmpty);
        expect(latestDocuments, [
          {'name': 'Ana'},
          {'name': 'Ben'},
        ]);
      },
    );

    // Scenario: A watcher is requested with an invalid polling interval.
    // Covers:
    // - Public API input validation before timers are created.
    // - Consistent [ArgumentError] behavior for invalid watcher options.
    // Expected: Invalid polling intervals fail synchronously.
    test('rejects invalid watcher polling intervals.', () async {
      // Arrange.
      final directory = await _createDatabaseDirectory();
      addTearDown(() => directory.delete(recursive: true));
      final database = await Cindel.open(directory: directory.path);
      addTearDown(database.close);

      // Act.
      Stream<CindelDocument?> createWatcher() {
        return database.watchDocument('users', 1, pollInterval: Duration.zero);
      }

      // Assert.
      expect(createWatcher, throwsArgumentError);
    });
  });
}

Future<void> _waitUntil(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 2),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('Timed out waiting for watcher event.');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

Future<Directory> _createDatabaseDirectory() {
  return Directory.systemTemp.createTemp('cindel_');
}
