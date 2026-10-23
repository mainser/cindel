import 'package:cindel/cindel.dart';
import 'package:test/test.dart';

import 'backend_test_support.dart';
import 'close_test_support_io.dart';
import 'schema_generation_fixture.dart';

void main() {
  group('Cindel MDBX partial selection', () {
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

    test(
      'matches full ordering for limited objects and projections.',
      () async {
        for (final source in [
          database.apiProducts.all(),
          database.apiProducts.where().idEqualTo('group1'),
          database.apiProducts
              .where()
              .idBetween('group0', 'group1')
              .filter()
              .dbIdGreaterThan(20),
        ]) {
          for (final ordered in [
            source.sortByDbIdDesc(),
            source.sortByName().thenByDbIdDesc(),
            source.sortByIdDesc().thenByName().thenByDbId(),
          ]) {
            for (final (offset, limit) in [
              (0, 1),
              (3, 7),
              (0, 0),
              (95, 8),
              (0, 96),
              (1000, 2),
            ]) {
              await _expectWindow(ordered, offset, limit);
            }
          }
        }
      },
    );

    test(
      'preserves full-sort results without an ID key and with distinct.',
      () async {
        for (final ordered in [
          database.apiProducts.all().sortByName(),
          database.apiProducts.all().sortByName().thenByDbId().distinctByName(),
        ]) {
          await _expectWindow(ordered, 1, 4);
          await _expectWindow(ordered, 0, 1);
        }
      },
    );

    test('preserves pending writes and rollback.', () async {
      final ordered = database.apiProducts.all().sortByName().thenByDbId();
      final original = await ordered.dbIdProperty().findAll();
      await expectLater(
        database.writeTxn<void>(() async {
          await database.apiProducts.delete(1);
          await database.apiProducts.put(
            ApiProduct()
              ..dbId = 200
              ..name = 'First',
          );
          await database.apiProducts.put(
            ApiProduct()
              ..dbId = 2
              ..name = 'Last',
          );
          await _expectWindow(ordered, 0, 5);
          expect((await ordered.findFirst())?.dbId, 200);
          throw StateError('rollback');
        }),
        throwsStateError,
      );
      expect(await ordered.dbIdProperty().findAll(), original);
      await _expectWindow(ordered, 0, 5);
    });

    test('keeps the read snapshot while another handle commits.', () async {
      final other = await _open(directory);
      addTearDown(other.close);
      final ordered = database.apiProducts.all().sortByName().thenByDbId();
      await database.readTxn(() async {
        final before = await ordered.limit(5).dbIdProperty().findAll();
        await other.writeTxn(() async {
          await other.apiProducts.delete(before.first);
          await other.apiProducts.put(
            ApiProduct()
              ..dbId = 200
              ..name = 'First',
          );
        });
        expect(await ordered.limit(5).dbIdProperty().findAll(), before);
        await _expectWindow(ordered, 0, 5);
      });
      expect((await ordered.findFirst())?.dbId, 200);
      await _expectWindow(ordered, 1, 5);
    });
  });
}

Future<void> _expectWindow(
  CindelQuery<ApiProduct> ordered,
  int offset,
  int limit,
) async {
  final expected = (await ordered.findAll()).skip(offset).take(limit).toList();
  final window = ordered.offset(offset).limit(limit);
  expect(
    (await window.findAll()).map((row) => row.dbId),
    expected.map((row) => row.dbId),
  );
  expect(
    await window.dbIdProperty().findAll(),
    expected.map((row) => row.dbId),
  );
  expect(await window.idProperty().findAll(), expected.map((row) => row.id));
  expect(
    await window.nameProperty().findAll(),
    expected.map((row) => row.name),
  );
  expect(await window.properties(['dbId', 'name']).findAll(), [
    for (final row in expected) {'dbId': row.dbId, 'name': row.name},
  ]);
  expect((await window.findFirst())?.dbId, expected.firstOrNull?.dbId);
  expect(await window.nameProperty().findFirst(), expected.firstOrNull?.name);
  expect(
    await window.dbIdProperty().sum(),
    expected.isEmpty
        ? null
        : expected.fold<int>(0, (sum, row) => sum + row.dbId),
  );
}

Future<CindelDatabase> _open(String directory) =>
    openTestDatabase(directory: directory, schemas: [ApiProductSchema]);
