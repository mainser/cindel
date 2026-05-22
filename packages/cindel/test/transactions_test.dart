import 'dart:async';
import 'dart:io';

import 'package:cindel/cindel.dart';
import 'package:test/test.dart';

import 'schema_generation_fixture.dart';

void main() {
  group('Cindel transactions', () {
    // Scenario: Multiple writes are committed through the public transaction
    // wrapper.
    // Covers:
    // - [CindelDatabase.writeTxn].
    // - Reads performed after commit.
    // Expected: Every write inside the transaction is persisted together.
    test('commits write transactions.', () async {
      // Arrange.
      final database = await Cindel.openInMemory();
      addTearDown(database.close);

      // Act.
      final result = await database.writeTxn(() async {
        await database.put('users', 1, {'name': 'Ana'});
        await database.put('users', 2, {'name': 'Ben'});
        return 'done';
      });

      // Assert.
      expect(result, 'done');
      expect(await database.get('users', 1), {'name': 'Ana'});
      expect(await database.get('users', 2), {'name': 'Ben'});
    });

    // Scenario: A write transaction throws after a successful first write.
    // Covers:
    // - Native rollback through [CindelDatabase.writeTxn].
    // - Partial write cleanup after user-code failures.
    // Expected: No document from the failed transaction remains persisted.
    test('rolls back failed write transactions.', () async {
      // Arrange.
      final database = await Cindel.openInMemory();
      addTearDown(database.close);

      // Act.
      final result = database.writeTxn<void>(() async {
        await database.put('users', 1, {'name': 'Ana'});
        throw StateError('stop');
      });

      // Assert.
      await expectLater(result, throwsA(isA<StateError>()));
      expect(await database.get('users', 1), isNull);
    });

    // Scenario: Auto-increment ids are allocated inside a failed transaction.
    // Covers:
    // - Native id counter writes inside the active transaction.
    // - Rollback of generated typed object writes.
    // Expected: A later successful write can reuse the rolled-back first id.
    test('rolls back typed auto-increment writes and id allocation.', () async {
      // Arrange.
      final database = await Cindel.openInMemory(schemas: [UserSchema]);
      addTearDown(database.close);
      final rolledBackUser = User()
        ..name = 'Ana'
        ..email = 'ana@example.com';

      // Act.
      await expectLater(
        database.writeTxn<void>(() async {
          await database.users.put(rolledBackUser);
          throw StateError('stop');
        }),
        throwsA(isA<StateError>()),
      );
      final savedUser = User()
        ..name = 'Ben'
        ..email = 'ben@example.com';
      await database.users.put(savedUser);

      // Assert.
      expect(rolledBackUser.id, 1);
      expect(savedUser.id, 1);
      expect(await database.users.get(rolledBackUser.id), isNotNull);
    });

    // Scenario: Reads are wrapped in an explicit read transaction.
    // Covers:
    // - [CindelDatabase.readTxn].
    // - Write rejection inside read transactions.
    // Expected: Reads work and attempted writes fail before native mutation.
    test('allows reads and rejects writes inside read transactions.', () async {
      // Arrange.
      final database = await Cindel.openInMemory();
      addTearDown(database.close);
      await database.put('users', 1, {'name': 'Ana'});

      // Act.
      final storedUser = await database.readTxn(() {
        return database.get('users', 1);
      });
      final writeResult = database.readTxn<void>(() {
        return database.put('users', 2, {'name': 'Ben'});
      });

      // Assert.
      expect(storedUser, {'name': 'Ana'});
      await expectLater(writeResult, throwsA(isA<StateError>()));
      expect(await database.get('users', 2), isNull);
    });

    // Scenario: A transaction is requested while another is active.
    // Covers:
    // - Public nested transaction guard.
    // Expected: Cindel rejects nested transactions for now.
    test('rejects nested transactions.', () async {
      // Arrange.
      final database = await Cindel.openInMemory();
      addTearDown(database.close);

      // Act.
      final result = database.writeTxn<void>(() {
        return database.readTxn(() async {});
      });

      // Assert.
      await expectLater(result, throwsA(isA<StateError>()));
    });

    // Scenario: A collection watcher is active during a write transaction.
    // Covers:
    // - Deferred local watcher notifications.
    // - Polling suspension while this database handle has an active
    //   transaction.
    // Expected: The watcher emits the committed snapshot only after commit.
    test('notifies watchers only after successful commit.', () async {
      // Arrange.
      final database = await Cindel.openInMemory();
      addTearDown(database.close);
      final events = <List<CindelDocument>>[];
      final subscription = database
          .watchCollection(
            'users',
            pollInterval: const Duration(milliseconds: 5),
          )
          .listen(events.add);
      addTearDown(subscription.cancel);
      await _waitUntil(() => events.length == 1);

      // Act.
      await database.writeTxn<void>(() async {
        await database.put('users', 1, {'name': 'Ana'});
        await Future<void>.delayed(const Duration(milliseconds: 40));
        expect(events.length, 1);
        expect(events.single, isEmpty);
      });
      await _waitUntil(() => events.length == 2);

      // Assert.
      expect(events.first, isEmpty);
      expect(events.last, [
        {'name': 'Ana'},
      ]);
    });

    // Scenario: A watcher is active during a failed write transaction.
    // Covers:
    // - Rollback notification suppression.
    // Expected: The watcher never receives a snapshot for rolled-back writes.
    test('does not notify watchers after rollback.', () async {
      // Arrange.
      final database = await Cindel.openInMemory();
      addTearDown(database.close);
      final events = <List<CindelDocument>>[];
      final subscription = database
          .watchCollection(
            'users',
            pollInterval: const Duration(milliseconds: 5),
          )
          .listen(events.add);
      addTearDown(subscription.cancel);
      await _waitUntil(() => events.length == 1);

      // Act.
      await expectLater(
        database.writeTxn<void>(() async {
          await database.put('users', 1, {'name': 'Ana'});
          throw StateError('stop');
        }),
        throwsA(isA<StateError>()),
      );
      await Future<void>.delayed(const Duration(milliseconds: 40));

      // Assert.
      expect(events.length, 1);
      expect(events.single, isEmpty);
      expect(await database.get('users', 1), isNull);
    });

    // Scenario: MDBX is selected explicitly and used through public
    // transaction wrappers.
    // Covers:
    // - [CindelStorageBackend.mdbx] through FFI.
    // - [CindelDatabase.writeTxn] commit and rollback on MDBX.
    // - Native id counter rollback through the selected backend.
    // Expected: MDBX matches the public transaction behavior currently
    //   provided by SQLite.
    test(
      'supports transactions with an explicit MDBX backend.',
      () async {
        // Arrange.
        final database = await Cindel.openInMemory(
          schemas: [UserSchema],
          backend: CindelStorageBackend.mdbx,
        );
        addTearDown(database.close);

        // Act.
        await database.writeTxn<void>(() async {
          await database.put('users', 1, {'name': 'Ana'});
        });
        await expectLater(
          database.writeTxn<void>(() async {
            await database.users.put(
              User()
                ..name = 'Ben'
                ..email = 'ben@example.com',
            );
            throw StateError('stop');
          }),
          throwsA(isA<StateError>()),
        );
        final savedUser = User()
          ..name = 'Cid'
          ..email = 'cid@example.com';
        await database.users.put(savedUser);

        // Assert.
        expect(await database.get('users', 1), {'name': 'Ana'});
        expect(savedUser.id, 2);
        expect(await database.users.get(savedUser.id), isNotNull);
      },
      skip: !_runMdbxBackendTests
          ? 'Requires CINDEL_TEST_MDBX=1 and a native library built with mdbx.'
          : false,
    );
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

bool get _runMdbxBackendTests {
  return Platform.environment['CINDEL_TEST_MDBX'] == '1';
}
