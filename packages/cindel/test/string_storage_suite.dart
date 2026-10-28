import 'package:cindel/cindel.dart';
import 'package:test/test.dart';

import 'backend_test_support.dart';
import 'close_test_support_io.dart'
    if (dart.library.js_interop) 'close_test_support_web.dart';
import 'schema_generation_fixture.dart';

void main() {
  group('String storage fidelity', () {
    const values = [
      '00123',
      '123',
      '+007',
      '-0',
      '1e3',
      '1000',
      '3.1400',
      ' 42 ',
      '999999999999999999999999999999',
      '',
      '0x10',
      'texto 😀',
    ];
    late String directory;
    late CindelDatabase db;
    setUp(() async {
      directory = await createCloseTestDirectory();
      addTearDown(() => deleteCloseTestDirectory(directory));
      db = await openTestDatabase(directory: directory, schemas: [UserSchema]);
      addTearDown(() => db.close());
    });

    Future<void> reopen() async {
      await db.close();
      db = await openTestDatabase(directory: directory, schemas: [UserSchema]);
    }

    User row(int id, String value) => User()
      ..dbId = id
      ..name = value
      ..email = value
      ..displayName = value
      ..tags = [value];

    Future<void> checkValues() async {
      final rows = await db.users.all().sortByDbId().findAll();
      expect(rows.map((r) => r.name), values);
      expect(rows.map((r) => r.email), values);
      expect(rows.map((r) => r.displayName), values);
      expect(rows.map((r) => r.tags.single), values);
      for (var i = 0; i < values.length; i++) {
        expect((await db.users.get(i + 1))!.name, values[i]);
        expect(
          (await db.users.where().emailEqualTo(values[i]).findAll()).map(
            (r) => r.dbId,
          ),
          [i + 1],
        );
        expect(await db.users.filter().nameEqualTo(values[i]).count(), 1);
      }
      final sorted = [...values]..sort();
      expect(
        await db.users.all().sortByName().nameProperty().findAll(),
        sorted,
      );
      expect(await db.users.all().distinctByName().count(), values.length);
    }

    for (final batch in [false, true]) {
      // Scenario: Numeric-looking text is inserted in required, nullable and
      // indexed strings, with a list holding the same value for comparison.
      // Covers: put/putAll, generated readers, indexes, filters, ordering and reopen.
      // Expected: Every character survives and numerically equal strings stay distinct.
      test('put batch=$batch preserves exact strings after reopen.', () async {
        // Arrange.
        final rows = [
          for (var i = 0; i < values.length; i++) row(i + 1, values[i]),
        ];
        // Act.
        if (batch) {
          await db.users.putAll(rows);
        } else {
          for (final value in rows) {
            await db.users.put(value);
          }
        }
        // Assert.
        await checkValues();
        await reopen();
        await checkValues();
      });
    }

    for (final first in [false, true]) {
      for (final useWhere in [false, true]) {
        // Scenario: A generated query assigns numeric-looking strings to an
        // existing row and repeats through all representative textual forms.
        // Covers: updateFirst/updateAll, where/filter, nullable fields and reopen.
        // Expected: Updates preserve exact text through every public read path.
        test(
          'update first=$first where=$useWhere preserves strings.',
          () async {
            // Arrange.
            await db.users.putAll([
              for (var i = 0; i < values.length; i++) row(i + 1, 'initial-$i'),
            ]);
            // Act.
            for (var i = 0; i < values.length; i++) {
              final query = useWhere
                  ? db.users.where().emailEqualTo('initial-$i')
                  : db.users.filter().dbIdEqualTo(i + 1);
              final changes = <String, Object?>{
                'name': values[i],
                'email': values[i],
                'displayName': values[i],
                'tags': [values[i]],
              };
              if (first) {
                expect(await query.updateFirst(changes), isTrue);
              } else {
                expect(await query.updateAll(changes), 1);
              }
            }
            // Assert.
            await checkValues();
            await reopen();
            await checkValues();
          },
        );
      }
    }

    // Scenario: A numeric string update is rolled back, then a nullable string
    // is explicitly cleared in a committed operation.
    // Covers: Transaction visibility, rollback and SQL NULL versus textual zero.
    // Expected: Rollback restores the original text; null remains null after reopen.
    test('string updates preserve rollback and null.', () async {
      // Arrange.
      await db.users.put(row(1, '00123'));
      // Act / Assert.
      await expectLater(
        db.writeTxn(() async {
          await db.users.filter().dbIdEqualTo(1).updateFirst({'name': '1e3'});
          expect((await db.users.get(1))!.name, '1e3');
          throw StateError('rollback');
        }),
        throwsStateError,
      );
      expect((await db.users.get(1))!.name, '00123');
      await db.users.filter().dbIdEqualTo(1).updateAll({'displayName': null});
      await reopen();
      expect((await db.users.get(1))!.displayName, isNull);
      expect((await db.users.get(1))!.name, '00123');
    });
  });
}
