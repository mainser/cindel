import 'package:cindel/cindel.dart';
import 'package:test/test.dart';

import 'schema_generation_fixture.dart';

void main() {
  group('Cindel query builder', () {
    // Scenario: A generated where helper queries an indexed field by equality.
    // Covers:
    // - Generated [UserQueryWhere.emailEqualTo].
    // - [CindelQuery.findAll] typed document mapping.
    // Expected: Only matching typed objects are returned.
    test('finds typed objects by indexed equality.', () async {
      // Arrange.
      final database = await _openSeededUsers();
      addTearDown(database.close);

      // Act.
      final users = await database.users
          .where()
          .emailEqualTo('team@example.com')
          .findAll();

      // Assert.
      expect(users.map((user) => user.name), ['Ana', 'Cid']);
    });

    // Scenario: A generated where helper queries an indexed string prefix.
    // Covers:
    // - Generated [UserQueryWhere.emailStartsWith].
    // - Prefix query post-filtering after indexed range lookup.
    // Expected: Only typed objects whose indexed value starts with the prefix
    // are returned.
    test('finds typed objects by indexed string prefix.', () async {
      // Arrange.
      final database = await _openSeededUsers();
      addTearDown(database.close);

      // Act.
      final users = await database.users
          .where()
          .emailStartsWith('team')
          .findAll();

      // Assert.
      expect(users.map((user) => user.email), [
        'team-alpha@example.com',
        'team@example.com',
        'team@example.com',
      ]);
    });

    // Scenario: A generated where helper queries an indexed inclusive range.
    // Covers:
    // - Generated [UserQueryWhere.emailBetween].
    // - [CindelQuery.findAll] preserving native index ordering.
    // Expected: Range results are typed and ordered by indexed value.
    test('finds typed objects by indexed range.', () async {
      // Arrange.
      final database = await _openSeededUsers();
      addTearDown(database.close);

      // Act.
      final users = await database.users
          .where()
          .emailBetween('solo@example.com', 'team-alpha@example.com')
          .findAll();

      // Assert.
      expect(users.map((user) => user.email), [
        'solo@example.com',
        'team-alpha@example.com',
      ]);
    });

    // Scenario: A query requests just the first matching object.
    // Covers:
    // - [CindelQuery.findFirst].
    // - Null result for empty query results.
    // Expected: The first matching typed object is returned, or null.
    test('returns the first typed match or null.', () async {
      // Arrange.
      final database = await _openSeededUsers();
      addTearDown(database.close);

      // Act.
      final firstTeamUser = await database.users
          .where()
          .emailEqualTo('team@example.com')
          .findFirst();
      final missingUser = await database.users
          .where()
          .emailEqualTo('missing@example.com')
          .findFirst();

      // Assert.
      expect(firstTeamUser?.name, 'Ana');
      expect(missingUser, isNull);
    });

    // Scenario: A query requests the number of matching objects.
    // Covers:
    // - [CindelQuery.count].
    // - Count over a generated prefix query.
    // Expected: Count returns the number of matching documents without typed
    // object assertions.
    test('counts matching typed query results.', () async {
      // Arrange.
      final database = await _openSeededUsers();
      addTearDown(database.close);

      // Act.
      final count = await database.users
          .where()
          .emailStartsWith('team')
          .count();

      // Assert.
      expect(count, 3);
    });
  });
}

Future<CindelDatabase> _openSeededUsers() async {
  final database = await Cindel.openInMemory(schemas: [UserSchema]);
  await database.users.put(
    _user(id: 1, name: 'Ana', email: 'team@example.com'),
  );
  await database.users.put(
    _user(id: 2, name: 'Ben', email: 'solo@example.com'),
  );
  await database.users.put(
    _user(id: 3, name: 'Cid', email: 'team@example.com'),
  );
  await database.users.put(
    _user(id: 4, name: 'Dee', email: 'team-alpha@example.com'),
  );
  return database;
}

User _user({required int id, required String name, required String email}) {
  return User()
    ..id = id
    ..name = name
    ..email = email
    ..active = true;
}
