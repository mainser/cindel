import 'package:cindel/cindel.dart';
import 'package:test/test.dart';

import 'backend_test_support.dart';
import 'close_test_support_io.dart'
    if (dart.library.js_interop) 'close_test_support_web.dart';
import 'schema_generation_fixture.dart';

// Run the same public calls and expectations on both native backends and Web.
// Use generated schemas; no backend-specific expectations or private readers.
void main() {
  group('Cindel public query contracts', () {
    late CindelDatabase database;
    late CindelQuery<User> all;

    setUp(() async {
      final directory = await createCloseTestDirectory();
      addTearDown(() => deleteCloseTestDirectory(directory));
      database = await openTestDatabase(
        directory: directory,
        schemas: [UserSchema],
      );
      addTearDown(database.close);
      await database.users.putAll([
        for (var id = 1; id <= 4; id++)
          User()
            ..dbId = id
            ..name = ['Alpha', 'Beta', 'Alpha', 'Gamma'][id - 1]
            ..email = id <= 2 ? 'team@example.com' : 'solo$id@example.com'
            ..active = id.isOdd
            ..displayName = ['TEAM', 'team', null, 'other'][id - 1]
            ..accessToken = id <= 2 ? 'shared' : 'token$id'
            ..bio = ['Flutter database', 'Flutter app', '', null][id - 1]
            ..tags = [
              ['one', 'two'],
              ['one'],
              <String>[],
              ['three'],
            ][id - 1]
            ..primaryRecipient = (Recipient()
              ..metadata = (RecipientMetadata()..label = 'label$id')),
      ]);
      all = database.users.all().sortByDbId();
    });

    Future<List<String>> names() async =>
        (await all.findAll()).map((user) => user.name).toList();

    for (final indexedSource in [false, true]) {
      for (final transaction in [false, true]) {
        // Scenario: An ordered unlimited update changes an unindexed property.
        // Covers: Generated where/filter paths, transaction overlays and query reuse.
        // Expected: Both selected users change; other fields and query order survive.
        test('ordered unlimited update where=$indexedSource '
            'transaction=$transaction preserves selection.', () async {
          // Arrange.
          final query =
              (indexedSource
                      ? database.users.where().emailEqualTo('team@example.com')
                      : database.users.filter().emailEqualTo(
                          'team@example.com',
                        ))
                  .sortByNameDesc()
                  .thenByDbId();
          Future<void> update() async {
            expect(await query.updateAll({'sessionLength': 1234}), 2);
            expect((await query.findAll()).map((row) => row.dbId), [2, 1]);
          }

          // Act.
          if (transaction) {
            await database.writeTxn(update);
          } else {
            await update();
          }
          // Assert.
          final rows = await all.findAll();
          expect(rows.map((row) => row.sessionLength?.inMicroseconds), [
            1234,
            1234,
            null,
            null,
          ]);
          expect(await names(), ['Alpha', 'Beta', 'Alpha', 'Gamma']);
          expect(
            await database.users
                .where()
                .emailEqualTo('team@example.com')
                .count(),
            2,
          );
        });
      }
    }

    // Scenario: Updating the sort/filter property makes every match stop matching.
    // Covers: Evaluation against the original rows and changing sort keys.
    // Expected: Each original match changes exactly once, without omitted rows.
    test(
      'ordered unlimited update changes its own filter and sort field.',
      () async {
        // Arrange.
        final query = database.users
            .filter()
            .nameContains('a')
            .sortByNameDesc();
        // Act.
        expect(await query.updateAll({'name': '0'}), 4);
        // Assert.
        expect(await names(), ['0', '0', '0', '0']);
        expect(await query.count(), 0);
      },
    );

    for (final mode in [
      'first',
      'limit',
      'offset',
      'window',
      'distinct',
      'zero',
    ]) {
      // Scenario: Ordered updates include a selection rule that depends on order.
      // Covers: updateFirst, limits, offsets and distinct representatives.
      // Expected: Only the rows in the original ordered selection are modified.
      test('ordered update preserves $mode selection.', () async {
        // Arrange.
        var query = database.users.all().sortByNameDesc().thenByDbId();
        final List<int> selected;
        switch (mode) {
          case 'first':
            selected = [4];
          case 'limit':
            query = query.limit(1);
            selected = [4];
          case 'offset':
            query = query.offset(1);
            selected = [2, 1, 3];
          case 'window':
            query = query.offset(1).limit(2);
            selected = [2, 1];
          case 'distinct':
            query = query.distinctByEmail();
            selected = [4, 2, 3];
          default:
            query = query.limit(0);
            selected = [];
        }
        // Act.
        if (mode == 'first') {
          expect(await query.updateFirst({'sessionLength': 1234}), isTrue);
        } else {
          expect(
            await query.updateAll({'sessionLength': 1234}),
            selected.length,
          );
        }
        // Assert.
        final changed = (await all.findAll())
            .where((row) => row.sessionLength != null)
            .map((row) => row.dbId);
        expect(changed, unorderedEquals(selected));
      });
    }

    // Scenario: An unlimited sorted update is followed by an explicit failure.
    // Covers: Transaction rollback for the path that may omit internal sorting.
    // Expected: No updated value persists after the failed transaction.
    test('ordered unlimited update rolls back.', () async {
      // Arrange.
      final query = database.users.all().sortByNameDesc();
      // Act.
      await expectLater(
        database.writeTxn(() async {
          expect(await query.updateAll({'name': 'pending'}), 4);
          throw StateError('rollback ordered update');
        }),
        throwsStateError,
      );
      // Assert.
      expect(await names(), ['Alpha', 'Beta', 'Alpha', 'Gamma']);
    });

    for (final indexedField in ['email', 'active']) {
      // Scenario: An ordered update changes a simple or composite index member.
      // Covers: Index maintenance and selection with indexed mutations.
      // Expected: Stored values and index-based queries agree after the update.
      test(
        'ordered unlimited update maintains index member $indexedField.',
        () async {
          // Arrange.
          final query = database.users.all().sortByNameDesc();
          // Act.
          expect(
            await query.updateAll({
              indexedField: indexedField == 'email' ? 'new@example.com' : false,
            }),
            4,
          );
          // Assert.
          if (indexedField == 'email') {
            expect(
              await database.users
                  .where()
                  .emailEqualTo('new@example.com')
                  .count(),
              4,
            );
            expect(
              await database.users
                  .where()
                  .emailEqualTo('team@example.com')
                  .count(),
              0,
            );
          } else {
            expect(
              (await all.findAll()).every((row) => row.active == false),
              isTrue,
            );
            expect(
              await database.users.filter().activeEqualTo(false).count(),
              4,
            );
          }
        },
      );
    }

    for (final limit in <int?>[null, 3]) {
      // Scenario: An ordered query starts at offset one with an optional
      // existing limit.
      // Covers:
      // - updateFirst row selection and query reuse.
      // Expected: Only Beta changes, updateFirst returns true and the
      // reusable query still counts three rows.
      test(
        'updateFirst changes one row with limit $limit and offset.',
        () async {
          // Arrange.
          var query = all.offset(1);
          if (limit != null) {
            query = query.limit(limit);
          }
          // Act / Assert.
          expect(await query.updateFirst({'name': 'changed'}), isTrue);
          expect(await names(), ['Alpha', 'changed', 'Alpha', 'Gamma']);
          expect(
            await query.count(),
            3,
            reason: 'The reusable query keeps its window.',
          );
        },
      );
    }

    // Scenario: An update targets two rows after skipping the first ordered
    // user.
    // Covers:
    // - updateAll count and ordered offset/limit selection.
    // Expected: Exactly two names change and the first and last users remain
    // untouched.
    test('updateAll changes exactly the ordered window.', () async {
      // Arrange: use the inputs described in this scenario.
      // Act.
      final changed = await all.offset(1).limit(2).updateAll({
        'name': 'changed',
      });
      // Assert.
      expect(changed, 2);
      expect(await names(), ['Alpha', 'changed', 'changed', 'Gamma']);
    });

    for (final first in [true, false]) {
      for (final window in [(0, 0), (0, 1), (0, 2), (1, 1), (5, 1)]) {
        // Scenario: An unsorted limited update changes the field used by its
        // filter, with nonmatching rows between and after the original matches.
        // Covers:
        // - updateFirst/updateAll window selection, zero limits and offsets.
        // - Equivalent generated API behavior in MDBX, SQLite native and Web.
        // Expected: Only the original matching IDs inside the window change;
        // skipped and nonmatching rows remain intact and the count is exact.
        test('unsorted ${first ? 'updateFirst' : 'updateAll'} preserves '
            'sparse window $window.', () async {
          // Arrange.
          final query = database.users
              .filter()
              .nameEqualTo('Alpha')
              .offset(window.$1)
              .limit(window.$2);
          final expectedIds = [1, 3]
              .skip(window.$1)
              .take(first && window.$2 > 0 ? 1 : window.$2)
              .toList();
          // Act.
          final result = first
              ? await query.updateFirst({'name': 'changed'})
              : await query.updateAll({'name': 'changed'});
          // Assert.
          expect(result, first ? expectedIds.isNotEmpty : expectedIds.length);
          expect(await names(), [
            for (var id = 1; id <= 4; id++)
              expectedIds.contains(id)
                  ? 'changed'
                  : ['Alpha', 'Beta', 'Alpha', 'Gamma'][id - 1],
          ]);
        });
      }

      // Scenario: An unsorted sparse update runs inside a transaction that fails.
      // Covers:
      // - Visibility and rollback for first/bulk updates with offset and limit.
      // Expected: Only ID 3 changes inside the transaction and all names return
      // after rollback on each backend.
      test('unsorted ${first ? 'updateFirst' : 'updateAll'} rolls back '
          'its sparse window.', () async {
        // Arrange.
        final query = database.users
            .filter()
            .nameEqualTo('Alpha')
            .offset(1)
            .limit(1);
        // Act / Assert.
        await expectLater(
          database.writeTxn<void>(() async {
            final result = first
                ? await query.updateFirst({'name': 'pending'})
                : await query.updateAll({'name': 'pending'});
            expect(result, first ? true : 1);
            expect(await names(), ['Alpha', 'Beta', 'pending', 'Gamma']);
            throw StateError('rollback sparse window');
          }),
          throwsStateError,
        );
        expect(await names(), ['Alpha', 'Beta', 'Alpha', 'Gamma']);
      });
    }

    // Scenario: A first-row delete is applied after an offset with a larger
    // limit.
    // Covers:
    // - deleteFirst within an existing ordered window.
    // Expected: Only ID 2 is deleted and IDs 1, 3 and 4 remain.
    test('deleteFirst preserves the rest of an ordered window.', () async {
      // Arrange: use the inputs described in this scenario.
      // Act / Assert.
      expect(await all.offset(1).limit(3).deleteFirst(), isTrue);
      expect(await all.dbIdProperty().findAll(), [1, 3, 4]);
    });

    // Scenario: A bulk delete targets a two-row ordered window.
    // Covers:
    // - deleteAll count and pagination boundaries.
    // Expected: The operation returns two and leaves only IDs 1 and 4.
    test('deleteAll removes only the ordered window.', () async {
      // Arrange: use the inputs described in this scenario.
      // Act / Assert.
      expect(await all.offset(1).limit(2).deleteAll(), 2);
      expect(await all.dbIdProperty().findAll(), [1, 4]);
    });

    for (final empty in ['zero limit', 'past end', 'missing filter']) {
      // Scenario: A query has a zero limit, an offset past the end or a
      // filter with no matches.
      // Covers:
      // - Empty-selection first/bulk updates and deletes.
      // Expected: First mutations return false, bulk mutations return zero
      // and all names remain unchanged.
      test('mutations on $empty leave every row unchanged.', () async {
        // Arrange.
        final query = switch (empty) {
          'zero limit' => all.offset(1).limit(0),
          'past end' => all.offset(100),
          _ => all.filter().nameEqualTo('missing'),
        };
        // Act / Assert.
        expect(await query.updateFirst({'name': 'changed'}), isFalse);
        expect(await query.updateAll({'name': 'changed'}), 0);
        expect(await query.deleteFirst(), isFalse);
        expect(await query.deleteAll(), 0);
        expect(await names(), ['Alpha', 'Beta', 'Alpha', 'Gamma']);
      });
    }

    // Scenario: First and bulk updates receive an empty changes map.
    // Covers:
    // - No-op update handling before database writes.
    // Expected: Both operations report no change and preserve every stored
    // name.
    test('empty changes are a no-op for first and bulk updates.', () async {
      // Arrange: use the inputs described in this scenario.
      // Act / Assert.
      expect(await all.updateFirst({}), isFalse);
      expect(await all.updateAll({}), 0);
      expect(await names(), ['Alpha', 'Beta', 'Alpha', 'Gamma']);
    });

    // Scenario: An explicit transaction updates two users, deletes another
    // and then throws.
    // Covers:
    // - Pending mutation visibility and rollback of combined updates/deletes.
    // Expected: Pending changes are visible inside writeTxn and all four
    // original names return after rollback.
    test('updates and deletes roll back together in writeTxn.', () async {
      // Arrange: use the inputs described in this scenario.
      // Act / Assert.
      await expectLater(
        database.writeTxn<void>(() async {
          expect(await all.limit(2).updateAll({'name': 'pending'}), 2);
          expect(await all.offset(3).deleteAll(), 1);
          expect(await names(), ['pending', 'pending', 'Alpha']);
          throw StateError('rollback public mutations');
        }),
        throwsStateError,
      );
      expect(await names(), ['Alpha', 'Beta', 'Alpha', 'Gamma']);
    });

    for (final invalid in <String, Object?>{
      'unsupported object': Object(),
      'non-finite number': double.infinity,
      'negative infinity': double.negativeInfinity,
      'NaN': double.nan,
      'non-finite list element': [double.infinity],
      'non-finite object value': {'value': double.infinity},
      'list with unsupported element': [Object()],
      'object with non-string key': {1: 'value'},
    }.entries) {
      // Scenario: An update mixes a valid name change with an invalid value
      // variant.
      // Covers:
      // - Native update value validation, including nested or non-finite
      // inputs.
      // Expected: ArgumentError is raised before any valid sibling field is
      // written.
      test(
        'rejects ${invalid.key} before writing valid sibling fields.',
        () async {
          // Arrange: use the inputs described in this scenario.
          // Act / Assert.
          await expectLater(
            all.updateAll({'name': 'changed', 'tags': invalid.value}),
            throwsArgumentError,
          );
          expect(await names(), ['Alpha', 'Beta', 'Alpha', 'Gamma']);
        },
      );
    }

    // Scenario: An update includes an ID change or an unknown field alongside
    // a valid name.
    // Covers:
    // - Immutable IDs, schema validation and all-or-nothing property
    // validation.
    // Expected: The calls fail with the expected error classes and preserve
    // IDs and names.
    test(
      'rejects changing IDs and unknown update fields atomically.',
      () async {
        // Arrange: use the inputs described in this scenario.
        // Act / Assert.
        await expectLater(
          all.updateAll({'name': 'changed', 'dbId': 9}),
          throwsArgumentError,
        );
        await expectLater(
          all.updateAll({'name': 'changed', 'missing': 'value'}),
          throwsA(isA<CindelSchemaError>()),
        );
        expect(await all.dbIdProperty().findAll(), [1, 2, 3, 4]);
        expect(await names(), ['Alpha', 'Beta', 'Alpha', 'Gamma']);
      },
    );

    // Scenario: One user receives null, list and embedded-object property
    // updates.
    // Covers:
    // - Generated embedded encoding, nested metadata and nullable object
    // replacement.
    // Expected: The selected row round-trips all values, its neighbor stays
    // unchanged and the embedded object can be cleared.
    test(
      'updates null, list and embedded values through the typed schema.',
      () async {
        // Arrange.
        final replacement = User()
          ..name = 'unused'
          ..email = 'unused@example.com'
          ..primaryRecipient = (Recipient()
            ..name = 'Recipient'
            ..metadata = (RecipientMetadata()..label = 'updated'));
        final embedded = UserSchema.toDocument(replacement)['primaryRecipient'];
        // Act / Assert.
        expect(
          await all.limit(1).updateAll({
            'displayName': null,
            'tags': ['new', 'value'],
            'primaryRecipient': embedded,
          }),
          1,
        );
        final user = (await database.users.get(1))!;
        expect(user.displayName, isNull);
        expect(user.tags, ['new', 'value']);
        expect(user.primaryRecipient!.name, 'Recipient');
        expect(user.primaryRecipient!.metadata!.label, 'updated');
        expect((await database.users.get(2))!.tags, ['one']);
        expect(
          await all.limit(1).primaryRecipientProperty().findFirst(),
          isNotNull,
        );
        expect(await all.limit(1).updateAll({'primaryRecipient': null}), 1);
        expect((await database.users.get(1))!.primaryRecipient, isNull);
      },
    );

    // Scenario: An embedded property update is observed inside a transaction
    // that throws.
    // Covers:
    // - Nested typed hydration and rollback of native property writes.
    // Expected: The pending label is readable inside the transaction and
    // label1 is restored afterward.
    test('embedded query updates roll back with their transaction.', () async {
      // Arrange: use the inputs described in this scenario.
      // Act / Assert.
      await expectLater(
        database.writeTxn<void>(() async {
          expect(
            await all.limit(1).updateAll({
              'primaryRecipient': {
                'metadata': {'label': 'pending'},
              },
            }),
            1,
          );
          expect(
            (await database.users.get(1))!.primaryRecipient!.metadata!.label,
            'pending',
          );
          throw StateError('rollback embedded update');
        }),
        throwsStateError,
      );
      expect(
        (await database.users.get(1))!.primaryRecipient!.metadata!.label,
        'label1',
      );
    });

    // Scenario: Embedded-label and list-length predicates are composed with
    // AND, OR and NOT.
    // Covers:
    // - Nested predicate evaluation, typed projections and ordered query
    // counts.
    // Expected: IDs 1 and 2 match, the paged name is Beta and empty windows
    // count zero.
    test(
      'nested filters preserve AND, OR, NOT and an ordered window.',
      () async {
        // Arrange.
        final query = all.whereMatches(
          CindelFilter.all([
            CindelFilter.any([
              CindelFilter.path([
                'primaryRecipient',
                'metadata',
                'label',
              ]).equalTo('label1'),
              CindelFilter.field('tags').lengthEqualTo(1),
            ]),
            CindelFilter.not(CindelFilter.field('name').equalTo('Gamma')),
          ]),
        );
        // Act / Assert.
        expect(await query.dbIdProperty().findAll(), [1, 2]);
        expect(await query.offset(1).limit(1).nameProperty().findAll(), [
          'Beta',
        ]);
        expect(await query.count(), 2);
        expect(await query.offset(1).limit(1).count(), 1);
        expect(await query.limit(0).count(), 0);
        expect(await query.offset(5).count(), 0);
      },
    );

    // Scenario: A list-length filter is combined with an offset before
    // deleting results.
    // Covers:
    // - Dart-evaluated selection for first/bulk deletes and exhausted
    // queries.
    // Expected: Only matching IDs 4 then 2 are deleted; later deletes report
    // no matches.
    test('Dart-evaluated deletes preserve filtering and the window.', () async {
      // Arrange.
      final query = all.whereMatches(
        CindelFilter.field('tags').lengthEqualTo(1),
      );
      // Act / Assert.
      expect(await query.offset(1).deleteFirst(), isTrue);
      expect(await all.dbIdProperty().findAll(), [1, 2, 3]);
      expect(await query.deleteAll(), 1);
      expect(await all.dbIdProperty().findAll(), [1, 3]);
      expect(await query.deleteFirst(), isFalse);
      expect(await query.deleteAll(), 0);
    });

    // Scenario: A normalized display-name index is queried with mixed-case
    // text.
    // Covers:
    // - Indexed equality normalization, null exclusion, sorting and query
    // reuse.
    // Expected: IDs 1 and 2 match, the paged name is Beta and a missing value
    // counts zero.
    test(
      'case-insensitive indexed equality preserves nulls and sorting.',
      () async {
        // Arrange.
        final query = database.users
            .where()
            .displayNameEqualTo('TeAm')
            .sortByDbId();
        // Act / Assert.
        expect(await query.count(), 2);
        expect(await query.dbIdProperty().findAll(), [1, 2]);
        expect(await query.offset(1).limit(1).nameProperty().findAll(), [
          'Beta',
        ]);
        expect(await query.count(), 2);
        expect(
          await database.users.where().displayNameEqualTo('missing').count(),
          0,
        );
      },
    );

    // Scenario: Generated where helpers query prefixes, a hash index and a
    // composite index.
    // Covers:
    // - Empty/nonempty prefixes, exact hash equality and both composite
    // components.
    // Expected: The projected ID lists match the explicitly listed users for
    // each source.
    test(
      'indexed prefixes, hash equality and composite equality select IDs.',
      () async {
        // Arrange: use the inputs described in this scenario.
        // Act / Assert.
        expect(
          await database.users
              .where()
              .emailStartsWith('')
              .sortByDbId()
              .dbIdProperty()
              .findAll(),
          [1, 2, 3, 4],
        );
        expect(
          await database.users
              .where()
              .emailStartsWith('team')
              .sortByDbId()
              .dbIdProperty()
              .findAll(),
          [1, 2],
        );
        expect(
          await database.users
              .where()
              .accessTokenEqualTo('shared')
              .sortByDbId()
              .dbIdProperty()
              .findAll(),
          [1, 2],
        );
        expect(
          await database.users
              .where()
              .emailActiveEqualTo('team@example.com', false)
              .dbIdProperty()
              .findAll(),
          [2],
        );
      },
    );

    // Scenario: Word equality and prefix helpers receive punctuation-only
    // input.
    // Covers:
    // - Empty tokenization results for generated word queries.
    // Expected: Equality counts zero and prefix lookup returns an empty list.
    test('word searches with no searchable tokens match nothing.', () async {
      // Arrange: use the inputs described in this scenario.
      // Act / Assert.
      expect(await database.users.where().bioWordEqualTo('!!!').count(), 0);
      expect(
        await database.users.where().bioWordStartsWith('!!!').findAll(),
        isEmpty,
      );
    });

    // Scenario: A case-insensitive word index receives uppercase text, extra
    // tokens or a substring.
    // Covers:
    // - Token normalization, first searchable token, word boundaries and
    // pagination.
    // Expected: FLUTTER selects IDs 1 and 2; extra tokens do not change that
    // selection and lutter matches nothing.
    test('word equality uses the case-insensitive index.', () async {
      // Arrange: use the inputs described in this scenario.
      // Act / Assert.
      expect(
        await database.users
            .where()
            .bioWordEqualTo('FLUTTER')
            .sortByDbId()
            .dbIdProperty()
            .findAll(),
        [1, 2],
      );
      final query = database.users
          .where()
          .bioWordEqualTo('FLUTTER ignored')
          .sortByDbId();
      expect(await query.count(), 2);
      expect(await query.offset(1).limit(1).nameProperty().findAll(), ['Beta']);
      expect(await query.offset(1).count(), 1);
      expect(
        await database.users.where().bioWordEqualTo('lutter').findAll(),
        isEmpty,
      );
    });

    // Scenario: A word-prefix query receives lower/uppercase prefixes and an
    // interior substring.
    // Covers:
    // - Prefix normalization, first-token selection and token-start
    // boundaries.
    // Expected: dat and DAT select ID 1 while ata matches nothing.
    test('word prefixes use the case-insensitive index.', () async {
      // Arrange: use the inputs described in this scenario.
      // Act / Assert.
      expect(
        await database.users
            .where()
            .bioWordStartsWith('dat')
            .dbIdProperty()
            .findAll(),
        [1],
      );
      expect(
        await database.users.where().bioWordStartsWith('DAT ignored').count(),
        1,
      );
      expect(
        await database.users.where().bioWordStartsWith('ata').findAll(),
        isEmpty,
      );
    });

    // Scenario: Word-query factories target a field without a word index.
    // Covers:
    // - Schema validation in wordsContain and wordsStartWith.
    // Expected: Both factories reject the field with CindelQueryError.
    test('word helpers reject fields without a word index.', () {
      // Arrange: use the inputs described in this scenario.
      // Act / Assert.
      expect(
        () => CindelQuery.wordsContain(
          database: database,
          schema: UserSchema,
          field: 'name',
          word: 'Alpha',
        ),
        throwsA(isA<CindelQueryError>()),
      );
      expect(
        () => CindelQuery.wordsStartWith(
          database: database,
          schema: UserSchema,
          field: 'name',
          prefix: 'Al',
        ),
        throwsA(isA<CindelQueryError>()),
      );
    });

    for (final source in ['words', 'normalized equality']) {
      // Scenario: Word or normalized-string queries mutate their selected
      // users through paged operations.
      // Covers:
      // - Read/write selection parity, empty windows, rollback and first/bulk
      // deletes.
      // Expected: Only the expected users change; rollback restores names and
      // deletes eventually leave IDs 3 and 4.
      test('$source mutations use the same selection as reads.', () async {
        // Arrange.
        final query = source == 'words'
            ? database.users.where().bioWordEqualTo('FLUTTER').sortByDbId()
            : database.users.where().displayNameEqualTo('TeAm').sortByDbId();
        // Act / Assert.
        expect(await query.limit(0).updateAll({'name': 'untouched'}), 0);
        expect(
          await query.offset(10).updateFirst({'name': 'untouched'}),
          isFalse,
        );
        expect(await query.offset(1).updateFirst({'name': 'updated'}), isTrue);
        expect(await names(), ['Alpha', 'updated', 'Alpha', 'Gamma']);
        await expectLater(
          database.writeTxn<void>(() async {
            expect(await query.updateAll({'name': 'pending'}), 2);
            throw StateError('rollback selected updates');
          }),
          throwsStateError,
        );
        expect(await names(), ['Alpha', 'updated', 'Alpha', 'Gamma']);
        expect(await query.offset(1).deleteFirst(), isTrue);
        expect(await all.dbIdProperty().findAll(), [1, 3, 4]);
        expect(await query.deleteAll(), 1);
        expect(await all.dbIdProperty().findAll(), [3, 4]);
      });
    }

    // Scenario: A word query matches 263 rows and updates the field that
    // determines membership.
    // Covers:
    // - Stable initial selection across ID batches, paged updates and
    // whole-transaction rollback.
    // Expected: Rollback restores all 263 matches; committing the 258-row
    // window leaves IDs 1, 262, 263, 264 and 265.
    test(
      'word updates preserve the initial selection across ID batches.',
      () async {
        // Arrange.
        await database.users.putAll([
          for (var id = 5; id <= 265; id++)
            User()
              ..dbId = id
              ..name = 'batch$id'
              ..email = 'batch$id@example.com'
              ..bio = 'Flutter',
        ]);
        final query = database.users
            .where()
            .bioWordEqualTo('FLUTTER')
            .sortByDbId();
        // Act / Assert.
        await expectLater(
          database.writeTxn<void>(() async {
            expect(await query.updateAll({'bio': 'different'}), 263);
            expect(await query.count(), 0);
            throw StateError('rollback all batches');
          }),
          throwsStateError,
        );
        expect(await query.count(), 263);
        expect(
          await query.offset(1).limit(258).updateAll({'bio': 'different'}),
          258,
        );
        expect(await query.dbIdProperty().findAll(), [1, 262, 263, 264, 265]);
      },
    );

    for (final modifier in <String, CindelQuery<User> Function()>{
      'negative offset': () => all.offset(-1),
      'negative limit': () => all.limit(-1),
      'empty distinct': () => all.distinctByFields([]),
      'blank distinct field': () => all.distinctByFields(['name', ' ']),
      'blank sort field': () => all.sortBy(' '),
      'blank secondary sort': () => all.thenBy(' '),
    }.entries) {
      // Scenario: A query modifier receives an invalid window or field
      // configuration.
      // Covers:
      // - Construction-time validation for each parameterized modifier.
      // Expected: The modifier throws ArgumentError before query execution.
      test('rejects ${modifier.key} at query construction.', () {
        // Arrange: use the inputs described in this scenario.
        // Act / Assert.
        expect(modifier.value, throwsArgumentError);
      });
    }

    // Scenario: A caller requests a projection with no fields.
    // Covers:
    // - Empty multi-property projection validation.
    // Expected: Query construction throws ArgumentError.
    test('rejects empty projections.', () {
      // Arrange: use the inputs described in this scenario.
      // Act / Assert.
      expect(() => all.properties([]), throwsArgumentError);
    });

    // Scenario: Single and multiple property projections contain a blank
    // field name.
    // Covers:
    // - Field-name validation before projection execution.
    // Expected: Both projection constructors throw ArgumentError.
    test('rejects blank property names.', () {
      // Arrange: use the inputs described in this scenario.
      // Act / Assert.
      expect(() => all.property<Object?>(' '), throwsArgumentError);
      expect(() => all.properties(['name', ' ']), throwsArgumentError);
    });

    // Scenario: An anyOf callback attempts to change pagination instead of
    // adding a predicate.
    // Covers:
    // - Repeated-filter callback shape validation.
    // Expected: Changing the offset inside anyOf throws ArgumentError.
    test('anyOf modifiers cannot change the query window.', () {
      // Arrange: use the inputs described in this scenario.
      // Act / Assert.
      expect(
        () => all.anyOf([1], (query, _) => query.offset(1)),
        throwsArgumentError,
      );
    });

    // Scenario: An allOf callback attempts to add distinct fields.
    // Covers:
    // - Repeated-filter callback restrictions on query shape.
    // Expected: Changing distinct inside allOf throws ArgumentError.
    test('allOf modifiers cannot change query distinct fields.', () {
      // Arrange: use the inputs described in this scenario.
      // Act / Assert.
      expect(
        () => all.allOf([1], (query, _) => query.distinctByName()),
        throwsArgumentError,
      );
    });

    // Scenario: A repeated filter is applied to an already filtered, sorted
    // and paged query.
    // Covers:
    // - Predicate composition, immutable query reuse and rejection of changed
    // sort/source shapes.
    // Expected: The derived and original windows contain ID 3, and callbacks
    // that replace the source or sort fail.
    test(
      'repeated modifiers preserve existing filters, sort and window.',
      () async {
        // Arrange.
        final query = all.filter().activeEqualTo(true).offset(1).limit(1);
        // Act.
        final filtered = query.anyOf([
          1,
          3,
          4,
        ], (query, id) => query.filter().dbIdEqualTo(id));
        // Assert.
        expect(await filtered.dbIdProperty().findAll(), [3]);
        expect(await query.dbIdProperty().findAll(), [3]);
        expect(
          await query
              .allOf([true], (query, _) => query)
              .dbIdProperty()
              .findAll(),
          [3],
        );
        expect(
          () => query.anyOf([1], (query, _) => query.sortByName()),
          throwsArgumentError,
        );
        expect(
          () => query.allOf([1], (query, _) => database.users.all()),
          throwsArgumentError,
        );
      },
    );

    // Scenario: Optional filters are disabled and repeated filters receive
    // empty or nonempty input.
    // Covers:
    // - Callback suppression, empty OR/AND semantics and preservation of the
    // original query.
    // Expected: The disabled callback is not invoked, empty anyOf matches
    // nothing, empty allOf keeps all rows and the original count stays four.
    test(
      'optional and repeated filters preserve the original query.',
      () async {
        // Arrange.
        var invoked = false;
        // Act.
        final disabled = all.optional(false, (query) {
          invoked = true;
          return query.limit(0);
        });
        // Assert.
        expect(invoked, isFalse);
        expect(await disabled.count(), 4);
        expect(
          await all
              .anyOf(<int>[], (query, id) => query.filter().dbIdEqualTo(id))
              .count(),
          0,
        );
        expect(
          await all
              .allOf(<int>[], (query, id) => query.filter().dbIdEqualTo(id))
              .count(),
          4,
        );
        expect(
          await all
              .anyOf([1, 4], (query, id) => query.filter().dbIdEqualTo(id))
              .dbIdProperty()
              .findAll(),
          [1, 4],
        );
        expect(await all.count(), 4);
      },
    );
  });
}
