import 'dart:async';

import 'package:cindel/cindel.dart';
import 'package:test/test.dart';

import 'backend_test_support.dart';
import 'close_test_support_io.dart'
    if (dart.library.js_interop) 'close_test_support_web.dart';
import 'dart_distinct_fixture.dart';
import 'schema_generation_fixture.dart' show Recipient, RecipientMetadata;

List<DistinctRecord> _rows() => [
  for (var id = 1; id <= 8; id++)
    DistinctRecord()
      ..dbId = id
      ..name = 'row$id'
      ..email = 'group${id % 3}'
      ..primaryRecipient = (id == 8
          ? null
          : (Recipient()
              ..name = id == 7 ? null : (id.isEven ? 'yes' : 'no')
              ..metadata = (id == 7
                  ? null
                  : (RecipientMetadata()..label = id <= 4 ? 'yes' : 'no'))))
      ..recipients = [Recipient()..name = id <= 3 ? 'yes' : 'no'],
];

void main() {
  group('Cindel nested deletes', () {
    late CindelDatabase db;
    setUp(() async {
      final directory = await createCloseTestDirectory();
      addTearDown(() => deleteCloseTestDirectory(directory));
      db = await openTestDatabase(
        directory: directory,
        schemas: [DistinctRecordSchema],
      );
      addTearDown(db.close);
      await db.distinctRecords.putAll(_rows());
    });

    for (final kind in ['single', 'deep', 'list', 'null', 'or', 'not']) {
      // Scenario: Nested predicates select different rows before distinct/window.
      // Covers:
      // - Generated object/list filters, null parents, boolean composition.
      // - Both sort directions, distinct, offsets and empty/limited windows.
      // Expected: Only independently calculated IDs are deleted; rollback
      // restores every record and propagates the original controlled error.
      test('preserves $kind selection and rollback.', () async {
        // Arrange.
        final all = db.distinctRecords;
        final query = switch (kind) {
          'single' => all.filter().primaryRecipient(
            (p) => p.nameEqualTo('yes'),
          ),
          'deep' => all.filter().primaryRecipient(
            (p) => p.metadata((m) => m.labelEqualTo('yes')),
          ),
          'list' => all.filter().recipientsElement((r) => r.nameEqualTo('yes')),
          'null' => all.all().whereMatches(
            CindelFilter.path(['primaryRecipient', 'name']).equalTo(null),
          ),
          'or' => all.all().whereMatches(
            CindelFilter.any([
              CindelFilter.path(['primaryRecipient', 'name']).equalTo('yes'),
              CindelFilter.field('dbId').equalTo(1),
            ]),
          ),
          _ => all.all().whereMatches(
            CindelFilter.not(
              CindelFilter.path(['primaryRecipient', 'name']).equalTo('yes'),
            ),
          ),
        };
        final matching = switch (kind) {
          'single' => [2, 4, 6],
          'deep' => [1, 2, 3, 4],
          'list' => [1, 2, 3],
          'null' => [7],
          'or' => [1, 2, 4, 6],
          _ => [1, 3, 5, 7, 8],
        };
        for (final descending in [false, true]) {
          for (final distinct in [false, true]) {
            for (final offset in [0, 1, 99]) {
              for (final limit in <int?>[null, 0, 1, 2]) {
                var q = descending
                    ? query.sortByDbIdDesc()
                    : query.sortByDbId();
                Iterable<int> expected = descending
                    ? matching.reversed
                    : matching;
                if (distinct) {
                  q = q.distinctByEmail();
                  final seen = <int>{};
                  expected = expected.where((id) => seen.add(id % 3)).toList();
                }
                q = q.offset(offset);
                expected = expected.skip(offset);
                if (limit != null) {
                  q = q.limit(limit);
                  expected = expected.take(limit);
                }
                final ids = expected.toList();
                final failure = StateError('rollback $kind');
                // Act / Assert.
                await expectLater(
                  db.writeTxn(() async {
                    expect(await q.deleteAll(), ids.length);
                    expect(await all.getAll(ids), everyElement(isNull));
                    final remaining = await all.all().sortByDbId().findAll();
                    expect(remaining.map((row) => row.dbId), [
                      for (var id = 1; id <= 8; id++)
                        if (!ids.contains(id)) id,
                    ]);
                    throw failure;
                  }),
                  throwsA(same(failure)),
                );
                final restored = await all.all().sortByDbId().findAll();
                expect(
                  restored.map(DistinctRecordSchema.toDocument),
                  _rows().map(DistinctRecordSchema.toDocument),
                );
              }
            }
          }
        }
      });
    }

    // Scenario: A generated schema observes the work of first/all nested deletes.
    // Covers: Native MDBX selection without Dart hydration or serialization.
    // Expected: MDBX reads/converts no objects; all backends delete the same IDs.
    test('avoids Dart hydration for MDBX nested deletes.', () async {
      // Arrange.
      var readers = 0;
      var conversions = 0;
      final s = DistinctRecordSchema;
      final counted = CindelCollectionSchema<DistinctRecord>(
        name: s.name,
        dartName: s.dartName,
        idField: s.idField,
        fields: s.fields,
        links: s.links,
        compositeIndexes: s.compositeIndexes,
        toDocument: (object) {
          conversions++;
          return s.toDocument(object);
        },
        fromDocument: s.fromDocument,
        toBinaryDocument: s.toBinaryDocument,
        fromBinaryDocument: s.fromBinaryDocument,
        getId: s.getId,
        setId: s.setId,
        writeNativeDocument: s.writeNativeDocument,
        readNativeDocument: (reader, index) {
          readers++;
          return s.readNativeDocument!(reader, index);
        },
        bindLinks: s.bindLinks,
      );
      for (final first in [false, true]) {
        await db.distinctRecords.putAll(_rows());
        final query = db
            .typedCollection(counted)
            .all()
            .filter()
            .primaryRecipient((p) => p.nameEqualTo('yes'))
            .sortByDbId();
        readers = 0;
        conversions = 0;
        // Act.
        if (first) {
          expect(await query.deleteFirst(), isTrue);
        } else {
          expect(await query.deleteAll(), 3);
        }
        // Assert.
        if (testStorageBackend == CindelStorageBackend.mdbx) {
          expect(readers, 0);
          expect(conversions, 0);
        }
        expect(
          (await db.distinctRecords.all().sortByDbId().findAll()).map(
            (r) => r.dbId,
          ),
          first ? [1, 3, 4, 5, 6, 7, 8] : [1, 3, 5, 7, 8],
        );
      }
    });

    for (final first in [false, true]) {
      // Scenario: A nested deletion removes rows with incoming/outgoing/self links.
      // Covers:
      // - Relation cleanup, rollback and committed collection revisions/watchers.
      // - Reusing a deleted identity without resurrecting its previous links.
      // Expected: Aborted deletes preserve rows/links and publish no change;
      // committed deletes remove only incident edges and notify observers.
      test('preserves links and notifications, first=$first.', () async {
        // Arrange.
        Future<void> link(int id, List<int> targets) => db.saveLinkIds(
          sourceCollection: 'distinctRecords',
          sourceId: id,
          linkName: 'peers',
          targetCollection: 'distinctRecords',
          targetIds: targets,
        );
        Future<List<int>> linked(int id) async =>
            (await db.loadLinkedObjects<DistinctRecord>(
              sourceCollection: 'distinctRecords',
              sourceId: id,
              linkName: 'peers',
              targetCollection: 'distinctRecords',
            )).map((row) => row.dbId).toList();
        await link(1, [1, 2]);
        await link(2, [2, 5]);
        await link(3, [2, 4]);
        final events = <CindelChangeSet>[];
        final subscription = db
            .watchCollectionChanges(
              'distinctRecords',
              pollInterval: const Duration(milliseconds: 5),
            )
            .listen(events.add);
        addTearDown(subscription.cancel);
        Future<void> waitFor(bool Function() condition) async {
          for (var i = 0; i < 200 && !condition(); i++) {
            await Future<void>.delayed(const Duration(milliseconds: 5));
          }
          expect(condition(), isTrue);
        }

        await waitFor(() => events.isNotEmpty);
        await db.distinctRecords.put(_rows().last);
        await waitFor(() => events.last.revision != null);
        final initial = events.length;
        final revision = events.last.revision!;
        final query = db.distinctRecords
            .filter()
            .primaryRecipient((p) => p.nameEqualTo('yes'))
            .sortByDbId();
        Future<void> remove() async {
          if (first) {
            expect(await query.deleteFirst(), isTrue);
          } else {
            expect(await query.deleteAll(), 3);
          }
        }

        final failure = StateError('rollback nested links');
        // Act / Assert.
        await expectLater(
          db.writeTxn(() async {
            await remove();
            expect(await linked(1), [1]);
            expect(await linked(3), first ? [4] : <int>[]);
            throw failure;
          }),
          throwsA(same(failure)),
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(events.length, initial);
        expect(await linked(1), [1, 2]);
        expect(await linked(2), [2, 5]);
        expect(await linked(3), [2, 4]);
        await db.writeTxn(remove);
        await waitFor(() => events.length > initial);
        expect(events.last.revision, greaterThan(revision));
        await subscription.cancel();
        await db.distinctRecords.put(_rows()[1]);
        expect(await linked(1), [1]);
        expect(await linked(2), isEmpty);
        expect(await linked(3), first ? [4] : <int>[]);
        expect((await db.cleanupOrphanLinks()).removedLinks, 0);
      });

      // Scenario: Transaction-local writes change which nested rows match.
      // Covers: Pending inserts/updates/deletes and native transactional overlays.
      // Expected: First/all see current writes, including the newly matching ID.
      test('sees pending writes, first=$first.', () async {
        // Arrange.
        final rows = db.distinctRecords;
        final query = rows
            .filter()
            .primaryRecipient((p) => p.nameEqualTo('yes'))
            .sortByDbId();
        // Act.
        await db.writeTxn(() async {
          await rows.delete(2);
          await rows.put(
            _rows().first..primaryRecipient = (Recipient()..name = 'yes'),
          );
          await rows.put(
            DistinctRecord()
              ..dbId = 9
              ..name = 'row9'
              ..email = 'new'
              ..primaryRecipient = (Recipient()..name = 'yes'),
          );
          if (first) {
            expect(await query.deleteFirst(), isTrue);
          } else {
            expect(await query.deleteAll(), 4);
          }
        });
        // Assert.
        expect(
          (await rows.all().sortByDbId().findAll()).map((r) => r.dbId),
          first ? [3, 4, 5, 6, 7, 8, 9] : [3, 5, 7, 8],
        );
      });
    }
  });
}
