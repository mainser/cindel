import 'package:cindel/cindel.dart';
import 'package:test/test.dart';

import 'backend_test_support.dart';
import 'close_test_support_io.dart';
import 'schema_generation_fixture.dart';

void main() {
  group('Cindel MDBX progressive distinct', () {
    late String directory;
    late CindelDatabase database;

    setUp(() async {
      directory = await createCloseTestDirectory();
      addTearDown(() => deleteCloseTestDirectory(directory));
      database = await _open(directory);
      addTearDown(database.close);
      await database.apiProducts.putAll([
        for (var id = 1; id <= 96; id++)
          ApiProduct()
            ..dbId = id
            ..id = id % 3 == 0 ? null : 'group${id % 2}'
            ..name = 'Name ${(id * 37) % 11}',
      ]);
    });

    // Scenario: MDBX distinct runs over all, filtered and indexed candidate
    // sources.
    // Covers:
    // - Source order, composite distinct tuples and paginated results.
    // Expected: Each query retains the first expected representative and
    // every window matches the reference selection.
    test('preserves source order, filters, tuples and windows.', () async {
      // Arrange: use the inputs described in this scenario.
      // Act / Assert.
      for (final source in [
        database.apiProducts.all(),
        database.apiProducts.filter().dbIdGreaterThan(20),
        database.apiProducts.where().idEqualTo('group1'),
        database.apiProducts.where().idBetween('group0', 'group1'),
        database.apiProducts
            .where()
            .idBetween('group0', 'group1')
            .filter()
            .dbIdGreaterThan(20),
        database.apiProducts.where().idEqualTo('missing'),
      ]) {
        final rows = await source.findAll();
        for (final fields in [
          ['name'],
          ['id'],
          ['name', 'id'],
          ['dbId'],
        ]) {
          final seen = <Object?>{};
          final expected = rows.where((row) {
            final Object? key = switch (fields) {
              ['name'] => row.name,
              ['id'] => row.id,
              ['dbId'] => row.dbId,
              _ => (row.name, row.id),
            };
            return seen.add(key);
          }).toList();
          final distinct = source.distinctByFields(fields);
          await _expectRows(distinct, expected);
          for (final (offset, limit) in [(0, 1), (1, 3), (0, 0), (200, 1)]) {
            await _expectRows(
              distinct.offset(offset).limit(limit),
              expected.skip(offset).take(limit).toList(),
            );
          }
        }
      }
    });

    // Scenario: Composite fields contain separator-like text and nullable
    // values.
    // Covers:
    // - Tuple key boundaries, nullable representatives and non-null property
    // counts.
    // Expected: IDs 1, 2 and 4 survive, the final projected null is preserved
    // and counts distinguish rows from non-null values.
    test('preserves tuple boundaries and the first nullable value.', () async {
      // Arrange.
      await database.apiProducts.all().deleteAll();
      await database.apiProducts.putAll([
        for (final (id, name, value) in [
          (1, 'a\u0001String:b', 'c'),
          (2, 'a', 'b\u0001String:c'),
          (3, 'a\u0001String:b', 'c'),
          (4, 'nullable', null),
          (5, 'nullable', null),
        ])
          ApiProduct()
            ..dbId = id
            ..name = name
            ..id = value,
      ]);
      final query = database.apiProducts.all().distinctByFields(['name', 'id']);
      // Act / Assert.
      expect(await query.dbIdProperty().findAll(), [1, 2, 4]);
      expect(await query.offset(1).limit(2).idProperty().findAll(), [
        'b\u0001String:c',
        null,
      ]);
      expect(await query.count(), 3);
      expect(await query.idProperty().count(), 2);
      expect(await query.offset(2).idProperty().findFirst(), isNull);
    });

    // Scenario: Sorted distinct is queried while writes are pending and then
    // rolled back.
    // Covers:
    // - Ordered representatives, changed duplicate groups and transaction
    // visibility.
    // Expected: Sorted results match the reference selection and rollback
    // restores the original distinct IDs.
    test('keeps sorted distinct and pending writes correct.', () async {
      // Arrange.
      final query = database.apiProducts.all().distinctByName();
      final before = await query.dbIdProperty().findAll();
      final sorted = database.apiProducts.all().sortByDbIdDesc();
      final seen = <String>{};
      final expected = (await sorted.findAll())
          .where((row) => seen.add(row.name))
          .toList();
      // Act / Assert.
      await _expectRows(
        sorted.distinctByName().limit(3),
        expected.take(3).toList(),
      );
      await expectLater(
        database.writeTxn<void>(() async {
          await database.apiProducts.delete(1);
          await database.apiProducts.put(
            ApiProduct()
              ..dbId = 200
              ..name = 'New',
          );
          await database.apiProducts.put(
            ApiProduct()
              ..dbId = 2
              ..name = 'New',
          );
          final seen = <String>{};
          final expected = (await database.apiProducts.all().findAll())
              .where((row) => seen.add(row.name))
              .toList();
          await _expectRows(query, expected);
          expect(await query.dbIdProperty().findAll(), isNot(contains(200)));
          throw StateError('rollback');
        }),
        throwsStateError,
      );
      expect(await query.dbIdProperty().findAll(), before);
    });

    // Scenario: Another handle deletes a representative during a read
    // transaction.
    // Covers:
    // - Snapshot isolation for distinct queries.
    // Expected: The active snapshot keeps its old representatives; after it
    // ends the first visible ID is 2.
    test('keeps distinct within the read transaction snapshot.', () async {
      // Arrange.
      final other = await _open(directory);
      addTearDown(other.close);
      final query = database.apiProducts.all().distinctByName();
      // Act / Assert.
      await database.readTxn(() async {
        final before = await query.findAll();
        await other.apiProducts.delete(before.first.dbId);
        await _expectRows(query, before);
      });
      expect((await query.findFirst())?.dbId, 2);
    });
  });
}

Future<void> _expectRows(
  CindelQuery<ApiProduct> query,
  List<ApiProduct> expected,
) async {
  expect(
    (await query.findAll()).map((row) => row.dbId),
    expected.map((row) => row.dbId),
  );
  expect(await query.dbIdProperty().findAll(), expected.map((row) => row.dbId));
  expect(await query.idProperty().findAll(), expected.map((row) => row.id));
  expect(await query.properties(['dbId', 'name']).findAll(), [
    for (final row in expected) {'dbId': row.dbId, 'name': row.name},
  ]);
  expect((await query.findFirst())?.dbId, expected.firstOrNull?.dbId);
  expect(await query.idProperty().findFirst(), expected.firstOrNull?.id);
  expect(await query.count(), expected.length);
  expect(
    await query.idProperty().count(),
    expected.where((row) => row.id != null).length,
  );
  final ids = expected.map((row) => row.dbId).toList()..sort();
  final sum = ids.fold<int>(0, (total, id) => total + id);
  expect(await query.dbIdProperty().sum(), ids.isEmpty ? null : sum);
  expect(await query.dbIdProperty().min(), ids.firstOrNull);
  expect(await query.dbIdProperty().max(), ids.lastOrNull);
  expect(
    await query.dbIdProperty().average(),
    ids.isEmpty ? null : sum / ids.length,
  );
}

Future<CindelDatabase> _open(String directory) =>
    openTestDatabase(directory: directory, schemas: [ApiProductSchema]);
