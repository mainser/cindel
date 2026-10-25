import 'package:cindel/cindel.dart';
import 'package:test/test.dart';

import 'backend_test_support.dart';
import 'close_test_support_io.dart'
    if (dart.library.js_interop) 'close_test_support_web.dart';
import 'schema_generation_fixture.dart';

// The generated API, fixtures and expected results are identical on all backends.
void main() {
  group('Cindel projection and aggregate contracts', () {
    late CindelDatabase database;
    late List<User> users;

    setUp(() async {
      final directory = await createCloseTestDirectory();
      addTearDown(() => deleteCloseTestDirectory(directory));
      database = await openTestDatabase(
        directory: directory,
        schemas: [UserSchema],
      );
      addTearDown(database.close);
      users = [
        for (var id = 1; id <= 6; id++)
          User()
            ..dbId = id
            ..name = [
              'Gamma',
              'Alpha',
              'Beta',
              'Alpha',
              'Gamma',
              'Delta',
            ][id - 1]
            ..email = [1, 2, 3, 5].contains(id)
                ? 'team@example.com'
                : 'solo$id@example.com'
            ..displayName = [
              'TEAM',
              null,
              'team',
              null,
              'other',
              'team',
            ][id - 1]
            ..bio = [
              'Flutter database',
              'Flutter app',
              'FLUTTER',
              'flutterish',
              'flutter database',
              'other',
            ][id - 1]
            ..tags = [
              ['one', 'two'],
              ['one'],
              ['one'],
              <String>[],
              ['one'],
              ['two'],
            ][id - 1]
            ..primaryRecipient = _recipient(
              [1, 2, 4, 5].contains(id) ? 'keep' : 'skip',
            )
            ..recipients = [
              _recipient('skip'),
              if (id.isOdd) _recipient('keep'),
            ],
      ];
      await database.users.putAll(users);
    });

    final sources =
        <
          ({
            String name,
            CindelQuery<User> Function(CindelDatabase) query,
            List<int> ids,
          })
        >[
          (
            name: 'where indexed equality',
            query: (db) => db.users.where().emailEqualTo('team@example.com'),
            ids: [1, 2, 3, 5],
          ),
          (
            name: 'filter indexed equality',
            query: (db) => db.users.filter().emailEqualTo('team@example.com'),
            ids: [1, 2, 3, 5],
          ),
          (
            name: 'where normalized equality',
            query: (db) => db.users.where().displayNameEqualTo('TeAm'),
            ids: [1, 3, 6],
          ),
          (
            // Normalized index keys do not change exact field equality.
            name: 'filter exact equality on a normalized index',
            query: (db) => db.users.filter().displayNameEqualTo('team'),
            ids: [3, 6],
          ),
          (
            name: 'where word equality',
            query: (db) => db.users.where().bioWordEqualTo('FLUTTER'),
            ids: [1, 2, 3, 5],
          ),
          (
            name: 'where word prefix',
            query: (db) => db.users.where().bioWordStartsWith('FLUTT'),
            ids: [1, 2, 3, 4, 5],
          ),
          (
            name: 'filter list length',
            query: (db) => db.users.filter().tagsLengthGreaterThan(0),
            ids: [1, 2, 3, 5, 6],
          ),
          (
            name: 'filter nested embedded field',
            query: (db) => db.users.filter().primaryRecipient(
              (q) => q.metadata((q) => q.labelEqualTo('keep')),
            ),
            ids: [1, 2, 4, 5],
          ),
          (
            name: 'filter embedded list element',
            query: (db) => db.users.filter().recipientsElement(
              (q) => q.metadata((q) => q.labelEqualTo('keep')),
            ),
            ids: [1, 3, 5],
          ),
        ];

    for (final source in sources) {
      // Scenario: Each indexed, word, list or embedded source selects from
      // six seeded users.
      // Covers:
      // - Single/multiple projections.
      // - count, min, max, sum and average before and after pagination.
      // Expected: Descending IDs and all projected values match the explicit
      // source IDs; deriving a window leaves the original query unchanged.
      test(
        '${source.name}: projections and aggregates respect windows.',
        () async {
          // Arrange.
          final query = source.query(database).sortByDbIdDesc();
          final descending = source.ids.reversed.toList();
          // Act / Assert.
          await _expectWindow(query, descending, users);
          await _expectWindow(
            query.offset(1).limit(2),
            descending.skip(1).take(2).toList(),
            users,
          );
          // Deriving a window must not change the original reusable query.
          expect(await query.dbIdProperty().findAll(), descending);
        },
      );

      // Scenario: Matching users share names and are ordered by name then
      // descending ID.
      // Covers:
      // - Distinct representative selection.
      // - offset/limit applied after deduplication.
      // Expected: Each name retains its first ordered user, and every
      // projection and aggregate uses that same representative window.
      test('${source.name}: distinct precedes offset and limit.', () async {
        // Arrange.
        final query = source.query(database).sortByName().thenByDbIdDesc();
        final ordered = source.ids.map((id) => users[id - 1]).toList()
          ..sort((a, b) {
            final names = a.name.compareTo(b.name);
            return names != 0 ? names : b.dbId.compareTo(a.dbId);
          });
        final seen = <String>{};
        final representatives = [
          for (final user in ordered)
            if (seen.add(user.name)) user.dbId,
        ];
        final distinct = query.distinctByName();
        // Act / Assert.
        await _expectWindow(distinct, representatives, users);
        await _expectWindow(
          distinct.offset(1).limit(2),
          representatives.skip(1).take(2).toList(),
          users,
        );
      });

      // Scenario: A matching query is given a zero limit, an exhausted offset
      // or an impossible ID filter.
      // Covers:
      // - Empty objects, projections, first values and aggregates for every
      // source variant.
      // Expected: Lists are empty, counts are zero and
      // first/min/max/sum/average are null.
      test('${source.name}: empty windows have no aggregate value.', () async {
        // Arrange.
        final query = source.query(database).sortByDbId();
        // Act / Assert.
        for (final empty in [
          query.limit(0),
          query.offset(source.ids.length),
          query.filter().dbIdGreaterThan(99),
        ]) {
          await _expectWindow(empty, const [], users);
        }
      });
    }

    for (final normalized in [false, true]) {
      // Scenario: An equality filter is added after sort, distinct, offset
      // and limit modifiers.
      // Covers:
      // - Indexed equality optimization.
      // - exact predicates on normalized string indexes.
      // - immutable query modifiers.
      // Expected: The filtered window contains ID 6 or 3 as specified, while
      // the original window still contains ID 3.
      test(
        'filter equality preserves existing modifiers, normalized=$normalized.',
        () async {
          // Arrange.
          final base = database.users
              .all()
              .sortByName()
              .thenByDbIdDesc()
              .distinctByName()
              .offset(1)
              .limit(1);
          final query = normalized
              ? base.filter().displayNameEqualTo('team')
              : base.filter().emailEqualTo('team@example.com');
          // Act / Assert.
          await _expectWindow(query, normalized ? [6] : [3], users);
          await _expectWindow(base, [3], users);
        },
      );
    }

    // Scenario: Stored display names differ in case from the mixed-case
    // search text.
    // Covers:
    // - Generated filter equality versus normalized indexed where equality.
    // Expected: filter() matches nothing for TeAm, while where() returns IDs
    // 1, 3 and 6.
    test(
      'filter equality does not inherit index case normalization.',
      () async {
        // Arrange: use the inputs described in this scenario.
        // Act / Assert.
        await _expectWindow(
          database.users.filter().displayNameEqualTo('TeAm').sortByDbId(),
          const [],
          users,
        );
        await _expectWindow(
          database.users.where().displayNameEqualTo('TeAm').sortByDbId(),
          [1, 3, 6],
          users,
        );
      },
    );

    // Check each API independently so an incorrect object representative does
    // not prevent the projection and aggregate assertions from executing.
    for (final operation in [
      'findAll',
      'findFirst',
      'properties',
      'count',
      'min',
      'max',
      'sum',
      'average',
    ]) {
      // Scenario: Two indexed matches share Gamma and the final distinct
      // window contains one representative.
      // Covers:
      // - Independent single/multiple projection and aggregate entry points
      // after sorting and pagination.
      // Expected: ID 5 is retained instead of ID 1; count is one and numeric
      // aggregates use ID 5.
      test(
        'sorted distinct keeps the representative for $operation.',
        () async {
          // Arrange.
          final query = database.users
              .where()
              .emailEqualTo('team@example.com')
              .sortByName()
              .thenByDbIdDesc()
              .distinctByName()
              .offset(2)
              .limit(1);
          final property = query.dbIdProperty();
          // Act.
          final (actual, expected) = switch (operation) {
            'findAll' => (await property.findAll(), [5]),
            'findFirst' => (await property.findFirst(), 5),
            'properties' => (
              await query.properties(['dbId', 'name']).findAll(),
              [
                {'dbId': 5, 'name': 'Gamma'},
              ],
            ),
            'count' => (await property.count(), 1),
            'min' => (await property.min(), 5),
            'max' => (await property.max(), 5),
            'sum' => (await property.sum(), 5),
            _ => (await property.average(), 5.0),
          };
          // Assert.
          expect(actual, expected);
        },
      );
    }

    for (final selection in ['exact filter', 'sorted distinct']) {
      for (final operation in [
        'updateFirst',
        'updateAll',
        'deleteFirst',
        'deleteAll',
      ]) {
        // Scenario: An exact-filter or sorted-distinct window is updated or
        // deleted inside a transaction that aborts.
        // Covers:
        // - First/bulk mutations, fixed selected IDs, untouched rows and
        // transaction rollback.
        // Expected: Only the expected first row or selected pair changes;
        // rollback restores all six users and the original query results.
        test(
          '$selection: $operation preserves selected IDs and rollback.',
          () async {
            // Arrange.
            final query = selection == 'exact filter'
                ? database.users
                      .filter()
                      .displayNameEqualTo('team')
                      .sortByDbIdDesc()
                : database.users
                      .where()
                      .emailEqualTo('team@example.com')
                      .sortByName()
                      .thenByDbIdDesc()
                      .distinctByName()
                      .offset(1)
                      .limit(2);
            final selectedIds = selection == 'exact filter' ? [6, 3] : [3, 5];
            final affectedIds = operation.endsWith('First')
                ? selectedIds.take(1).toSet()
                : selectedIds.toSet();
            final rollback = StateError('rollback $selection $operation');
            // Act / Assert.
            await expectLater(
              database.writeTxn<void>(() async {
                switch (operation) {
                  case 'updateFirst':
                    expect(
                      await query.updateFirst({'name': 'Changed'}),
                      isTrue,
                    );
                  case 'updateAll':
                    expect(
                      await query.updateAll({'name': 'Changed'}),
                      affectedIds.length,
                    );
                  case 'deleteFirst':
                    expect(await query.deleteFirst(), isTrue);
                  case 'deleteAll':
                    expect(await query.deleteAll(), affectedIds.length);
                }
                final remaining = await database.users
                    .all()
                    .sortByDbId()
                    .findAll();
                final deleting = operation.startsWith('delete');
                expect(remaining.map((user) => user.dbId), [
                  for (final user in users)
                    if (!deleting || !affectedIds.contains(user.dbId))
                      user.dbId,
                ]);
                expect(remaining.map((user) => user.name), [
                  for (final user in users)
                    if (!deleting || !affectedIds.contains(user.dbId))
                      !deleting && affectedIds.contains(user.dbId)
                          ? 'Changed'
                          : user.name,
                ]);
                throw rollback;
              }),
              throwsA(same(rollback)),
            );
            await _expectWindow(database.users.all().sortByDbId(), [
              1,
              2,
              3,
              4,
              5,
              6,
            ], users);
            await _expectWindow(query, selectedIds, users);
          },
        );
      }
    }

    for (final source in ['where', 'filter', 'words', 'list']) {
      CindelQuery<User> selected() => switch (source) {
        'where' => database.users.where().emailEqualTo('team@example.com'),
        'filter' => database.users.filter().emailEqualTo('team@example.com'),
        'words' => database.users.where().bioWordEqualTo('flutter'),
        _ => database.users.filter().tagsElementEqualTo('one'),
      };

      // Scenario: A reusable indexed, word or list query is read during an
      // aborted write transaction.
      // Covers:
      // - Read-your-writes in projections and aggregates.
      // - ordered windows.
      // - rollback visibility.
      // Expected: Pending IDs are 2, 3, 5 and 7 with sum 17 and average 4.25;
      // rollback restores IDs 1, 2, 3 and 5.
      test('$source: projections see pending writes and rollback.', () async {
        // Arrange.
        final query = selected().sortByDbId();
        final rollback = StateError('rollback projection test');
        // Act / Assert.
        await expectLater(
          database.writeTxn<void>(() async {
            await database.users.delete(1);
            await database.users.put(
              User()
                ..dbId = 7
                ..name = 'New'
                ..email = 'team@example.com'
                ..bio = 'Flutter new'
                ..tags = ['one'],
            );
            final ids = query.dbIdProperty();
            expect(await ids.findAll(), [2, 3, 5, 7]);
            expect(await ids.findFirst(), 2);
            expect(await ids.count(), 4);
            expect(await ids.min(), 2);
            expect(await ids.max(), 7);
            expect(await ids.sum(), 17);
            expect(await ids.average(), 4.25);
            expect(
              await query.offset(2).limit(1).nameProperty().findFirst(),
              'Gamma',
            );
            throw rollback;
          }),
          throwsA(same(rollback)),
        );
        await _expectWindow(query, [1, 2, 3, 5], users);
      });
    }

    // Scenario: A word-prefix query projects both null and non-null display
    // names.
    // Covers:
    // - Null preservation in projections.
    // - non-null counts/extrema.
    // - all-null aggregate windows.
    // Expected: Mixed values remain in order, count ignores nulls, and an
    // all-null window has count zero and null aggregate values.
    test(
      'nullable projections ignore nulls and preserve an all-null window.',
      () async {
        // Arrange.
        final query = database.users
            .where()
            .bioWordStartsWith('flutt')
            .sortByDbId();
        final property = query.displayNameProperty();
        // Act / Assert.
        expect(await property.findAll(), ['TEAM', null, 'team', null, 'other']);
        expect(await property.count(), 3);
        expect(await property.min(), 'TEAM');
        expect(await property.max(), 'team');
        final nulls = query
            .filter()
            .displayNameEqualTo(null)
            .displayNameProperty();
        expect(await nulls.findAll(), [null, null]);
        expect(await nulls.findFirst(), isNull);
        expect(await nulls.count(), 0);
        expect(await nulls.min(), isNull);
        expect(await nulls.max(), isNull);
        expect(await nulls.sum(), isNull);
        expect(await nulls.average(), isNull);
      },
    );

    // Scenario: A word query projects strings for numeric aggregates and
    // lists for extrema.
    // Covers:
    // - Aggregate type validation through the generated property API.
    // Expected: String sum/average and list min/max fail with
    // CindelQueryError.
    test(
      'aggregates reject nonnumeric and noncomparable projected values.',
      () async {
        // Arrange.
        final query = database.users.where().bioWordEqualTo('flutter');
        // Act / Assert.
        await expectLater(
          query.nameProperty().sum(),
          throwsA(isA<CindelQueryError>()),
        );
        await expectLater(
          query.nameProperty().average(),
          throwsA(isA<CindelQueryError>()),
        );
        await expectLater(
          query.tagsProperty().min(),
          throwsA(isA<CindelQueryError>()),
        );
        await expectLater(
          query.tagsProperty().max(),
          throwsA(isA<CindelQueryError>()),
        );
      },
    );
  });
}

Recipient _recipient(String label) =>
    Recipient()..metadata = (RecipientMetadata()..label = label);

Future<void> _expectWindow(
  CindelQuery<User> query,
  List<int> expectedIds,
  List<User> fixtures,
) async {
  final expected = [for (final id in expectedIds) fixtures[id - 1]];
  expect((await query.findAll()).map((user) => user.dbId), expectedIds);
  expect(await query.count(), expectedIds.length);
  final ids = query.dbIdProperty();
  expect(await ids.findAll(), expectedIds);
  expect(await ids.findFirst(), expectedIds.firstOrNull);
  expect(await ids.count(), expectedIds.length);
  final sortedIds = expectedIds.toList()..sort();
  expect(await ids.min(), sortedIds.firstOrNull);
  expect(await ids.max(), sortedIds.lastOrNull);
  final sum = expectedIds.fold(0, (sum, id) => sum + id);
  expect(await ids.sum(), expectedIds.isEmpty ? null : sum);
  expect(
    await ids.average(),
    expectedIds.isEmpty ? null : sum / expectedIds.length,
  );
  final names = [for (final user in expected) user.name];
  expect(await query.nameProperty().findAll(), names);
  final labels = [for (final user in expected) user.displayName];
  final nonNullLabels = labels.nonNulls.toList()..sort();
  final labelProperty = query.displayNameProperty();
  expect(await labelProperty.findAll(), labels);
  expect(await labelProperty.findFirst(), labels.firstOrNull);
  expect(await labelProperty.count(), nonNullLabels.length);
  expect(await labelProperty.min(), nonNullLabels.firstOrNull);
  expect(await labelProperty.max(), nonNullLabels.lastOrNull);
  final documents = [
    for (final user in expected)
      {'dbId': user.dbId, 'name': user.name, 'displayName': user.displayName},
  ];
  final properties = query.properties(['dbId', 'name', 'displayName']);
  expect(await properties.findAll(), documents);
  expect(await properties.findFirst(), documents.firstOrNull);
}
