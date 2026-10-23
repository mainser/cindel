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

    test('putAll assigns consecutive IDs and preserves manual IDs.', () async {
      final batch = _products(1000);
      await database.apiProducts.putAll(batch);
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

    test('empty and explicit batches do not reserve automatic IDs.', () async {
      await database.apiProducts.putAll([]);
      expect(await database.allocateIds('apiProducts', 0), isEmpty);
      expect(await database.allocateId('apiProducts'), 1);
      await database.apiProducts.putAll([
        ApiProduct()
          ..dbId = 40
          ..name = 'Manual',
      ]);
      expect(await database.allocateIds('apiProducts', 2), [41, 42]);
    });

    test('reservations persist without rows after reopening.', () async {
      expect(await database.allocateIds('apiProducts', 3), [1, 2, 3]);
      await database.close();
      database = await _open(directory);
      final batch = _products(2);
      await database.apiProducts.putAll(batch);
      expect(batch.map((item) => item.dbId), [4, 5]);
    });

    test('writeTxn rolls back the whole range and its rows.', () async {
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

    test(
      'failed batch keeps implicit reservations but rolls back explicit ones.',
      () async {
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

    test(
      'repeated objects and manual collisions still reject the batch.',
      () async {
        final repeated = ApiProduct()..name = 'Repeated';
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

    test('invalid counts and read transactions cannot reserve IDs.', () async {
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
      test(
        'concurrent putAll calls on open handles use disjoint ranges.',
        () async {
          final other = await _open(directory);
          addTearDown(other.close);
          final first = _products(32);
          final second = _products(32);
          await Future.wait([
            database.apiProducts.putAll(first),
            other.apiProducts.putAll(second),
          ]);
          final ids = [...first, ...second].map((item) => item.dbId).toList()
            ..sort();
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
