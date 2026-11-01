import 'package:cindel/cindel.dart';
import 'package:test/test.dart';

import 'backend_test_support.dart';
import 'close_test_support_io.dart'
    if (dart.library.js_interop) 'close_test_support_web.dart';
import 'schema_generation_fixture.dart';
import 'nested_delete_suite.dart' as nested_delete;

void main() {
  nested_delete.main();
  group('Cindel selected query deletes', () {
    late CindelDatabase db;

    setUp(() async {
      final directory = await createCloseTestDirectory();
      addTearDown(() => deleteCloseTestDirectory(directory));
      db = await openTestDatabase(directory: directory, schemas: [UserSchema]);
      addTearDown(db.close);
      await db.users.putAll([
        for (var id = 1; id <= 6; id++)
          User()
            ..dbId = id
            ..name = id <= 3 ? 'A' : 'B'
            ..email = id == 6 ? 'other' : 'team'
            ..primaryRecipient = (Recipient()..name = id == 1 ? 'no' : 'yes'),
      ]);
    });

    for (final source in ['where', 'filter']) {
      for (final descending in [false, true]) {
        for (final window in ['all', 'first', 'offset', 'zero', 'past']) {
          // Scenario: Nested matches share distinct keys with excluded rows.
          // Covers:
          // - Generated where/filter, distinct, ordering, offset and limits.
          // - First/all deletion through the Dart-selected SQLite batch path.
          // Expected: Only the selected representatives disappear; counts and
          // every surviving object's fields are preserved.
          test('$source descending=$descending deletes $window.', () async {
            // Arrange.
            final candidates =
                (source == 'where'
                        ? db.users.where().emailEqualTo('team')
                        : db.users.filter().emailEqualTo('team'))
                    .filter()
                    .primaryRecipient((p) => p.nameEqualTo('yes'));
            var query =
                (descending
                        ? candidates.sortByDbIdDesc()
                        : candidates.sortByDbId())
                    .distinctByName();
            var expected = descending ? [5, 3] : [2, 4];
            switch (window) {
              case 'first':
                expected = expected.take(1).toList();
              case 'offset':
                query = query.offset(1).limit(1);
                expected = expected.skip(1).toList();
              case 'zero':
                query = query.limit(0);
                expected = [];
              case 'past':
                query = query.offset(2);
                expected = [];
            }

            // Act.
            final Object result = window == 'first'
                ? await query.deleteFirst()
                : await query.deleteAll();

            // Assert.
            expect(result, window == 'first' ? true : expected.length);
            final remaining = await db.users.all().sortByDbId().findAll();
            expect(remaining.map((r) => r.dbId), [
              for (var id = 1; id <= 6; id++)
                if (!expected.contains(id)) id,
            ]);
            for (final row in remaining) {
              expect(row.name, row.dbId <= 3 ? 'A' : 'B');
              expect(row.email, row.dbId == 6 ? 'other' : 'team');
              expect(row.primaryRecipient!.name, row.dbId == 1 ? 'no' : 'yes');
            }
            expect(await query.limit(0).deleteFirst(), isFalse);
          });
        }
      }
    }

    for (final first in [false, true]) {
      // Scenario: A nested query deletes rows before the outer transaction fails.
      // Covers:
      // - Read-your-writes, error propagation and rollback for first/all.
      // - Reusing the same query after rollback and an empty selection.
      // Expected: The controlled error is preserved and all rows are restored;
      // a later successful deletion removes only the expected rows.
      test('rolls back selected deletes, first=$first.', () async {
        // Arrange.
        final query = db.users
            .filter()
            .primaryRecipient((p) => p.nameEqualTo('yes'))
            .sortByDbId();
        final failure = StateError('abort selected delete');
        final expected = first ? [2] : [2, 3, 4, 5, 6];

        // Act.
        await expectLater(
          db.writeTxn(() async {
            if (first) {
              expect(await query.deleteFirst(), isTrue);
            } else {
              expect(await query.deleteAll(), 5);
            }
            expect(await db.users.getAll(expected), everyElement(isNull));
            throw failure;
          }),
          throwsA(same(failure)),
        );

        // Assert.
        expect(
          (await db.users.all().sortByDbId().findAll()).map((r) => r.dbId),
          [1, 2, 3, 4, 5, 6],
        );
        if (first) {
          expect(await query.deleteFirst(), isTrue);
        } else {
          expect(await query.deleteAll(), 5);
          expect(await query.deleteFirst(), isFalse);
          expect(await query.deleteAll(), 0);
        }
        expect(await db.users.getAll(expected), everyElement(isNull));
      });
    }
  });
}
