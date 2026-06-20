import 'dart:async';
import 'dart:io';

import 'package:cindel/cindel.dart';
import 'package:test/test.dart';

import 'backend_test_support.dart';
import 'schema_generation_fixture.dart';

void main() {
  group('Cindel MDBX typed contract', () {
    test('persists and reopens generated typed objects.', () async {
      final directory = await Directory.systemTemp.createTemp(
        'cindel_mdbx_contract_',
      );
      addTearDown(() => directory.delete(recursive: true));
      var database = await openTestDatabase(
        directory: directory.path,
        schemas: [UserSchema],
      );
      addTearDown(() => database.close());
      final user = User()
        ..dbId = 1
        ..name = 'Ana'
        ..email = 'ana@example.com'
        ..active = true
        ..tags = ['typed', 'mdbx'];

      await database.users.put(user);
      expect(await database.schemaVersion('users'), 1);
      expect((await database.users.get(1))?.tags, ['typed', 'mdbx']);

      await database.close();
      database = await openTestDatabase(
        directory: directory.path,
        schemas: [UserSchema],
      );

      final reopened = await database.users.get(1);
      expect(reopened, isNotNull);
      expect(reopened!.name, 'Ana');
      expect(reopened.email, 'ana@example.com');
      expect(reopened.tags, ['typed', 'mdbx']);
      expect(await database.schemaVersion('users'), 1);
    });

    // Scenario: maintenance tooling walks a typed MDBX collection without
    // requesting the full id list.
    // Covers:
    // - Public `documentIdsPage` ordering and exclusive `afterId` cursor.
    // - Generated MDBX typed collection storage.
    // - Public argument validation before crossing FFI.
    // Expected: pages are stable, ascending, bounded, and end with an empty
    // page once the cursor reaches the last id.
    test('pages generated typed document ids.', () async {
      final database = await openTestDatabaseInMemory(schemas: [UserSchema]);
      addTearDown(database.close);

      await database.users.putAll([
        User()
          ..dbId = 3
          ..name = 'Cid'
          ..email = 'cid@example.com',
        User()
          ..dbId = 1
          ..name = 'Ana'
          ..email = 'ana@example.com',
        User()
          ..dbId = 5
          ..name = 'Eli'
          ..email = 'eli@example.com',
      ]);

      expect(await database.documentIdsPage('users', limit: 2), [1, 3]);
      expect(await database.documentIdsPage('users', afterId: 1, limit: 2), [
        3,
        5,
      ]);
      expect(
        await database.documentIdsPage('users', afterId: 5, limit: 2),
        isEmpty,
      );
      await expectLater(
        database.documentIdsPage('users', limit: 0),
        throwsArgumentError,
      );
    });

    test('commits and rolls back generated typed transactions.', () async {
      final database = await openTestDatabaseInMemory(schemas: [UserSchema]);
      addTearDown(database.close);

      final committed = await database.writeTxn(() async {
        await database.users.put(
          User()
            ..dbId = 1
            ..name = 'Ana'
            ..email = 'ana@example.com',
        );
        return database.users.get(1);
      });
      expect(committed?.name, 'Ana');

      await expectLater(
        database.writeTxn<void>(() async {
          await database.users.put(
            User()
              ..dbId = 2
              ..name = 'Ben'
              ..email = 'ben@example.com',
          );
          throw StateError('rollback');
        }),
        throwsA(isA<StateError>()),
      );
      expect(await database.users.get(2), isNull);

      final readBack = await database.readTxn(() {
        return database.users.get(1);
      });
      expect(readBack?.email, 'ana@example.com');
      await expectLater(
        database.readTxn<void>(() {
          return database.users.put(
            User()
              ..dbId = 3
              ..name = 'Cid'
              ..email = 'cid@example.com',
          );
        }),
        throwsA(isA<CindelTransactionError>()),
      );
      expect(await database.users.get(3), isNull);
    });

    test('keeps generated auto-increment allocation transactional.', () async {
      final database = await openTestDatabaseInMemory(schemas: [UserSchema]);
      addTearDown(database.close);
      final rolledBack = User()
        ..name = 'Ana'
        ..email = 'ana@example.com';

      await expectLater(
        database.writeTxn<void>(() async {
          await database.users.put(rolledBack);
          throw StateError('rollback');
        }),
        throwsA(isA<StateError>()),
      );

      final committed = User()
        ..name = 'Ben'
        ..email = 'ben@example.com';
      await database.users.put(committed);

      expect(rolledBack.dbId, 1);
      expect(committed.dbId, 1);
      expect((await database.users.get(1))?.name, 'Ben');
    });

    test('notifies generated typed watchers only after commit.', () async {
      final database = await openTestDatabaseInMemory(schemas: [UserSchema]);
      addTearDown(database.close);
      final collectionEvents = <List<User>>[];
      final objectEvents = <User?>[];
      final lazyEvents = <void>[];
      final collectionSubscription = database.users
          .watchCollection(pollInterval: const Duration(milliseconds: 5))
          .listen(collectionEvents.add);
      final objectSubscription = database.users
          .watchObject(1, pollInterval: const Duration(milliseconds: 5))
          .listen(objectEvents.add);
      final lazySubscription = database.users
          .watchCollectionLazy(pollInterval: const Duration(milliseconds: 5))
          .listen(lazyEvents.add);
      addTearDown(collectionSubscription.cancel);
      addTearDown(objectSubscription.cancel);
      addTearDown(lazySubscription.cancel);

      await _waitUntil(() => collectionEvents.length == 1);
      await _waitUntil(() => objectEvents.length == 1);
      final initialLazyEvents = lazyEvents.length;

      await expectLater(
        database.writeTxn<void>(() async {
          await database.users.put(
            User()
              ..dbId = 1
              ..name = 'Rolled back'
              ..email = 'rollback@example.com',
          );
          throw StateError('rollback');
        }),
        throwsA(isA<StateError>()),
      );
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(collectionEvents.single, isEmpty);
      expect(objectEvents.single, isNull);
      expect(lazyEvents.length, initialLazyEvents);

      await database.writeTxn<void>(() async {
        await database.users.put(
          User()
            ..dbId = 1
            ..name = 'Committed'
            ..email = 'committed@example.com',
        );
      });
      await _waitUntil(() => collectionEvents.any((users) => users.isNotEmpty));
      await _waitUntil(() => objectEvents.any((user) => user != null));
      await _waitUntil(() => lazyEvents.length > initialLazyEvents);

      expect(collectionEvents.last.single.name, 'Committed');
      expect(objectEvents.last?.email, 'committed@example.com');
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
      throw TimeoutException('Timed out waiting for condition.');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}
