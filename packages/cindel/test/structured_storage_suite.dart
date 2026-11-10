import 'package:cindel/cindel.dart';
import 'package:test/test.dart';

import 'backend_test_support.dart';
import 'close_test_support_io.dart'
    if (dart.library.js_interop) 'close_test_support_web.dart';
import 'schema_generation_fixture.dart';
import 'type_compatibility_fixture.dart';

void main() {
  group('structured storage', () {
    for (final batch in [false, true]) {
      for (final first in [false, true]) {
        // Scenario: Object lists are written, updated, read and reopened.
        // Covers:
        // - put/putAll followed by updateFirst/updateAll and generated readers.
        // - Nested filters, projections and rollback on the same typed data.
        // Expected: Every route retains populated, empty and null values.
        test('preserves object lists (batch=$batch, first=$first).', () async {
          // Arrange.
          final directory = await createCloseTestDirectory();
          var db = await openTestDatabase(
            directory: directory,
            schemas: [UserSchema],
          );
          try {
            final user = User()
              ..dbId = 1
              ..name = 'Before'
              ..email = 'one@example.com'
              ..recipients = [Recipient()..name = '123'];
            if (batch) {
              await db.users.putAll([user]);
            } else {
              await db.users.put(user);
            }
            expect((await db.users.get(1))!.recipients!.single.name, '123');

            // Act.
            final query = db.users.all().filter().dbIdEqualTo(1);
            final update = {
              'primaryRecipient': {
                'name': '001',
                'address': 'é\u0000😀',
                'metadata': {'label': '2.0'},
              },
              'recipients': [
                {
                  'name': '001',
                  'address': 'é\u0000😀',
                  'metadata': {'label': '2.0'},
                },
              ],
            };
            if (first) {
              expect(await query.updateFirst(update), isTrue);
            } else {
              expect(await query.updateAll(update), 1);
            }

            // Assert.
            void check(User value) {
              expect(value.primaryRecipient!.name, '001');
              expect(value.recipients!.single.name, '001');
              expect(value.recipients!.single.address, 'é\u0000😀');
              expect(value.recipients!.single.metadata!.label, '2.0');
            }

            check((await db.users.get(1))!);
            check((await db.users.getAll([1])).single!);
            check((await query.findFirst())!);
            expect(
              await db.users
                  .all()
                  .filter()
                  .primaryRecipient((q) => q.nameEqualTo('001'))
                  .count(),
              1,
            );
            expect(
              (await query.recipientsProperty().findAll()).single!.single.name,
              '001',
            );
            await expectLater(
              db.writeTxn(() async {
                await query.updateAll({'recipients': <Object?>[]});
                expect((await db.users.get(1))!.recipients, isEmpty);
                throw StateError('rollback structured update');
              }),
              throwsStateError,
            );
            check((await db.users.get(1))!);
            await db.close();
            db = await openTestDatabase(
              directory: directory,
              schemas: [UserSchema],
            );
            check((await db.users.get(1))!);
            await db.users.all().updateAll({'recipients': <Object?>[]});
            expect((await db.users.get(1))!.recipients, isEmpty);
            await db.users.all().updateAll({'recipients': null});
            expect((await db.users.get(1))!.recipients, isNull);
          } finally {
            await db.close();
            await deleteCloseTestDirectory(directory);
          }
        });
      }
    }

    // Scenario: Numeric lists previously reached JSON filters as binary blobs.
    // Covers:
    // - Generated .filter() membership/length and native source .whereMatches().
    // - Query updates followed by list readers and projections.
    // Expected: Numeric values remain numeric and every query selects the row.
    test('queries numeric lists before and after updates.', () async {
      // Arrange.
      final directory = await createCloseTestDirectory();
      final db = await openTestDatabase(
        directory: directory,
        schemas: [UserSchema],
      );
      try {
        final c = db.users;
        await c.putAll([
          User()
            ..dbId = 1
            ..name = 'Numeric'
            ..email = 'numeric@example.com'
            ..scores = [42, -7],
        ]);
        // Act / Assert.
        for (var i = 0; i < 2; i++) {
          expect(await c.all().filter().scoresElementEqualTo(42).count(), 1);
          expect(await c.all().filter().scoresLengthEqualTo(2).count(), 1);
          expect(
            await c
                .all()
                .whereMatches(CindelFilter.field('scores').contains(42))
                .count(),
            1,
          );
          expect((await c.get(1))!.scores, [42, -7]);
          expect(await c.all().scoresProperty().findAll(), [
            [42, -7],
          ]);
          await c.all().updateAll({
            'scores': [42, -7],
          });
        }
      } finally {
        await db.close();
        await deleteCloseTestDirectory(directory);
      }
    });

    // Scenario: A list is named value, also a column exposed by json_each.
    // Covers:
    // - Generated and direct contains filters against the outer collection.
    // Expected: Both routes select the row before and after an update.
    test('qualifies lists named value in membership filters.', () async {
      // Arrange.
      final directory = await createCloseTestDirectory();
      final db = await openTestDatabase(
        directory: directory,
        schemas: [Modelc08Schema],
      );
      try {
        final c = db.typedCollection(Modelc08Schema);
        await c.putAll([
          Modelc08()
            ..dbId = 1
            ..value = [42, -7],
        ]);
        // Act / Assert.
        for (var i = 0; i < 2; i++) {
          expect(await c.all().filter().valueElementEqualTo(42).count(), 1);
          expect(
            await c
                .all()
                .whereMatches(CindelFilter.field('value').contains(42))
                .count(),
            1,
          );
          expect(await c.all().filter().valueElementEqualTo(99).count(), 0);
          await c.all().updateAll({
            'value': [42, -7],
          });
        }
      } finally {
        await db.close();
        await deleteCloseTestDirectory(directory);
      }
    });

    // Scenario: Whole-valued doubles must not become integer list elements.
    // Covers:
    // - JSON number encoding through puts and query updates, including subnormal values.
    // Expected: Double values survive every read, with existing zero normalization.
    test('preserves double lists and numeric precision.', () async {
      // Arrange.
      final directory = await createCloseTestDirectory();
      final db = await openTestDatabase(
        directory: directory,
        schemas: [Modelc14Schema],
      );
      try {
        final c = db.typedCollection(Modelc14Schema);
        final values = [2.0, -0.0, 1.2345678901234567, 5e-324];
        await c.putAll([
          Modelc14()
            ..dbId = 1
            ..value = values,
        ]);
        // Act / Assert.
        for (var i = 0; i < 2; i++) {
          final actual = (await c.get(1))!.value;
          expect(actual, values);

          expect(await c.all().valueProperty().findAll(), [values]);
          await c.all().updateAll({'value': values});
        }
      } finally {
        await db.close();
        await deleteCloseTestDirectory(directory);
      }
    });
  });
}
