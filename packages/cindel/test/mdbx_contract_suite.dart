import 'dart:async';
import 'dart:io';

import 'package:cindel/cindel.dart';
import 'package:test/test.dart';

import 'backend_test_support.dart';
import 'schema_generation_fixture.dart';

void main() {
  group('Cindel MDBX typed contract', () {
    test('filters and sorts int64 durations without rounding.', () async {
      final database = await openTestDatabaseInMemory(schemas: [UserSchema]);
      addTearDown(database.close);
      for (final low in [
        // The compact native format reserves int64 minimum for null.
        -9223372036854775807,
        -9007199254740993,
        9007199254740992,
        9223372036854775806,
      ]) {
        await database.users.all().deleteAll();
        final lower = Duration(microseconds: low);
        final upper = Duration(microseconds: low + 1);
        await database.users.putAll([
          User()
            ..dbId = 1
            ..name = 'Higher'
            ..email = 'high@test'
            ..sessionLength = upper,
          User()
            ..dbId = 2
            ..name = 'Lower'
            ..email = 'low@test'
            ..sessionLength = lower,
        ]);
        expect(
          (await database.users
                  .filter()
                  .sessionLengthGreaterThan(lower)
                  .findAll())
              .map((user) => user.dbId),
          [1],
        );
        expect(
          (await database.users.filter().sessionLengthLessThan(upper).findAll())
              .map((user) => user.dbId),
          [2],
        );
        expect(
          await database.users.filter().sessionLengthGreaterThan(lower).count(),
          1,
        );
        Future<void> checkSorts() async {
          expect(
            (await database.users.all().sortBy('sessionLength').findAll()).map(
              (user) => user.dbId,
            ),
            [2, 1],
          );
          expect(
            (await database.users
                    .all()
                    .sortBy('sessionLength', order: CindelSortOrder.descending)
                    .findAll())
                .map((user) => user.dbId),
            [1, 2],
          );
          expect(
            (await database.users
                    .all()
                    .sortBy('sessionLength')
                    .offset(1)
                    .limit(1)
                    .findAll())
                .single
                .dbId,
            1,
          );
        }

        await checkSorts();
        await database.writeTxn(checkSorts);
      }
    });

    test(
      'preserves adjacent DateTime microseconds beyond double precision.',
      () async {
        final database = await openTestDatabaseInMemory(schemas: [UserSchema]);
        addTearDown(database.close);
        final lower = DateTime.fromMicrosecondsSinceEpoch(
          9007199254740992,
          isUtc: true,
        );
        final upper = DateTime.fromMicrosecondsSinceEpoch(
          9007199254740993,
          isUtc: true,
        );
        await database.users.putAll([
          User()
            ..dbId = 1
            ..name = 'Higher'
            ..email = 'high@test'
            ..createdAt = upper,
          User()
            ..dbId = 2
            ..name = 'Lower'
            ..email = 'low@test'
            ..createdAt = lower,
        ]);
        expect(
          (await database.users.filter().createdAtGreaterThan(lower).findAll())
              .map((user) => user.dbId),
          [1],
        );
        expect(
          (await database.users.all().sortBy('createdAt').findAll()).map(
            (user) => user.dbId,
          ),
          [2, 1],
        );
        await database.writeTxn(() async {
          expect(
            (await database.users.all().sortBy('createdAt').findAll()).map(
              (user) => user.dbId,
            ),
            [2, 1],
          );
        });
      },
    );

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

    for (final rollback in [false, true]) {
      test(
        'keeps readTxn snapshot isolated until ${rollback ? 'rollback' : 'commit'}.',
        () async {
          final (reader, writer, _) = await _openSharedDatabases();
          await writer.users.put(_user('Before', id: 1));
          await writer.users.put(_user('Deleted', id: 2));

          Future<void> checkSnapshot() async {
            // The snapshot must exist before the callback's first read.
            await writer.writeTxn(() async {
              await writer.users.put(_user('After', id: 1));
              await writer.users.delete(2);
              await writer.users.put(_user('Inserted', id: 3));
            });
            expect((await reader.users.get(1))?.name, 'Before');
            expect(
              (await reader.users.getAll([1, 2, 3])).map((user) => user?.name),
              ['Before', 'Deleted', null],
            );
            expect(
              (await reader.users.all().findAll()).map((user) => user.name),
              ['Before', 'Deleted'],
            );
            expect(
              (await reader.users.all().sortBy('name').findAll()).map(
                (user) => user.name,
              ),
              ['Before', 'Deleted'],
            );
            expect(
              (await reader.users
                      .where()
                      .emailEqualTo('Before@example.com')
                      .findAll())
                  .single
                  .name,
              'Before',
            );
            expect(
              (await reader.users.where().emailBetween('A', 'Z').findAll()).map(
                (user) => user.name,
              ),
              ['Before', 'Deleted'],
            );
            expect(await reader.users.all().count(), 2);
            expect(await reader.users.all().nameProperty().findAll(), [
              'Before',
              'Deleted',
            ]);
            expect(await reader.users.all().dbIdProperty().sum(), 3);
            expect(
              await reader.users
                  .all()
                  .distinctBy('name')
                  .nameProperty()
                  .findAll(),
              ['Before', 'Deleted'],
            );
            expect(await reader.documentIdsPage('users', limit: 10), [1, 2]);
            // A second commit must not advance the original snapshot either.
            await writer.users.put(_user('Latest', id: 1));
            expect((await reader.users.get(1))?.name, 'Before');
            if (rollback) throw StateError('rollback snapshot');
          }

          if (rollback) {
            await expectLater(reader.readTxn(checkSnapshot), throwsStateError);
          } else {
            await reader.readTxn(checkSnapshot);
          }
          expect((await reader.users.get(1))?.name, 'Latest');
          expect(await reader.documentIds('users'), [1, 3]);
          await reader.readTxn(() async {
            expect((await reader.users.get(1))?.name, 'Latest');
          });
        },
      );
    }

    test(
      'reserves auto IDs across overlapping writeTxn callbacks and implicit writes.',
      () async {
        final (first, second, directory) = await _openSharedDatabases();
        final outer = _user('Outer');
        final inner = _user('Inner');
        final implicit = _user('Implicit');
        final batch = [_user('Batch A'), _user('Batch B')];
        await first.writeTxn(() async {
          await first.users.put(outer);
          await second.writeTxn(() => second.users.put(inner));
          await second.users.put(implicit);
          await first.users.putAll(batch);
        });

        expect(
          [
            outer.dbId,
            inner.dbId,
            implicit.dbId,
            ...batch.map((user) => user.dbId),
          ],
          [1, 2, 3, 4, 5],
        );
        expect((await first.users.all().findAll()).map((user) => user.name), [
          'Outer',
          'Inner',
          'Implicit',
          'Batch A',
          'Batch B',
        ]);
        await first.close();
        await second.close();
        final reopened = await openTestDatabase(
          directory: directory.path,
          schemas: [UserSchema],
        );
        addTearDown(reopened.close);
        final next = _user('Next');
        await reopened.users.put(next);
        expect(next.dbId, 6);
        expect(await reopened.users.all().count(), 6);
      },
    );

    test(
      'rollback preserves IDs committed by an overlapping writeTxn.',
      () async {
        final (first, second, _) = await _openSharedDatabases();
        final rolledBack = _user('Rolled back');
        final committed = _user('Committed');
        await expectLater(
          first.writeTxn<void>(() async {
            await first.users.put(rolledBack);
            await second.writeTxn(() => second.users.put(committed));
            throw StateError('rollback');
          }),
          throwsStateError,
        );

        expect(rolledBack.dbId, 1);
        expect(committed.dbId, 2);
        expect(await first.users.get(1), isNull);
        expect((await first.users.get(2))?.name, 'Committed');
        final next = _user('Next');
        await first.users.put(next);
        expect(next.dbId, 3);
      },
    );

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

User _user(String name, {int id = autoIncrement}) => User()
  ..dbId = id
  ..name = name
  ..email = '$name@example.com';

Future<(CindelDatabase, CindelDatabase, Directory)>
_openSharedDatabases() async {
  final directory = await Directory.systemTemp.createTemp('cindel_mdbx_txn_');
  addTearDown(() => directory.delete(recursive: true));
  final first = await openTestDatabase(
    directory: directory.path,
    schemas: [UserSchema],
  );
  addTearDown(first.close);
  final second = await openTestDatabase(
    directory: directory.path,
    schemas: [UserSchema],
  );
  addTearDown(second.close);
  return (first, second, directory);
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
