import 'package:cindel/cindel.dart';
import 'package:test/test.dart';

import 'backend_test_support.dart';
import 'close_test_support_io.dart'
    if (dart.library.js_interop) 'close_test_support_web.dart';
import 'schema_generation_fixture.dart';

void main({bool includeSameDirectoryHandles = true}) {
  group('Cindel optimized count', () {
    late String directory;
    late CindelDatabase database;

    setUp(() async {
      directory = await createCloseTestDirectory();
      addTearDown(() => deleteCloseTestDirectory(directory));
      database = await _open(directory);
      addTearDown(() => database.close());
      await database.apiProducts.putAll([
        for (var id = 1; id <= 10; id++)
          ApiProduct()
            ..dbId = id
            ..id = id % 3 == 0 ? null : (id.isEven ? 'a' : 'b')
            ..name = 'Name ${id % 4}',
      ]);
    });

    // Scenario: Ten seeded products are counted through unordered and ordered
    // queries.
    // Covers:
    // - Offset/limit cardinality, empty windows and query reuse.
    // Expected: Counts follow the selected window, clamp at the collection
    // end and leave the original count at ten.
    test('counts the window with and without ordering.', () async {
      // Arrange: use the inputs described in this scenario.
      // Act / Assert.
      for (final query in [
        database.apiProducts.all(),
        database.apiProducts.all().sortByNameDesc().thenByDbId(),
      ]) {
        expect(await query.count(), 10);
        expect(await query.offset(3).count(), 7);
        expect(await query.limit(0).count(), 0);
        expect(await query.offset(3).limit(0).count(), 0);
        expect(await query.offset(3).limit(4).count(), 4);
        expect(await query.offset(9).limit(4).count(), 1);
        expect(await query.offset(10).count(), 0);
        expect(await query.offset(100).limit(4).count(), 0);
        expect(await query.count(), 10);
      }
    });

    // Scenario: Scalar filters and indexed sources are combined with ordering
    // and pagination.
    // Covers:
    // - Optimized counts for filtered equality/range query shapes.
    // Expected: Every count equals the length of the same query window
    // returned by findAll.
    test('preserves filtered and indexed source cardinality.', () async {
      // Arrange: use the inputs described in this scenario.
      // Act / Assert.
      for (final query in [
        database.apiProducts.all().filter().dbIdGreaterThan(4),
        database.apiProducts.all().filter().nameEqualTo('Name 1'),
        database.apiProducts.where().idEqualTo('a'),
        database.apiProducts.where().idBetween('a', 'b'),
        database.apiProducts.where().idEqualTo('missing'),
        database.apiProducts
            .where()
            .idBetween('a', 'b')
            .filter()
            .dbIdGreaterThan(4),
      ]) {
        for (final ordered in [query, query.sortByNameDesc().thenByDbId()]) {
          for (final window in [
            ordered,
            ordered.offset(1),
            ordered.offset(1).limit(2),
            ordered.limit(0),
          ]) {
            expect(await window.count(), (await window.findAll()).length);
          }
        }
      }
    });

    // Scenario: Repeated names and nullable projected IDs are counted.
    // Covers:
    // - Distinct cardinality and non-null property count semantics.
    // Expected: Four distinct names and seven non-null IDs are counted; paged
    // counts match their selected values.
    test('keeps distinct and non-null property counts unchanged.', () async {
      // Arrange.
      final distinct = database.apiProducts.all().sortByName().distinctByName();
      // Act / Assert.
      expect(await distinct.count(), 4);
      expect(await distinct.offset(1).limit(2).count(), 2);
      expect(await distinct.limit(0).count(), 0);
      final query = database.apiProducts.all().sortByDbId();
      expect(await query.count(), 10);
      expect(await query.idProperty().count(), 7);
      final projected = query.offset(2).limit(4).idProperty();
      expect(
        await projected.count(),
        (await projected.findAll()).where((value) => value != null).length,
      );
    });

    // Scenario: A transaction inserts, updates and deletes rows before
    // rollback or commit.
    // Covers:
    // - Pending counts, filtered counts and transaction visibility.
    // Expected: The aborted changes restore count ten; a later committed
    // deletion leaves count eight.
    test(
      'counts pending inserts, updates and deletes and respects rollback.',
      () async {
        // Arrange.
        final all = database.apiProducts.all();
        // Act / Assert.
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
                ..dbId = 21
                ..name = 'New',
            );
            await database.apiProducts.put(
              ApiProduct()
                ..dbId = 2
                ..name = 'Updated',
            );
            expect(await all.count(), 11);
            expect(await all.sortByName().offset(9).limit(5).count(), 2);
            expect(await all.filter().nameEqualTo('New').count(), 2);
            throw StateError('rollback');
          }),
          throwsStateError,
        );
        expect(await all.count(), 10);
        expect(await all.filter().nameEqualTo('New').count(), 0);
        await database.writeTxn(() async {
          await database.apiProducts.deleteAll([1, 2]);
          expect(await all.count(), 8);
        });
        expect(await all.count(), 8);
      },
    );

    // Scenario: Rows are deleted, the handle is reopened and the collection
    // is emptied.
    // Covers:
    // - Persisted count changes and empty counts in read transactions.
    // Expected: Reopen sees eight remaining rows; deleting them makes all
    // tested counts zero.
    test(
      'counts empty collections and persisted changes after reopen.',
      () async {
        // Arrange: use the inputs described in this scenario.
        // Act.
        await database.apiProducts.deleteAll([1, 2]);
        await database.close();
        database = await _open(directory);
        // Assert.
        expect(await database.apiProducts.all().count(), 8);
        await database.apiProducts.deleteAll(List.generate(8, (i) => i + 3));
        await database.readTxn(() async {
          expect(await database.apiProducts.all().count(), 0);
          expect(
            await database.apiProducts
                .all()
                .sortByName()
                .offset(1)
                .limit(2)
                .count(),
            0,
          );
        });
        expect(await database.apiProducts.where().idEqualTo('a').count(), 0);
      },
    );

    if (includeSameDirectoryHandles) {
      // Scenario: A second handle commits changes while the first holds a
      // read transaction.
      // Covers:
      // - Snapshot isolation for full, filtered and paged counts.
      // Expected: The read snapshot keeps the original ten rows and excludes
      // New; after it ends the count is eight.
      test('uses the read snapshot after another handle commits.', () async {
        // Arrange.
        final other = await _open(directory);
        addTearDown(other.close);
        // Act / Assert.
        await database.readTxn(() async {
          expect(await database.apiProducts.all().count(), 10);
          await other.writeTxn(() async {
            await other.apiProducts.deleteAll([1, 2, 3]);
            await other.apiProducts.put(
              ApiProduct()
                ..dbId = 20
                ..name = 'New',
            );
          });
          expect(await database.apiProducts.all().count(), 10);
          expect(
            await database.apiProducts.all().sortByName().offset(8).count(),
            2,
          );
          expect(
            await database.apiProducts
                .all()
                .filter()
                .nameEqualTo('New')
                .count(),
            0,
          );
        });
        expect(await database.apiProducts.all().count(), 8);
      });
    }
  });
}

Future<CindelDatabase> _open(String directory) =>
    openTestDatabase(directory: directory, schemas: [ApiProductSchema]);
