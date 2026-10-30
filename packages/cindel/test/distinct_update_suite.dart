import 'package:cindel/cindel.dart';
import 'package:test/test.dart';

import 'backend_test_support.dart';
import 'close_test_support_io.dart'
    if (dart.library.js_interop) 'close_test_support_web.dart';
import 'dart_distinct_fixture.dart';
import 'schema_generation_fixture.dart';

void main() {
  group('Cindel distinct updates', () {
    late CindelDatabase database;

    setUp(() async {
      final directory = await createCloseTestDirectory();
      addTearDown(() => deleteCloseTestDirectory(directory));
      database = await openTestDatabase(
        directory: directory,
        schemas: [UserSchema, DistinctRecordSchema],
      );
      addTearDown(database.close);
      await database.users.putAll([
        for (var id = 1; id <= 6; id++)
          User()
            ..dbId = id
            ..name = id <= 3 ? 'A' : 'B'
            ..email = id <= 5 ? 'team' : 'other'
            ..displayName = id <= 3 ? 'TEAM' : null
            ..tags = id <= 3 ? ['one'] : ['two']
            ..primaryRecipient = (Recipient()..name = id <= 3 ? 'A' : 'B'),
      ]);
    });

    for (final source in ['where', 'filter']) {
      for (final descending in [false, true]) {
        for (final window in ['all', 'first', 'window', 'zero', 'past']) {
          // Scenario: Excluded rows share distinct keys with eligible rows.
          // Covers: Generated where/filter, sort ties, first/all and windows.
          // Expected: Filtering precedes distinct and the window; query reuse
          // and all unselected values remain unchanged.
          test('$source descending=$descending preserves $window.', () async {
            // Arrange.
            final candidates =
                (source == 'where'
                        ? database.users.where().emailEqualTo('team')
                        : database.users.filter().emailEqualTo('team'))
                    .filter()
                    .dbIdBetween(2, 5);
            var query =
                (descending
                        ? candidates.sortByNameDesc().thenByDbIdDesc()
                        : candidates.sortByName().thenByDbId())
                    .distinctByName();
            var ids = descending ? [5, 3] : [2, 4];
            switch (window) {
              case 'first':
                ids = ids.take(1).toList();
              case 'window':
                query = query.offset(1).limit(1);
                ids = ids.skip(1).toList();
              case 'zero':
                query = query.limit(0);
                ids = [];
              case 'past':
                query = query.offset(2);
                ids = [];
            }
            final selectedBefore = (await query.findAll())
                .map((row) => row.dbId)
                .toList();
            // Act.
            if (window == 'first') {
              expect(await query.updateFirst({'sessionLength': 42}), isTrue);
            } else {
              expect(await query.updateAll({'sessionLength': 42}), ids.length);
            }
            // Assert.
            final rows = await database.users.all().sortByDbId().findAll();
            expect(
              rows
                  .where((row) => row.sessionLength != null)
                  .map((row) => row.dbId),
              ids.toList()..sort(),
            );
            expect(rows.map((row) => row.name), ['A', 'A', 'A', 'B', 'B', 'B']);
            expect(
              (await query.findAll()).map((row) => row.dbId),
              selectedBefore,
            );
          });
        }
      }
    }

    for (final sorted in [false, true]) {
      // Scenario: A numeric filter can use an index whose order reverses IDs.
      // Covers: Implicit traversal order and stable ties in explicit sorting.
      // Expected: Distinct chooses the original first ID of each name group.
      test(
        'preserves representatives across index plans, sorted=$sorted.',
        () async {
          // Arrange.
          final users = await database.users.all().findAll();
          for (final user in users) {
            user.createdAt = DateTime.fromMicrosecondsSinceEpoch(
              7 - user.dbId,
              isUtc: true,
            );
          }
          await database.users.putAll(users);
          var query = database.users.filter().createdAtGreaterThan(
            DateTime.fromMicrosecondsSinceEpoch(0, isUtc: true),
          );
          if (sorted) query = query.sortByName();
          query = query.distinctByName();
          // Act.
          expect(await query.updateAll({'sessionLength': 42}), 2);
          // Assert.
          final rows = await database.users.all().sortByDbId().findAll();
          expect(
            rows
                .where((row) => row.sessionLength != null)
                .map((row) => row.dbId),
            [1, 4],
          );
        },
      );
    }

    // Scenario: An indexed equality source has no additional filter.
    // Covers: Source-only preselection and exclusion before distinct.
    // Expected: The last matching representative per name changes.
    test('prefilters an equality source without an extra filter.', () async {
      // Arrange.
      final query = database.users
          .where()
          .emailEqualTo('team')
          .sortByDbIdDesc()
          .distinctByName();
      // Act.
      expect(await query.updateAll({'sessionLength': 42}), 2);
      // Assert.
      final rows = await database.users.all().sortByDbId().findAll();
      expect(
        rows.where((row) => row.sessionLength != null).map((row) => row.dbId),
        [3, 5],
      );
    });

    // Scenario: Null scalar equality is evaluated before distinct on another key.
    // Covers: SQL IS NULL and unchanged representatives for nullable fields.
    // Expected: Exactly IDs 4 and 6 change, preserving the non-null rows.
    test('preserves null equality before distinct.', () async {
      // Arrange.
      final query = database.users
          .filter()
          .displayNameEqualTo(null)
          .sortByDbId()
          .distinctByEmail();
      // Act.
      expect(await query.updateAll({'sessionLength': 42}), 2);
      // Assert.
      final rows = await database.users.all().sortByDbId().findAll();
      expect(
        rows.where((row) => row.sessionLength != null).map((row) => row.dbId),
        [4, 6],
      );
    });

    for (final empty in ['zero', 'missing']) {
      // Scenario: A distinct first update has a zero limit or no matching rows.
      // Covers: Empty selections and updateFirst's boolean result.
      // Expected: No row changes and updateFirst returns false.
      test('does not update an empty $empty selection.', () async {
        // Arrange.
        var query = database.users
            .filter()
            .emailEqualTo(empty == 'missing' ? 'missing' : 'team')
            .sortByDbId()
            .distinctByName();
        if (empty == 'zero') query = query.limit(0);
        // Act.
        expect(await query.updateFirst({'sessionLength': 42}), isFalse);
        // Assert.
        expect(
          (await database.users.all().findAll()).every(
            (row) => row.sessionLength == null,
          ),
          isTrue,
        );
      });
    }

    // Scenario: A valid change is followed by an invalid ID mutation.
    // Covers: Complete changes validation before candidate selection or writes.
    // Expected: The error is propagated and even the valid change is not applied.
    test('validates every change before writing.', () async {
      // Arrange.
      final query = database.users
          .filter()
          .dbIdGreaterThan(1)
          .sortByDbId()
          .distinctByName();
      // Act.
      await expectLater(
        query.updateAll({'name': 'bad', 'dbId': 99}),
        throwsArgumentError,
      );
      // Assert.
      expect(
        (await database.users.all().sortByDbId().findAll()).map(
          (row) => row.name,
        ),
        ['A', 'A', 'A', 'B', 'B', 'B'],
      );
    });

    for (final field in ['displayName', 'tags', 'primaryRecipient']) {
      // Scenario: A scalar filter precedes distinct on nullable/structured keys.
      // Covers: Existing null, list and embedded-object distinct semantics.
      // Expected: The earliest eligible representative of each key changes.
      test('preserves structural distinct on $field.', () async {
        // Arrange.
        final query = database.users
            .filter()
            .dbIdBetween(2, 5)
            .sortByDbId()
            .distinctByFields([field]);
        // Act.
        expect(await query.updateAll({'sessionLength': 42}), 2);
        // Assert.
        final rows = await database.users.all().sortByDbId().findAll();
        expect(
          rows.where((row) => row.sessionLength != null).map((row) => row.dbId),
          [2, 4],
        );
      });
    }

    for (final shape in ['not', 'nested', 'list', 'normalized', 'or']) {
      // Scenario: Distinct candidates require non-SQL semantics or a whole OR.
      // Covers: Safe fallback, nullable negation and no partial OR pushdown.
      // Expected: Candidate prefiltering never removes a matching representative.
      test('preserves $shape candidate semantics.', () async {
        // Arrange.
        final all = database.users.all();
        final query = switch (shape) {
          'not' => all.whereMatches(
            CindelFilter.not(CindelFilter.field('displayName').equalTo('TEAM')),
          ),
          'nested' => all.whereMatches(
            CindelFilter.any([
              CindelFilter.field('dbId').equalTo(2),
              CindelFilter.path(['primaryRecipient', 'name']).equalTo('B'),
            ]),
          ),
          'list' => all.filter().tagsElementEqualTo('two'),
          'normalized' => database.users.where().displayNameEqualTo('team'),
          _ => all.whereMatches(
            CindelFilter.any([
              CindelFilter.field('dbId').equalTo(2),
              CindelFilter.field('dbId').equalTo(5),
            ]),
          ),
        };
        final selected = query.sortByDbId().distinctByName();
        final expected = shape == 'not' || shape == 'list'
            ? [4]
            : shape == 'normalized'
            ? [1]
            : shape == 'nested'
            ? [2, 4]
            : [2, 5];
        // Act / Assert.
        expect(
          await selected.updateAll({'sessionLength': 42}),
          expected.length,
        );
        final rows = await database.users.all().sortByDbId().findAll();
        expect(
          rows.where((row) => row.sessionLength != null).map((row) => row.dbId),
          expected,
        );
      });
    }

    for (final rollback in [false, true]) {
      // Scenario: More than two ID batches change both source and distinct keys.
      // Covers: Fixed selection, transaction visibility and rollback across batches.
      // Expected: Only original odd-ID representatives change, or all writes roll back.
      test('captures all batches before writes, rollback=$rollback.', () async {
        // Arrange.
        await database.distinctRecords.putAll([
          for (var id = 1; id <= 600; id++)
            DistinctRecord()
              ..dbId = id
              ..name = 'original'
              ..email = 'group${(id - 1) ~/ 2}',
        ]);
        final query = database.distinctRecords
            .filter()
            .nameEqualTo('original')
            .sortByDbId()
            .distinctByEmail();
        Future<void> update() async {
          expect(
            await query.updateAll({'name': 'changed', 'email': 'merged'}),
            300,
          );
          expect(
            await database.distinctRecords
                .filter()
                .nameEqualTo('changed')
                .count(),
            300,
          );
          if (rollback) throw StateError('rollback all ID batches');
        }

        // Act.
        if (rollback) {
          await expectLater(database.writeTxn(update), throwsStateError);
        } else {
          await update();
        }
        // Assert.
        final rows = await database.distinctRecords
            .all()
            .sortByDbId()
            .findAll();
        expect(rows, hasLength(600));
        for (final row in rows) {
          final changed = !rollback && row.dbId.isOdd;
          expect(row.name, changed ? 'changed' : 'original');
          expect(row.email, changed ? 'merged' : 'group${(row.dbId - 1) ~/ 2}');
        }
      });
    }

    // Scenario: Twenty matches are surrounded by 1,980 irrelevant documents.
    // Covers: Generated readers and document conversions after prefiltering.
    // Expected: SQLite reads/converts twenty candidates once; MDBX does neither.
    // Five representatives change and irrelevant documents remain untouched.
    test('hydrates only matching candidates.', () async {
      // Arrange.
      final original = DistinctRecordSchema;
      var reads = 0;
      final conversions = <int, int>{};
      final counted = CindelCollectionSchema<DistinctRecord>(
        name: original.name,
        dartName: original.dartName,
        idField: original.idField,
        fields: original.fields,
        toDocument: (object) {
          conversions.update(
            object.dbId,
            (count) => count + 1,
            ifAbsent: () => 1,
          );
          return original.toDocument(object);
        },
        fromDocument: original.fromDocument,
        toBinaryDocument: original.toBinaryDocument,
        fromBinaryDocument: original.fromBinaryDocument,
        getId: original.getId,
        setId: original.setId,
        writeNativeDocument: original.writeNativeDocument,
        readNativeDocument: (reader, index) {
          reads++;
          return original.readNativeDocument!(reader, index);
        },
      );
      final collection = database.typedCollection(counted);
      await collection.putAll([
        for (var id = 1; id <= 2000; id++)
          DistinctRecord()
            ..dbId = id
            ..name = 'original'
            ..email = 'group${id % 5}',
      ]);
      final query = collection
          .all()
          .filter()
          .dbIdBetween(1001, 1020)
          .sortByDbId()
          .distinctByEmail();
      // Act.
      reads = 0;
      conversions.clear();
      final changed = await query.updateAll({'name': 'changed'});
      final candidateReads = reads;
      // Assert.
      expect(changed, 5);
      final usesDart = testStorageBackend != CindelStorageBackend.mdbx;
      expect(candidateReads, usesDart ? 20 : 0);
      expect(
        conversions.keys,
        usesDart ? [for (var id = 1001; id <= 1020; id++) id] : isEmpty,
      );
      expect(conversions.values, everyElement(1));
      final rows = await collection
          .all()
          .filter()
          .nameEqualTo('changed')
          .sortByDbId()
          .findAll();
      expect(rows.map((row) => row.dbId), [1001, 1002, 1003, 1004, 1005]);
    });
  });
}
