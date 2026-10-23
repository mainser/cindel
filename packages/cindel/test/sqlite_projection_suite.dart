import 'package:cindel/cindel.dart';
import 'package:test/test.dart';

import 'backend_test_support.dart';
import 'close_test_support_io.dart'
    if (dart.library.js_interop) 'close_test_support_web.dart';
import 'schema_generation_fixture.dart';

void main({bool includeSameDirectoryHandles = true}) {
  group('Cindel SQLite projected values', () {
    late String directory;
    late CindelDatabase database;

    setUp(() async {
      directory = await createCloseTestDirectory();
      addTearDown(() => deleteCloseTestDirectory(directory));
      database = await _open(directory);
      addTearDown(() => database.close());
      await database.apiProducts.putAll([
        for (var id = 1; id <= 8; id++)
          ApiProduct()
            ..dbId = id
            ..id = id % 3 == 0 ? null : (id.isEven ? 'a' : 'b')
            ..name = 'Árbol ${id % 3}',
      ]);
    });

    test('projects and aggregates filtered and indexed windows.', () async {
      for (final source in [
        database.apiProducts.all(),
        database.apiProducts.all().filter().dbIdGreaterThan(3),
        database.apiProducts.where().idEqualTo('a'),
        database.apiProducts.where().idBetween('a', 'b'),
        database.apiProducts
            .where()
            .idBetween('a', 'b')
            .filter()
            .dbIdGreaterThan(3),
      ]) {
        final ordered = source.sortByNameDesc().thenByDbId();
        for (final query in [ordered, ordered.offset(1).limit(3)]) {
          final objects = await query.findAll();
          final ids = objects.map((object) => object.dbId).toList();
          final values = objects.map((object) => object.id).toList();
          final nonNull = values.nonNulls.toList()..sort();
          final sortedIds = ids.toList()..sort();
          expect(await query.dbIdProperty().findAll(), ids);
          expect(await query.idProperty().findAll(), values);
          expect(
            await query.nameProperty().findAll(),
            objects.map((object) => object.name),
          );
          expect(await query.idProperty().count(), nonNull.length);
          expect(await query.idProperty().min(), nonNull.firstOrNull);
          expect(await query.idProperty().max(), nonNull.lastOrNull);
          expect(await query.dbIdProperty().count(), ids.length);
          expect(await query.dbIdProperty().min(), sortedIds.firstOrNull);
          expect(await query.dbIdProperty().max(), sortedIds.lastOrNull);
          final sum = ids.fold<int>(0, (sum, id) => sum + id);
          expect(await query.dbIdProperty().sum(), ids.isEmpty ? null : sum);
          expect(
            await query.dbIdProperty().average(),
            ids.isEmpty ? null : sum / ids.length,
          );
        }
      }
    });

    test('keeps empty and all-null aggregate behavior.', () async {
      final all = database.apiProducts.all().sortByDbId();
      for (final query in [
        all.limit(0),
        all.offset(99),
        all.filter().dbIdGreaterThan(99),
      ]) {
        expect(await query.dbIdProperty().findAll(), isEmpty);
        expect(await query.dbIdProperty().count(), 0);
        expect(await query.dbIdProperty().min(), isNull);
        expect(await query.dbIdProperty().max(), isNull);
        expect(await query.dbIdProperty().sum(), isNull);
        expect(await query.dbIdProperty().average(), isNull);
      }
      final nulls = all.filter().idEqualTo(null).idProperty();
      expect(await nulls.findAll(), [null, null]);
      expect(await nulls.count(), 0);
      expect(await nulls.min(), isNull);
      expect(await nulls.max(), isNull);
      expect(await nulls.sum(), isNull);
      expect(await nulls.average(), isNull);
    });

    test('preserves distinct representatives and their window.', () async {
      final distinct = database.apiProducts.all().sortByName().distinctByName();
      for (final query in [distinct, distinct.offset(1).limit(1)]) {
        final objects = await query.findAll();
        expect(
          await query.nameProperty().findAll(),
          objects.map((object) => object.name),
        );
        expect(
          await query.dbIdProperty().findAll(),
          objects.map((object) => object.dbId),
        );
        expect(
          await query.dbIdProperty().sum(),
          objects.fold<int>(0, (sum, object) => sum + object.dbId),
        );
      }
    });

    test('reads pending changes and respects rollback and reopen.', () async {
      final ids = database.apiProducts.all().sortByDbId().dbIdProperty();
      await expectLater(
        database.writeTxn<void>(() async {
          await database.apiProducts.delete(1);
          await database.apiProducts.put(
            ApiProduct()
              ..dbId = 20
              ..name = 'New',
          );
          await database.apiProducts.put(
            ApiProduct()
              ..dbId = 2
              ..id = 'updated'
              ..name = 'Updated',
          );
          expect(await ids.findAll(), [2, 3, 4, 5, 6, 7, 8, 20]);
          expect(await ids.sum(), 55);
          expect(
            await database.apiProducts
                .all()
                .filter()
                .dbIdEqualTo(2)
                .idProperty()
                .findAll(),
            ['updated'],
          );
          throw StateError('rollback');
        }),
        throwsStateError,
      );
      expect(await ids.sum(), 36);
      await database.writeTxn(() => database.apiProducts.delete(1));
      await database.close();
      database = await _open(directory);
      expect(
        await database.apiProducts.all().sortByDbId().dbIdProperty().findAll(),
        [2, 3, 4, 5, 6, 7, 8],
      );
      expect(await database.apiProducts.all().dbIdProperty().sum(), 35);
    });

    if (includeSameDirectoryHandles) {
      test('projects and aggregates from the active read snapshot.', () async {
        final other = await _open(directory);
        addTearDown(other.close);
        final ids = database.apiProducts.all().sortByDbId().dbIdProperty();
        await database.readTxn(() async {
          expect(await ids.sum(), 36);
          await other.writeTxn(() => other.apiProducts.delete(1));
          expect(await ids.findAll(), [1, 2, 3, 4, 5, 6, 7, 8]);
          expect(await ids.sum(), 36);
        });
        expect(await ids.sum(), 35);
      });
    }
  });
}

Future<CindelDatabase> _open(String directory) =>
    openTestDatabase(directory: directory, schemas: [ApiProductSchema]);
