import 'dart:async';
import 'dart:io';

import 'package:cindel/cindel.dart';
import 'package:test/test.dart';

import 'backend_test_support.dart';

import 'schema_generation_fixture.dart';

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
      final database = await openTestDatabase(directory: directory.path);
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

    // Scenario: High-frequency local writes touch other documents while a
    // document watcher is active.
    // Covers:
    // - Local watcher change sets carrying changed document ids.
    // - [CindelDatabase.watchDocument] skipping native reads for unrelated ids.
    // Expected: Unrelated writes do not emit, while the watched id still emits.
    test('skips document watcher reads for unrelated local changes.', () async {
      // Arrange.
      final database = await openTestDatabaseInMemory();
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
      for (var id = 2; id < 12; id += 1) {
        await database.put('users', id, {'name': 'User $id'});
      }
      await Future<void>.delayed(const Duration(milliseconds: 60));
      await database.put('users', 1, {'name': 'Ana'});
      await _waitUntil(() => events.length == 2);

      // Assert.
      expect(events, [
        null,
        {'name': 'Ana'},
      ]);
    });

    // Scenario: Local writes expose native-backed change set metadata.
    // Covers:
    // - [CindelDatabase.watchCollectionChanges] local changed ids.
    // - Batched writes preserving document ids in one watcher signal.
    // Expected: Consumers can see the exact ids changed by local writes.
    test('emits local collection change sets with changed ids.', () async {
      // Arrange.
      final database = await openTestDatabaseInMemory();
      addTearDown(database.close);
      final changes = <Set<int>?>[];
      final subscription = database
          .watchCollectionChanges(
            'users',
            pollInterval: const Duration(milliseconds: 5),
            fireImmediately: false,
          )
          .listen((change) => changes.add(change.documentIds));
      addTearDown(subscription.cancel);

      // Act.
      await Future<void>.delayed(const Duration(milliseconds: 40));
      await database.putAll('users', {
        1: {'name': 'Ana'},
        2: {'name': 'Ben'},
      });
      await _waitUntil(() => changes.length == 1);

      // Assert.
      expect(changes.single, {1, 2});
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
        final watcherDatabase = await openTestDatabase(
          directory: directory.path,
        );
        addTearDown(watcherDatabase.close);
        final writerDatabase = await openTestDatabase(
          directory: directory.path,
        );
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
      final database = await openTestDatabase(directory: directory.path);
      addTearDown(database.close);

      // Act.
      Stream<CindelDocument?> createWatcher() {
        return database.watchDocument('users', 1, pollInterval: Duration.zero);
      }

      // Assert.
      expect(createWatcher, throwsArgumentError);
    });

    // Scenario: A watcher is configured not to emit its initial snapshot.
    // Covers:
    // - fireImmediately: false on document watchers.
    // - Later local changes still notifying the watcher.
    // Expected: The stream stays quiet until the document changes.
    test('supports fireImmediately false.', () async {
      // Arrange.
      final database = await openTestDatabaseInMemory();
      addTearDown(database.close);
      final events = <CindelDocument?>[];
      final subscription = database
          .watchDocument(
            'users',
            1,
            pollInterval: const Duration(milliseconds: 5),
            fireImmediately: false,
          )
          .listen(events.add);
      addTearDown(subscription.cancel);

      // Act.
      await Future<void>.delayed(const Duration(milliseconds: 40));
      await database.put('users', 1, {'name': 'Ana'});
      await _waitUntil(() => events.length == 1);

      // Assert.
      expect(events, [
        {'name': 'Ana'},
      ]);
    });

    // Scenario: Lazy watchers notify without returning document or collection data.
    // Covers:
    // - [CindelDatabase.watchDocumentLazy].
    // - [CindelDatabase.watchCollectionLazy].
    // - [CindelTypedCollection.watchObjectLazy].
    // Expected: Lazy streams emit void events after matching changes.
    test('supports object and collection lazy watchers.', () async {
      // Arrange.
      final database = await openTestDatabaseInMemory(schemas: [UserSchema]);
      addTearDown(database.close);
      var documentEvents = 0;
      var collectionEvents = 0;
      var typedObjectEvents = 0;
      final documentSubscription = database
          .watchDocumentLazy(
            'users',
            1,
            pollInterval: const Duration(milliseconds: 5),
          )
          .listen((_) => documentEvents += 1);
      final collectionSubscription = database
          .watchCollectionLazy(
            'users',
            pollInterval: const Duration(milliseconds: 5),
          )
          .listen((_) => collectionEvents += 1);
      final typedObjectSubscription = database.users
          .watchObjectLazy(1, pollInterval: const Duration(milliseconds: 5))
          .listen((_) => typedObjectEvents += 1);
      addTearDown(documentSubscription.cancel);
      addTearDown(collectionSubscription.cancel);
      addTearDown(typedObjectSubscription.cancel);

      // Act.
      await Future<void>.delayed(const Duration(milliseconds: 40));
      await database.put('users', 1, {'name': 'Ana'});
      await _waitUntil(
        () =>
            documentEvents == 1 &&
            collectionEvents == 1 &&
            typedObjectEvents == 1,
      );

      // Assert.
      expect(documentEvents, 1);
      expect(collectionEvents, 1);
      expect(typedObjectEvents, 1);
    });

    // Scenario: A typed query watcher observes only its visible result.
    // Covers:
    // - [CindelQuery.watch] initial query snapshot.
    // - Query result comparison after unrelated collection changes.
    // - [CindelQuery.watchLazy] emitting only when the visible query changes.
    // Expected: Writes outside the query do not emit; matching writes do emit.
    test(
      'emits query watcher events only when visible results change.',
      () async {
        // Arrange.
        final database = await openTestDatabaseInMemory(schemas: [UserSchema]);
        addTearDown(database.close);
        await database.users.put(_user(1, 'Ana', true));

        final queryEvents = <List<String>>[];
        var lazyEvents = 0;
        final query = database.users.filter().activeEqualTo(true).sortByName();
        final subscription = query
            .watch(pollInterval: const Duration(milliseconds: 5))
            .listen((users) {
              final names = users.map((user) => user.name).toList();
              queryEvents.add(names);
            });
        final lazySubscription = query
            .watchLazy(pollInterval: const Duration(milliseconds: 5))
            .listen((_) {
              lazyEvents += 1;
            });
        addTearDown(subscription.cancel);
        addTearDown(lazySubscription.cancel);

        // Act.
        await _waitUntil(() => queryEvents.length == 1);
        await database.users.put(_user(2, 'Ben', false));
        await Future<void>.delayed(const Duration(milliseconds: 60));
        await database.users.put(_user(3, 'Cid', true));
        await _waitUntil(() => queryEvents.length == 2 && lazyEvents == 1);

        // Assert.
        expect(queryEvents, [
          ['Ana'],
          ['Ana', 'Cid'],
        ]);
        expect(lazyEvents, 1);
      },
    );
  });
}

User _user(int id, String name, bool active) {
  return User()
    ..id = id
    ..name = name
    ..email = '$name@example.com'.toLowerCase()
    ..active = active;
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
