import 'package:cindel/cindel.dart';
import 'package:test/test.dart';

import 'backend_test_support.dart';
import 'close_test_support_io.dart';
import 'schema_generation_fixture.dart';

void main() {
  group('Cindel MDBX direct ID scan', () {
    late String directory;
    late CindelDatabase database;
    const ids = [1, 7, 255, 256, 65536, 9007199254740992, 9007199254740993];

    setUp(() async {
      directory = await createCloseTestDirectory();
      addTearDown(() => deleteCloseTestDirectory(directory));
      database = await _open(directory);
      addTearDown(database.close);
      await database.apiProducts.putAll([
        for (final id in ids.reversed)
          ApiProduct()
            ..dbId = id
            ..id = 'same'
            ..name = 'Name $id',
      ]);
    });

    test(
      'reads sparse 64-bit IDs and projections in both directions.',
      () async {
        for (final ascending in [true, false]) {
          final ordered = ascending
              ? database.apiProducts.all().sortByDbId()
              : database.apiProducts.all().sortByDbIdDesc();
          final expected = ascending ? ids : ids.reversed.toList();
          for (final (offset, limit) in [
            (0, 1),
            (2, 3),
            (0, 0),
            (6, 9),
            (0, 7),
            (20, 1),
          ]) {
            await _expectIds(
              ordered.offset(offset).limit(limit),
              expected.skip(offset).take(limit).toList(),
            );
          }
        }
        await database.apiProducts.deleteAll(ids);
        await _expectIds(database.apiProducts.all().sortByDbId().limit(2), []);
        await _expectIds(
          database.apiProducts.all().sortByDbIdDesc().limit(2),
          [],
        );
      },
    );

    test(
      'preserves filters, indexes, distinct and additional sort keys.',
      () async {
        await _expectIds(
          database.apiProducts
              .all()
              .filter()
              .dbIdLessThan(256)
              .sortByDbIdDesc()
              .limit(2),
          [255, 7],
        );
        await _expectIds(
          database.apiProducts
              .where()
              .idEqualTo('missing')
              .sortByDbIdDesc()
              .limit(2),
          [],
        );
        await _expectIds(
          database.apiProducts.all().sortByDbIdDesc().distinctById().limit(2),
          [ids.last],
        );
        await _expectIds(
          database.apiProducts
              .all()
              .sortByDbId()
              .thenByNameDesc()
              .offset(1)
              .limit(2),
          [7, 255],
        );
      },
    );

    test(
      'includes pending writes and restores results after rollback.',
      () async {
        await expectLater(
          database.writeTxn<void>(() async {
            await database.apiProducts.delete(1);
            await database.apiProducts.delete(ids.last);
            await database.apiProducts.put(
              ApiProduct()
                ..dbId = 2
                ..name = 'Name 2',
            );
            await _expectIds(database.apiProducts.all().sortByDbId().limit(2), [
              2,
              7,
            ]);
            await _expectIds(
              database.apiProducts.all().sortByDbIdDesc().limit(2),
              [ids[5], 65536],
            );
            throw StateError('rollback');
          }),
          throwsStateError,
        );
        await _expectIds(database.apiProducts.all().sortByDbId().limit(2), [
          1,
          7,
        ]);
        await _expectIds(database.apiProducts.all().sortByDbIdDesc().limit(2), [
          ids.last,
          ids[5],
        ]);
      },
    );

    test('keeps both directions on the read transaction snapshot.', () async {
      final other = await _open(directory);
      addTearDown(other.close);
      await database.readTxn(() async {
        await other.writeTxn(() async {
          await other.apiProducts.delete(1);
          await other.apiProducts.delete(ids.last);
        });
        await _expectIds(database.apiProducts.all().sortByDbId().limit(2), [
          1,
          7,
        ]);
        await _expectIds(database.apiProducts.all().sortByDbIdDesc().limit(2), [
          ids.last,
          ids[5],
        ]);
      });
      await _expectIds(database.apiProducts.all().sortByDbId().limit(2), [
        7,
        255,
      ]);
      await _expectIds(database.apiProducts.all().sortByDbIdDesc().limit(2), [
        ids[5],
        65536,
      ]);
    });
  });
}

Future<void> _expectIds(CindelQuery<ApiProduct> query, List<int> ids) async {
  expect((await query.findAll()).map((row) => row.dbId), ids);
  expect(await query.dbIdProperty().findAll(), ids);
  expect(await query.nameProperty().findAll(), [
    for (final id in ids) 'Name $id',
  ]);
  expect(await query.properties(['dbId', 'name']).findAll(), [
    for (final id in ids) {'dbId': id, 'name': 'Name $id'},
  ]);
  expect((await query.findFirst())?.dbId, ids.firstOrNull);
  expect(await query.dbIdProperty().findFirst(), ids.firstOrNull);
}

Future<CindelDatabase> _open(String directory) =>
    openTestDatabase(directory: directory, schemas: [ApiProductSchema]);
