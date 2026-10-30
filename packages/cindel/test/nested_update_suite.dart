import 'package:test/test.dart';
import 'backend_test_support.dart';
import 'package:cindel/cindel.dart';
import 'dart_distinct_fixture.dart';
import 'schema_generation_fixture.dart';
import 'close_test_support_io.dart'
    if (dart.library.js_interop) 'close_test_support_web.dart';

void require(bool ok, String message) {
  if (!ok) {
    throw StateError(message);
  }
}

List<DistinctRecord> seed() => [
  for (var id = 1; id <= 9; id++)
    DistinctRecord()
      ..dbId = id
      ..name = 'original'
      ..email = 'group' + ((id - 1) ~/ 3).toString()
      ..tags = ['preserved']
      ..recipients = (id == 2 || id == 5 ? [Recipient()..name = 'yes'] : [])
      ..primaryRecipient = (id == 8
          ? null
          : (Recipient()
              ..name = (id == 1 || id == 4 || id == 7 || id == 9 ? 'no' : 'yes')
              ..metadata = (id == 7
                  ? null
                  : (RecipientMetadata()
                      ..label = (id == 9
                          ? null
                          : (id == 1 || id == 4 ? 'no' : 'yes')))))),
];
CindelQuery<DistinctRecord> query(CindelDatabase db, String shape) =>
    switch (shape) {
      'list' => db.distinctRecords.filter().recipientsElement(
        (p) => p.nameEqualTo('yes'),
      ),
      'single' => db.distinctRecords.filter().primaryRecipient(
        (p) => p.nameEqualTo('yes'),
      ),
      'double' => db.distinctRecords.filter().primaryRecipient(
        (p) => p.metadata((m) => m.labelEqualTo('yes')),
      ),
      'null' => db.distinctRecords.filter().primaryRecipient(
        (p) => p.metadata((m) => m.labelEqualTo(null)),
      ),
      'mixed_or' => db.distinctRecords.all().whereMatches(
        CindelFilter.any([
          CindelFilter.field('dbId').equalTo(1),
          CindelFilter.path([
            'primaryRecipient',
            'metadata',
            'label',
          ]).equalTo('yes'),
        ]),
      ),
      _ => db.distinctRecords.filter().dbIdLessThanOrEqualTo(6),
    };
Future<void> _exercise() async {
  for (final backend in [testStorageBackend]) {
    final directory = await createCloseTestDirectory();
    final db = await Cindel.open(
      directory: directory,
      backend: backend,
      schemas: [DistinctRecordSchema, UserSchema],
    );
    try {
      // Scenario: Generated nested predicates select rows before distinct/window.
      // Covers: Two path depths, null parents, OR, first/all, offset and zero limit.
      // Expected: Updates match the typed read and preserve unselected rows.
      for (final shape in [
        'single',
        'double',
        'list',
        'null',
        'mixed_or',
        'scalar',
      ]) {
        for (final distinct in [false, true]) {
          for (final window in ['all', 'first', 'offset', 'zero']) {
            // Arrange.
            await db.distinctRecords.putAll(seed());
            var q = query(db, shape).sortByDbId();
            if (distinct) {
              q = q.distinctByEmail();
            }
            if (window == 'offset') {
              q = q.offset(1).limit(1);
            }
            if (window == 'zero') {
              q = q.limit(0);
            }
            var selected = (await q.findAll()).map((r) => r.dbId).toList();
            if (window == 'first') {
              selected = selected.take(1).toList();
            }
            final expectedBase = switch (shape) {
              'list' => [2, 5],
              'null' => [9],
              'mixed_or' => [1, 2, 3, 5, 6],
              'scalar' => [1, 2, 3, 4, 5, 6],
              _ => [2, 3, 5, 6],
            };
            var expected = distinct
                ? switch (shape) {
                    'list' => [2, 5],
                    'null' => [9],
                    'mixed_or' => [1, 5],
                    'scalar' => [1, 4],
                    _ => [2, 5],
                  }
                : expectedBase;
            if (window == 'offset') {
              expected = expected.skip(1).take(1).toList();
            }
            if (window == 'zero') {
              expected = [];
            }
            if (window == 'first') {
              expected = expected.take(1).toList();
            }
            require(
              selected.join(',') == expected.join(','),
              'read selection $shape/$distinct/$window: $selected != $expected',
            );
            // Act.
            final result = window == 'first'
                ? await q.updateFirst({'name': 'changed'})
                : await q.updateAll({'name': 'changed'});
            // Assert.
            final rows = await db.distinctRecords.all().sortByDbId().findAll();
            final changed = rows
                .where((r) => r.name == 'changed')
                .map((r) => r.dbId)
                .toList();
            require(
              changed.join(',') == expected.join(','),
              'changed set mismatch',
            );
            require(
              rows.length == 9 &&
                  rows.every((r) => r.tags.single == 'preserved'),
              'corrupt data',
            );
            require(
              result ==
                  (window == 'first' ? expected.isNotEmpty : expected.length),
              'bad count',
            );
          }
        }
      }
      // Scenario: An indexed generated where source precedes a nested filter and distinct.
      // Covers: Source restriction, both directions and first/all.
      // Expected: Selection reads and updates identify the same representatives.
      for (final descending in [false, true]) {
        for (final first in [false, true]) {
          // Arrange.
          await db.users.putAll([
            for (var id = 1; id <= 6; id++)
              User()
                ..dbId = id
                ..name = (id <= 3 ? 'A' : 'B')
                ..email = (id == 6 ? 'excluded' : 'team')
                ..primaryRecipient = (Recipient()
                  ..name = (id == 1 ? 'no' : 'yes')),
          ]);
          final candidates = db.users
              .where()
              .emailEqualTo('team')
              .filter()
              .primaryRecipient((p) => p.nameEqualTo('yes'));
          final q =
              (descending
                      ? candidates.sortByDbIdDesc()
                      : candidates.sortByDbId())
                  .distinctByName();
          var expected = descending ? [5, 3] : [2, 4];
          if (first) {
            expected = expected.take(1).toList();
          }
          require(
            (await (first ? q.limit(1) : q).findAll())
                    .map((r) => r.dbId)
                    .join(',') ==
                expected.join(','),
            'indexed read mismatch',
          );
          // Act.
          final result = first
              ? await q.updateFirst({'sessionLength': 42})
              : await q.updateAll({'sessionLength': 42});
          expect(result, first ? expected.isNotEmpty : expected.length);
          // Assert.
          final changed = (await db.users.all().sortByDbId().findAll())
              .where((r) => r.sessionLength != null)
              .map((r) => r.dbId)
              .toList();
          require(
            changed.join(',') == (expected.toList()..sort()).join(','),
            'indexed update mismatch',
          );
        }
      }
      // Scenario: A failing outer write transaction contains a nested distinct update.
      // Covers: Selection and write rollback after a successful nested update.
      // Expected: No name changes survive.
      await db.distinctRecords.putAll(seed());
      String? failure;
      try {
        await db.writeTxn(() async {
          await query(
            db,
            'double',
          ).sortByDbId().distinctByEmail().updateAll({'name': 'changed'});
          throw StateError('rollback-marker');
        });
      } catch (e) {
        failure = e.toString();
      }
      require(
        failure.contains('rollback-marker'),
        'update failed before rollback',
      );
      require(
        (await db.distinctRecords.all().findAll()).every(
          (r) => r.name == 'original',
        ),
        'rollback lost',
      );
    } finally {
      await db.close();
      await deleteCloseTestDirectory(directory);
    }
  }
}

void main() {
  group('Cindel nested updates', () {
    // Scenario: Generated nested queries previously read correctly but updates were rejected.
    // Covers: 52 query shapes, indexed where, filter, lists, null parents/leaves,
    // OR, distinct on/off, first/all, windows, both directions and rollback.
    // Expected: Every backend updates the same selected IDs and preserves other data.
    test('preserves typed nested selection and atomicity.', _exercise);

    for (final shape in [
      'not',
      'prefix',
      'suffix',
      'contains',
      'object',
      'listEmpty',
    ]) {
      // Scenario: Generated nested operators and structured equality require Dart path semantics.
      // Covers: String operators, NOT on missing parents, deep object equality and nullable lists.
      // Expected: Update selection equals the typed read and leaves all other rows intact.
      test('preserves nested $shape semantics.', () async {
        // Arrange.
        final directory = await createCloseTestDirectory();
        addTearDown(() => deleteCloseTestDirectory(directory));
        final db = await openTestDatabase(
          directory: directory,
          schemas: [DistinctRecordSchema],
        );
        addTearDown(db.close);
        await db.distinctRecords.putAll(seed());
        final all = db.distinctRecords.all();
        final q = (switch (shape) {
          'not' => all.whereMatches(
            CindelFilter.not(
              CindelFilter.path([
                'primaryRecipient',
                'metadata',
                'label',
              ]).equalTo('yes'),
            ),
          ),
          'prefix' => all.filter().primaryRecipient(
            (p) => p.metadata((m) => m.labelStartsWith('y')),
          ),
          'suffix' => all.filter().primaryRecipient(
            (p) => p.metadata((m) => m.labelEndsWith('s')),
          ),
          'contains' => all.filter().primaryRecipient(
            (p) => p.metadata((m) => m.labelContains('e')),
          ),
          'object' => all.filter().primaryRecipient(
            (p) => p.metadataEqualTo(RecipientMetadata()..label = 'yes'),
          ),
          _ => all.whereMatches(
            CindelFilter.all([
              CindelFilter.path([
                'primaryRecipient',
                'metadata',
                'label',
              ]).equalTo('yes'),
              CindelFilter.field('recipients').isEmpty(),
            ]),
          ),
        }).sortByDbId().distinctByEmail();
        final ids = (await q.findAll()).map((r) => r.dbId).toList();
        // Act.
        expect(await q.updateAll({'name': 'changed'}), ids.length);
        // Assert.
        final changed = (await db.distinctRecords.all().sortByDbId().findAll())
            .where((r) => r.name == 'changed')
            .map((r) => r.dbId);
        expect(changed, ids);
      });
    }

    // Scenario: A nested-selected update includes both valid changes and an invalid ID change.
    // Covers: Validation of all changes before any selected row is written.
    // Expected: Invalid changes leave both records unchanged.
    test('rejects ID changes before writing.', () async {
      // Arrange.
      final directory = await createCloseTestDirectory();
      addTearDown(() => deleteCloseTestDirectory(directory));
      final db = await openTestDatabase(
        directory: directory,
        schemas: [UserSchema],
      );
      addTearDown(db.close);
      await db.users.putAll([
        for (var id = 1; id <= 2; id++)
          User()
            ..dbId = id
            ..name = 'name' + id.toString()
            ..email = 'team'
            ..username = 'user' + id.toString()
            ..primaryRecipient = (Recipient()..name = 'yes'),
      ]);
      final q = db.users
          .filter()
          .primaryRecipient((p) => p.nameEqualTo('yes'))
          .sortByDbId()
          .distinctByName();
      // Act / Assert.
      await expectLater(
        q.updateAll({'name': 'invalid', 'dbId': 10}),
        throwsArgumentError,
      );
      final rows = await db.users.all().sortByDbId().findAll();
      expect(rows.map((r) => r.username), ['user1', 'user2']);
      expect(rows.map((r) => r.name), ['name1', 'name2']);
    });

    for (final rollback in [false, true]) {
      // Scenario: More than two ID batches change both their filter and distinct key.
      // Covers: Snapshot selection, read-your-writes, outer transaction commit and rollback.
      // Expected: All 300 initial representatives change once, or no change survives rollback.
      test('keeps multi-batch selection, rollback=$rollback.', () async {
        // Arrange.
        final directory = await createCloseTestDirectory();
        addTearDown(() => deleteCloseTestDirectory(directory));
        final db = await openTestDatabase(
          directory: directory,
          schemas: [DistinctRecordSchema],
        );
        addTearDown(db.close);
        await db.distinctRecords.putAll([
          for (var id = 1; id <= 600; id++)
            DistinctRecord()
              ..dbId = id
              ..name = 'original'
              ..email = 'group' + ((id - 1) ~/ 2).toString()
              ..primaryRecipient = (Recipient()
                ..metadata = (RecipientMetadata()..label = 'yes')),
        ]);
        final q = query(db, 'double').sortByDbId().distinctByEmail();
        // Act.
        Future<void> work() => db.writeTxn(() async {
          expect(
            await q.updateAll({'email': 'same', 'primaryRecipient': null}),
            300,
          );
          expect((await db.distinctRecords.get(1))!.primaryRecipient, isNull);
          if (rollback) {
            throw StateError('rollback-marker');
          }
        });
        if (rollback) {
          await expectLater(work(), throwsStateError);
        } else {
          await work();
        }
        // Assert.
        final rows = await db.distinctRecords.all().sortByDbId().findAll();
        expect(rows.length, 600);
        for (final row in rows) {
          final changed = !rollback && row.dbId.isOdd;
          expect(row.primaryRecipient == null, changed);
          expect(
            row.email,
            changed ? 'same' : 'group' + ((row.dbId - 1) ~/ 2).toString(),
          );
        }
      });
    }
    // Scenario: A nested update matches one row and all candidates have generated readers.
    // Covers: Actual Dart hydration, preserving MDBX's native selection and SQLite's behavior.
    // Expected: MDBX calls no generated reader; SQLite reads nine candidates and updates ID 9.
    test('does not hydrate MDBX nested update candidates in Dart.', () async {
      // Arrange.
      final directory = await createCloseTestDirectory();
      addTearDown(() => deleteCloseTestDirectory(directory));
      final db = await openTestDatabase(
        directory: directory,
        schemas: [DistinctRecordSchema],
      );
      addTearDown(db.close);
      await db.distinctRecords.putAll(seed());
      var reads = 0;
      final s = DistinctRecordSchema;
      final counted = CindelCollectionSchema<DistinctRecord>(
        name: s.name,
        dartName: s.dartName,
        idField: s.idField,
        fields: s.fields,
        links: s.links,
        compositeIndexes: s.compositeIndexes,
        toDocument: s.toDocument,
        fromDocument: s.fromDocument,
        toBinaryDocument: s.toBinaryDocument,
        fromBinaryDocument: s.fromBinaryDocument,
        getId: s.getId,
        setId: s.setId,
        writeNativeDocument: s.writeNativeDocument,
        readNativeDocument: (reader, index) {
          reads++;
          return s.readNativeDocument!(reader, index);
        },
        bindLinks: s.bindLinks,
      );
      final q = db
          .typedCollection(counted)
          .all()
          .filter()
          .primaryRecipient((p) => p.metadata((m) => m.labelEqualTo(null)))
          .distinctByEmail();
      // Act.
      expect(await q.updateAll({'name': 'changed'}), 1);
      // Assert.
      expect(reads, testStorageBackend == CindelStorageBackend.mdbx ? 0 : 9);
      expect((await db.distinctRecords.get(9))!.name, 'changed');
    });
  });
}
