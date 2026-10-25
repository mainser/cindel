import 'package:cindel/cindel.dart';
import 'package:test/test.dart';

import 'backend_test_support.dart';
import 'close_test_support_io.dart'
    if (dart.library.js_interop) 'close_test_support_web.dart';
import 'schema_generation_fixture.dart';

void main({bool includeSameDirectoryHandles = true}) {
  group('Cindel bulk ID allocation', () {
    late String directory;
    late CindelDatabase database;

    setUp(() async {
      directory = await createCloseTestDirectory();
      addTearDown(() => deleteCloseTestDirectory(directory));
      database = await _open(directory);
      addTearDown(() => database.close());
    });

    // Scenario: A large automatic-ID batch is followed by a mixed
    // automatic/manual batch.
    // Covers:
    // - Consecutive range reservation.
    // - explicit ID preservation.
    // - next-ID advancement.
    // Expected: The first batch gets 1..1000, the mixed batch gets
    // 1001/2000/1002 and the next insert gets 2001.
    test('putAll assigns consecutive IDs and preserves manual IDs.', () async {
      // Arrange.
      final batch = _products(1000);
      // Act.
      await database.apiProducts.putAll(batch);
      // Assert.
      expect(batch.map((item) => item.dbId), List.generate(1000, (i) => i + 1));
      expect((await database.apiProducts.get(1000))?.name, 'Product 999');
      final mixed = [
        ApiProduct()..name = 'Auto A',
        ApiProduct()
          ..dbId = 2000
          ..name = 'Manual',
        ApiProduct()..name = 'Auto B',
      ];
      await database.apiProducts.putAll(mixed);
      expect(mixed.map((item) => item.dbId), [1001, 2000, 1002]);
      final next = ApiProduct()..name = 'Next';
      await database.apiProducts.put(next);
      expect(next.dbId, 2001);
      expect((await database.apiProducts.get(1001))?.name, 'Auto A');
      expect((await database.apiProducts.get(1002))?.name, 'Auto B');
    });

    // Scenario: Empty operations and explicit-ID batches run before another
    // reservation.
    // Covers:
    // - Zero-count allocation and manual IDs without unnecessary automatic
    // reservations.
    // Expected: Empty requests consume no IDs; allocations return 1 and then
    // 41/42 after manual ID 40.
    test('empty and explicit batches do not reserve automatic IDs.', () async {
      // Arrange: use the inputs described in this scenario.
      // Act.
      await database.apiProducts.putAll([]);
      // Assert.
      expect(await database.allocateIds('apiProducts', 0), isEmpty);
      expect(await database.allocateId('apiProducts'), 1);
      await database.apiProducts.putAll([
        ApiProduct()
          ..dbId = 40
          ..name = 'Manual',
      ]);
      expect(await database.allocateIds('apiProducts', 2), [41, 42]);
    });

    // Scenario: IDs are reserved without inserting rows and the database is
    // reopened.
    // Covers:
    // - Persistent allocation high-water mark independent of stored
    // documents.
    // Expected: Reserving 1..3 makes the next typed batch receive IDs 4 and
    // 5.
    test('reservations persist without rows after reopening.', () async {
      // Arrange: use the inputs described in this scenario.
      // Act / Assert.
      expect(await database.allocateIds('apiProducts', 3), [1, 2, 3]);
      await database.close();
      database = await _open(directory);
      final batch = _products(2);
      await database.apiProducts.putAll(batch);
      expect(batch.map((item) => item.dbId), [4, 5]);
    });

    // Scenario: A write transaction inserts an automatic batch and then
    // aborts.
    // Covers:
    // - Atomic rollback of reserved ranges and written rows.
    // Expected: Rolled-back rows are absent and the next committed batch
    // reuses IDs 1 and 2.
    test('writeTxn rolls back the whole range and its rows.', () async {
      // Arrange: use the inputs described in this scenario.
      // Act / Assert.
      await expectLater(
        database.writeTxn<void>(() async {
          final batch = _products(3);
          await database.apiProducts.putAll(batch);
          expect(batch.map((item) => item.dbId), [1, 2, 3]);
          throw StateError('rollback');
        }),
        throwsStateError,
      );
      expect(await database.apiProducts.getAll([1, 2, 3]), [null, null, null]);
      final committed = _products(2);
      await database.writeTxn(() => database.apiProducts.putAll(committed));
      expect(committed.map((item) => item.dbId), [1, 2]);
      expect(await database.allocateId('apiProducts'), 3);
    });

    // Scenario: A batch contains valid automatic objects and duplicate
    // explicit IDs.
    // Covers:
    // - Failed implicit reservations versus reservations inside an explicit
    // transaction.
    // Expected: No rows survive either failure; implicit reservations stay
    // consumed while the explicit transaction restores its counter.
    test(
      'failed batch keeps implicit reservations but rolls back explicit ones.',
      () async {
        // Arrange.
        // Duplicate IDs fail after the automatic range has been reserved,
        // before either backend writes any rows.
        List<ApiProduct> invalidBatch() => [
          ..._products(2),
          ApiProduct()
            ..dbId = 40
            ..name = 'Duplicate A',
          ApiProduct()
            ..dbId = 40
            ..name = 'Duplicate B',
        ];
        // Act / Assert.
        await expectLater(
          database.apiProducts.putAll(invalidBatch()),
          throwsArgumentError,
        );
        expect(await database.apiProducts.getAll([1, 2, 40]), [
          null,
          null,
          null,
        ]);
        expect(await database.allocateId('apiProducts'), 3);
        await expectLater(
          database.writeTxn(() => database.apiProducts.putAll(invalidBatch())),
          throwsArgumentError,
        );
        expect(await database.allocateIds('apiProducts', 2), [4, 5]);
      },
    );

    // Scenario: A batch repeats the same object or collides with a manually
    // chosen ID.
    // Covers:
    // - Duplicate object identities and automatic/manual ID collisions.
    // Expected: Both batches fail with ArgumentError and the repeated object
    // is not persisted.
    test(
      'repeated objects and manual collisions still reject the batch.',
      () async {
        // Arrange.
        final repeated = ApiProduct()..name = 'Repeated';
        // Act / Assert.
        await expectLater(
          database.apiProducts.putAll([repeated, repeated]),
          throwsArgumentError,
        );
        expect(await database.apiProducts.get(repeated.dbId), isNull);
        await expectLater(
          database.writeTxn(() async {
            final next =
                (await database.allocateIds('apiProducts', 1)).single + 1;
            await database.apiProducts.putAll([
              ApiProduct()
                ..dbId = next
                ..name = 'Manual',
              ApiProduct()..name = 'Auto',
            ]);
          }),
          throwsArgumentError,
        );
      },
    );

    // Scenario: Allocation receives invalid counts or is attempted inside
    // readTxn.
    // Covers:
    // - Negative/overflow count validation and read-only transaction
    // enforcement.
    // Expected: RangeError or CindelTransactionError is raised without
    // consuming the next ID.
    test('invalid counts and read transactions cannot reserve IDs.', () async {
      // Arrange: use the inputs described in this scenario.
      // Act / Assert.
      for (final count in [-1, 0x100000000]) {
        await expectLater(
          database.allocateIds('apiProducts', count),
          throwsRangeError,
        );
      }
      await database.readTxn(() async {
        await expectLater(
          database.allocateIds('apiProducts', 2),
          throwsA(isA<CindelTransactionError>()),
        );
      });
      expect(await database.allocateId('apiProducts'), 1);
    });

    if (includeSameDirectoryHandles) {
      // Scenario: Two already-open handles insert automatic-ID batches
      // concurrently.
      // Covers:
      // - Transactional batch reservations across handles.
      // Expected: All 64 IDs are unique and consecutive, all rows are
      // readable and the next range is 65/66.
      test(
        'concurrent putAll calls on open handles use disjoint ranges.',
        () async {
          // Arrange.
          final other = await _open(directory);
          addTearDown(other.close);
          final first = _products(32);
          final second = _products(32);
          // Act.
          await Future.wait([
            database.apiProducts.putAll(first),
            other.apiProducts.putAll(second),
          ]);
          final ids = [...first, ...second].map((item) => item.dbId).toList()
            ..sort();
          // Assert.
          expect(ids, List.generate(64, (i) => i + 1));
          expect(await database.allocateIds('apiProducts', 2), [65, 66]);
          expect(
            (await other.apiProducts.getAll(
              ids,
            )).whereType<ApiProduct>().length,
            64,
          );
        },
      );
    }
  });
}

List<ApiProduct> _products(int count) =>
    List.generate(count, (i) => ApiProduct()..name = 'Product $i');

Future<CindelDatabase> _open(String directory) =>
    openTestDatabase(directory: directory, schemas: [ApiProductSchema]);
