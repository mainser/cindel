import 'package:cindel/cindel.dart';
import 'package:test/test.dart';

import 'schema_generation_fixture.dart';

void main() {
  group('Cindel in-memory databases', () {
    // Scenario: An in-memory database registers a generated schema and stores
    // indexed typed objects.
    // Covers:
    // - [Cindel.openInMemory] schema registration.
    // - Typed collection writes over in-memory SQLite.
    // - Indexed equality and range queries without a file-backed directory.
    // Expected: Schema metadata, typed reads, and indexed queries work in memory.
    test('supports schemas, typed collections, and indexed queries.', () async {
      // Arrange.
      final database = await Cindel.openInMemory(schemas: [UserSchema]);
      addTearDown(database.close);
      final ana = User()
        ..id = 1
        ..name = 'Ana'
        ..email = 'ana@example.com'
        ..active = true;
      final ben = User()
        ..id = 2
        ..name = 'Ben'
        ..email = 'ben@example.com'
        ..active = false;

      // Act.
      await database.users.put(ana);
      await database.users.put(ben);
      final storedAna = await database.users.get(1);
      final exactMatches = await database.queryEqual(
        'users',
        'email',
        'ana@example.com',
      );
      final rangeMatches = await database.queryRange(
        'users',
        'email',
        lower: 'ana@example.com',
        upper: 'ben@example.com',
      );
      final version = await database.schemaVersion('users');

      // Assert.
      expect(database.directory, ':memory:');
      expect(storedAna, isNotNull);
      expect(storedAna!.name, 'Ana');
      expect(exactMatches.map((document) => document['id']), [1]);
      expect(rangeMatches.map((document) => document['id']), [1, 2]);
      expect(version, 1);
    });

    // Scenario: An in-memory database is closed and a new one is opened.
    // Covers:
    // - In-memory state lifetime is tied to the native database handle.
    // - Separate in-memory opens do not share persisted documents or schemas.
    // Expected: The second database starts empty.
    test('does not persist state between separate opens.', () async {
      // Arrange.
      final firstDatabase = await Cindel.openInMemory(schemas: [UserSchema]);

      // Act.
      await firstDatabase.put('users', 1, {
        'id': 1,
        'name': 'Ana',
        'email': 'ana@example.com',
        'active': true,
      });
      final storedUser = await firstDatabase.get('users', 1);
      await firstDatabase.close();

      final secondDatabase = await Cindel.openInMemory(schemas: [UserSchema]);
      addTearDown(secondDatabase.close);
      final missingUser = await secondDatabase.get('users', 1);
      final version = await secondDatabase.schemaVersion('users');

      // Assert.
      expect(storedUser, isNotNull);
      expect(missingUser, isNull);
      expect(version, 1);
    });
  });
}
