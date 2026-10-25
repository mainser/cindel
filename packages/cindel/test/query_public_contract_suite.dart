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

    for (final limit in <int?>[null, 3]) {
      test(
        'updateFirst changes one row with limit $limit and offset.',
        () async {
          var query = all.offset(1);
          if (limit != null) {
            query = query.limit(limit);
          }
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

    test('updateAll changes exactly the ordered window.', () async {
      final changed = await all.offset(1).limit(2).updateAll({
        'name': 'changed',
      });
      expect(changed, 2);
      expect(await names(), ['Alpha', 'changed', 'changed', 'Gamma']);
    });

    test('deleteFirst preserves the rest of an ordered window.', () async {
      expect(await all.offset(1).limit(3).deleteFirst(), isTrue);
      expect(await all.dbIdProperty().findAll(), [1, 3, 4]);
    });

    test('deleteAll removes only the ordered window.', () async {
      expect(await all.offset(1).limit(2).deleteAll(), 2);
      expect(await all.dbIdProperty().findAll(), [1, 4]);
    });

    for (final empty in ['zero limit', 'past end', 'missing filter']) {
      test('mutations on $empty leave every row unchanged.', () async {
        final query = switch (empty) {
          'zero limit' => all.offset(1).limit(0),
          'past end' => all.offset(100),
          _ => all.filter().nameEqualTo('missing'),
        };
        expect(await query.updateFirst({'name': 'changed'}), isFalse);
        expect(await query.updateAll({'name': 'changed'}), 0);
        expect(await query.deleteFirst(), isFalse);
        expect(await query.deleteAll(), 0);
        expect(await names(), ['Alpha', 'Beta', 'Alpha', 'Gamma']);
      });
    }

    test('empty changes are a no-op for first and bulk updates.', () async {
      expect(await all.updateFirst({}), isFalse);
      expect(await all.updateAll({}), 0);
      expect(await names(), ['Alpha', 'Beta', 'Alpha', 'Gamma']);
    });

    test('updates and deletes roll back together in writeTxn.', () async {
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
      test(
        'rejects ${invalid.key} before writing valid sibling fields.',
        () async {
          await expectLater(
            all.updateAll({'name': 'changed', 'tags': invalid.value}),
            throwsArgumentError,
          );
          expect(await names(), ['Alpha', 'Beta', 'Alpha', 'Gamma']);
        },
      );
    }

    test(
      'rejects changing IDs and unknown update fields atomically.',
      () async {
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

    test(
      'updates null, list and embedded values through the typed schema.',
      () async {
        final replacement = User()
          ..name = 'unused'
          ..email = 'unused@example.com'
          ..primaryRecipient = (Recipient()
            ..name = 'Recipient'
            ..metadata = (RecipientMetadata()..label = 'updated'));
        final embedded = UserSchema.toDocument(replacement)['primaryRecipient'];
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

    test('embedded query updates roll back with their transaction.', () async {
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

    test(
      'nested filters preserve AND, OR, NOT and an ordered window.',
      () async {
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

    test('Dart-evaluated deletes preserve filtering and the window.', () async {
      final query = all.whereMatches(
        CindelFilter.field('tags').lengthEqualTo(1),
      );
      expect(await query.offset(1).deleteFirst(), isTrue);
      expect(await all.dbIdProperty().findAll(), [1, 2, 3]);
      expect(await query.deleteAll(), 1);
      expect(await all.dbIdProperty().findAll(), [1, 3]);
      expect(await query.deleteFirst(), isFalse);
      expect(await query.deleteAll(), 0);
    });

    test(
      'case-insensitive indexed equality preserves nulls and sorting.',
      () async {
        final query = database.users
            .where()
            .displayNameEqualTo('TeAm')
            .sortByDbId();
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

    test(
      'indexed prefixes, hash equality and composite equality select IDs.',
      () async {
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

    test('word searches with no searchable tokens match nothing.', () async {
      expect(await database.users.where().bioWordEqualTo('!!!').count(), 0);
      expect(
        await database.users.where().bioWordStartsWith('!!!').findAll(),
        isEmpty,
      );
    });

    test('word equality uses the case-insensitive index.', () async {
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

    test('word prefixes use the case-insensitive index.', () async {
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

    test('word helpers reject fields without a word index.', () {
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
      test('$source mutations use the same selection as reads.', () async {
        final query = source == 'words'
            ? database.users.where().bioWordEqualTo('FLUTTER').sortByDbId()
            : database.users.where().displayNameEqualTo('TeAm').sortByDbId();
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

    test(
      'word updates preserve the initial selection across ID batches.',
      () async {
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
      test('rejects ${modifier.key} at query construction.', () {
        expect(modifier.value, throwsArgumentError);
      });
    }

    test('rejects empty projections.', () {
      expect(() => all.properties([]), throwsArgumentError);
    });

    test('rejects blank property names.', () {
      expect(() => all.property<Object?>(' '), throwsArgumentError);
      expect(() => all.properties(['name', ' ']), throwsArgumentError);
    });

    test('anyOf modifiers cannot change the query window.', () {
      expect(
        () => all.anyOf([1], (query, _) => query.offset(1)),
        throwsArgumentError,
      );
    });

    test('allOf modifiers cannot change query distinct fields.', () {
      expect(
        () => all.allOf([1], (query, _) => query.distinctByName()),
        throwsArgumentError,
      );
    });

    test(
      'repeated modifiers preserve existing filters, sort and window.',
      () async {
        final query = all.filter().activeEqualTo(true).offset(1).limit(1);
        final filtered = query.anyOf([
          1,
          3,
          4,
        ], (query, id) => query.filter().dbIdEqualTo(id));
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

    test(
      'optional and repeated filters preserve the original query.',
      () async {
        var invoked = false;
        final disabled = all.optional(false, (query) {
          invoked = true;
          return query.limit(0);
        });
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
