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

    // Scenario: A query deletes only its first matching object.
    // Covers:
    // - [CindelQuery.deleteFirst].
    // - Native batch delete path through query results.
    // Expected: One matching object is removed and missing queries return false.
    test('deletes the first matching typed query result.', () async {
      // Arrange.
      final database = await _openSeededUsers();
      addTearDown(database.close);

      // Act.
      final deleted = await database.users
          .where()
          .emailEqualTo('team@example.com')
          .deleteFirst();
      final remainingTeamUsers = await database.users
          .where()
          .emailEqualTo('team@example.com')
          .findAll();
      final missingDeleted = await database.users
          .where()
          .emailEqualTo('missing@example.com')
          .deleteFirst();

      // Assert.
      expect(deleted, isTrue);
      expect(remainingTeamUsers.map((user) => user.name), ['Cid']);
      expect(missingDeleted, isFalse);
    });

    // Scenario: A query deletes every matching object.
    // Covers:
    // - [CindelQuery.deleteAll].
    // - Atomic native delete for all matching ids.
    // Expected: Matching objects are removed and non-matching objects remain.
    test('deletes all matching typed query results.', () async {
      // Arrange.
      final database = await _openSeededUsers();
      addTearDown(database.close);

      // Act.
      final deletedCount = await database.users
          .where()
          .emailStartsWith('team')
          .deleteAll();
      final teamCount = await database.users
          .where()
          .emailStartsWith('team')
          .count();
      final soloUser = await database.users
          .where()
          .emailEqualTo('solo@example.com')
          .findFirst();

      // Assert.
      expect(deletedCount, 3);
      expect(teamCount, 0);
      expect(soloUser?.name, 'Ben');
    });

    // Scenario: A generated filter starts from the whole collection.
    // Covers:
    // - Generated [UserQueryFilter.activeEqualTo].
    // - Full collection scans through [CindelQuery.all].
    // Expected: Non-indexed bool filters can be used without a where clause.
    test('filters the whole typed collection by bool equality.', () async {
      // Arrange.
      final database = await _openSeededUsers();
      addTearDown(database.close);

      // Act.
      final inactiveUsers = await database.users
          .filter()
          .activeEqualTo(false)
          .findAll();

      // Assert.
      expect(inactiveUsers.map((user) => user.name), ['Cid']);
    });

    // Scenario: An indexed where clause is followed by a non-indexed filter.
    // Covers:
    // - Execution order: indexed where first, Dart filter second.
    // - Generated [UserQueryFilter.activeEqualTo] on an existing query.
    // Expected: The filter narrows the indexed result set.
    test('combines indexed where clauses with non-indexed filters.', () async {
      // Arrange.
      final database = await _openSeededUsers();
      addTearDown(database.close);

      // Act.
      final activeTeamUsers = await database.users
          .where()
          .emailEqualTo('team@example.com')
          .filter()
          .activeEqualTo(true)
          .findAll();

      // Assert.
      expect(activeTeamUsers.map((user) => user.name), ['Ana']);
    });

    // Scenario: String filters run over typed documents.
    // Covers:
    // - Generated string contains, startsWith, and endsWith filter helpers.
    // Expected: String predicates match only string fields.
    test('filters by string contains, startsWith, and endsWith.', () async {
      // Arrange.
      final database = await _openSeededUsers();
      addTearDown(database.close);

      // Act.
      final contains = await database.users
          .filter()
          .nameContains('e')
          .findAll();
      final startsWith = await database.users
          .filter()
          .nameStartsWith('A')
          .findAll();
      final endsWith = await database.users
          .filter()
          .nameEndsWith('n')
          .findAll();

      // Assert.
      expect(contains.map((user) => user.name), ['Ben', 'Dee']);
      expect(startsWith.map((user) => user.name), ['Ana']);
      expect(endsWith.map((user) => user.name), ['Ben']);
    });

    // Scenario: Numeric filters run over typed documents.
    // Covers:
    // - Generated comparison helpers for numeric fields.
    // - Inclusive generated between filters.
    // Expected: Numeric predicates preserve collection id ordering.
    test('filters by numeric comparisons.', () async {
      // Arrange.
      final database = await _openSeededUsers();
      addTearDown(database.close);

      // Act.
      final greaterThan = await database.users
          .filter()
          .idGreaterThan(2)
          .findAll();
      final between = await database.users.filter().idBetween(2, 3).findAll();

      // Assert.
      expect(greaterThan.map((user) => user.name), ['Cid', 'Dee']);
      expect(between.map((user) => user.name), ['Ben', 'Cid']);
    });

    // Scenario: Filters are composed manually with boolean groups.
    // Covers:
    // - [CindelFilter.all], [CindelFilter.any], and [CindelFilter.not].
    // - [CindelQuery.whereMatches] custom predicate composition.
    // Expected: Grouped predicates narrow query results predictably.
    test('supports all, any, and not filter groups.', () async {
      // Arrange.
      final database = await _openSeededUsers();
      addTearDown(database.close);

      // Act.
      final users = await database.users
          .where()
          .emailStartsWith('team')
          .whereMatches(
            CindelFilter.all([
              CindelFilter.any([
                CindelFilter.field('name').startsWith('A'),
                CindelFilter.field('name').startsWith('D'),
              ]),
              CindelFilter.not(CindelFilter.field('active').equalTo(false)),
            ]),
          )
          .findAll();

      // Assert.
      expect(users.map((user) => user.name), ['Dee', 'Ana']);
    });

    // Scenario: A query sorts, offsets, and limits typed results.
    // Covers:
    // - Generated sortBy and descending helpers.
    // - Query offset and limit windowing after sort.
    // Expected: Results are sorted before pagination is applied.
    test('sorts and paginates typed query results.', () async {
      // Arrange.
      final database = await _openSeededUsers();
      addTearDown(database.close);

      // Act.
      final users = await database.users
          .all()
          .sortByNameDesc()
          .offset(1)
          .limit(2)
          .findAll();

      // Assert.
      expect(users.map((user) => user.name), ['Cid', 'Ben']);
    });

    // Scenario: A query uses a secondary sort key.
    // Covers:
    // - Generated thenBy helpers.
    // - Stable tie-breaking after primary sort values match.
    // Expected: Duplicate names are ordered by the secondary email field.
    test('sorts by secondary keys.', () async {
      // Arrange.
      final database = await _openUsersWithDuplicateNames();
      addTearDown(database.close);

      // Act.
      final users = await database.users
          .all()
          .sortByName()
          .thenByEmailDesc()
          .findAll();

      // Assert.
      expect(users.map((user) => '${user.name}:${user.email}'), [
        'Ana:z@example.com',
        'Ana:a@example.com',
        'Ben:b@example.com',
      ]);
    });

    // Scenario: A query removes duplicate values after sorting.
    // Covers:
    // - Generated distinctBy helpers.
    // - Multi-field distinct tuples through [CindelQuery.distinctByFields].
    // Expected: Distinct keeps the first sorted result for each key.
    test('returns distinct results by one or multiple fields.', () async {
      // Arrange.
      final database = await _openUsersWithDuplicateNames();
      addTearDown(database.close);

      // Act.
      final distinctNames = await database.users
          .all()
          .sortByEmail()
          .distinctByName()
          .findAll();
      final distinctTuples = await database.users
          .all()
          .sortByEmail()
          .distinctByFields(['name', 'active'])
          .findAll();

      // Assert.
      expect(distinctNames.map((user) => user.email), [
        'a@example.com',
        'b@example.com',
      ]);
      expect(distinctTuples.map((user) => user.email), [
        'a@example.com',
        'b@example.com',
        'z@example.com',
      ]);
    });

    // Scenario: A query projects primitive field values.
    // Covers:
    // - Generated property projection helpers.
    // - Multi-property projections.
    // Expected: Projections preserve the query order and selected fields.
    test('projects primitive fields.', () async {
      // Arrange.
      final database = await _openSeededUsers();
      addTearDown(database.close);

      // Act.
      final names = await database.users
          .all()
          .sortById()
          .nameProperty()
          .findAll();
      final firstEmail = await database.users
          .all()
          .sortByNameDesc()
          .emailProperty()
          .findFirst();
      final rows = await database.users.all().sortById().limit(2).properties([
        'name',
        'active',
      ]).findAll();

      // Assert.
      expect(names, ['Ana', 'Ben', 'Cid', 'Dee']);
      expect(firstEmail, 'team-alpha@example.com');
      expect(rows, [
        {'name': 'Ana', 'active': true},
        {'name': 'Ben', 'active': true},
      ]);
    });

    // Scenario: Query modifiers are combined in the documented order.
    // Covers:
    // - Execution order: where, filter, sort, distinct, offset, limit,
    //   projection.
    // Expected: Pagination is applied after the distinct sorted result.
    test(
      'applies where, filter, sort, distinct, window, and projection in order.',
      () async {
        // Arrange.
        final database = await _openUsersForExecutionOrder();
        addTearDown(database.close);

        // Act.
        final names = await database.users
            .where()
            .emailStartsWith('team')
            .filter()
            .activeEqualTo(true)
            .sortByName()
            .distinctByEmail()
            .offset(1)
            .limit(2)
            .nameProperty()
            .findAll();

        // Assert.
        expect(names, ['Cid', 'Dee']);
      },
    );
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
    _user(id: 3, name: 'Cid', email: 'team@example.com', active: false),
  );
  await database.users.put(
    _user(id: 4, name: 'Dee', email: 'team-alpha@example.com'),
  );
  return database;
}

Future<CindelDatabase> _openUsersWithDuplicateNames() async {
  final database = await Cindel.openInMemory(schemas: [UserSchema]);
  await database.users.put(
    _user(id: 1, name: 'Ana', email: 'z@example.com', active: false),
  );
  await database.users.put(
    _user(id: 2, name: 'Ben', email: 'b@example.com', active: true),
  );
  await database.users.put(
    _user(id: 3, name: 'Ana', email: 'a@example.com', active: true),
  );
  return database;
}

Future<CindelDatabase> _openUsersForExecutionOrder() async {
  final database = await Cindel.openInMemory(schemas: [UserSchema]);
  await database.users.put(
    _user(id: 1, name: 'Bob', email: 'team-a@example.com', active: true),
  );
  await database.users.put(
    _user(id: 2, name: 'Ana', email: 'team-a@example.com', active: true),
  );
  await database.users.put(
    _user(id: 3, name: 'Cid', email: 'team-c@example.com', active: true),
  );
  await database.users.put(
    _user(id: 4, name: 'Dee', email: 'team-d@example.com', active: true),
  );
  await database.users.put(
    _user(id: 5, name: 'Eli', email: 'solo@example.com', active: true),
  );
  await database.users.put(
    _user(id: 6, name: 'Fox', email: 'team-f@example.com', active: false),
  );
  return database;
}

User _user({
  required int id,
  required String name,
  required String email,
  bool active = true,
}) {
  return User()
    ..id = id
    ..name = name
    ..email = email
    ..active = active;
}
