import 'package:cindel/cindel.dart';
import 'package:test/test.dart';

import 'backend_test_support.dart';

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

    // Scenario: A generated where helper queries a collection-level composite
    // index by its full value.
    // Covers:
    // - Generated [UserQueryWhere.emailActiveEqualTo].
    // - Native composite index key lookup.
    // Expected: Only documents matching every composite component are returned.
    test('finds typed objects by composite indexed equality.', () async {
      // Arrange.
      final database = await _openSeededUsers();
      addTearDown(database.close);

      // Act.
      final activeUsers = await database.users
          .where()
          .emailActiveEqualTo('team@example.com', true)
          .findAll();
      final inactiveUsers = await database.users
          .where()
          .emailActiveEqualTo('team@example.com', false)
          .findAll();

      // Assert.
      expect(activeUsers.map((user) => user.name), ['Ana']);
      expect(inactiveUsers.map((user) => user.name), ['Cid']);
    });

    // Scenario: A generated where helper queries a primitive list membership
    // through a multi-entry index.
    // Covers:
    // - Generated [UserQueryWhere.tagsContains].
    // - Case-insensitive multi-entry index values.
    // Expected: Documents containing the requested list item are returned.
    test('finds typed objects by multi-entry list membership.', () async {
      // Arrange.
      final database = await _openSeededUsers();
      addTearDown(database.close);

      // Act.
      final users = await database.users
          .where()
          .tagsContains('FLUTTER')
          .findAll();

      // Assert.
      expect(users.map((user) => user.name), ['Ana', 'Dee']);
    });

    // Scenario: Generated list query helpers filter by collection size.
    // Covers:
    // - Generated [UserQueryWhere.tagsIsEmpty].
    // - Generated [UserQueryWhere.tagsIsNotEmpty].
    // - Generated [UserQueryWhere.tagsLengthEqualTo].
    // - Generated [UserQueryWhere.tagsLengthLessThan].
    // - Generated [UserQueryWhere.tagsLengthGreaterThan].
    // - Generated [UserQueryWhere.tagsLengthBetween].
    // Expected: Empty, non-empty, exact, inclusive, and exclusive length
    // filters match Isar-style list query semantics.
    test('finds typed objects by list length helpers.', () async {
      // Arrange.
      final database = await _openSeededUsers();
      addTearDown(database.close);

      // Act.
      final emptyTags = await database.users
          .all()
          .filter()
          .tagsIsEmpty()
          .sortByDbId()
          .findAll();
      final nonEmptyTags = await database.users
          .all()
          .filter()
          .tagsIsNotEmpty()
          .sortByDbId()
          .findAll();
      final lengthTwo = await database.users
          .all()
          .filter()
          .tagsLengthEqualTo(2)
          .sortByDbId()
          .findAll();
      final lengthLessThanTwo = await database.users
          .all()
          .filter()
          .tagsLengthLessThan(2)
          .sortByDbId()
          .findAll();
      final lengthLessThanTwoInclusive = await database.users
          .all()
          .filter()
          .tagsLengthLessThan(2, include: true)
          .sortByDbId()
          .findAll();
      final lengthGreaterThanTwoInclusive = await database.users
          .all()
          .filter()
          .tagsLengthGreaterThan(2, include: true)
          .sortByDbId()
          .findAll();
      final lengthBetween = await database.users
          .all()
          .filter()
          .tagsLengthBetween(1, 2, includeLower: true, includeUpper: false)
          .sortByDbId()
          .findAll();
      final databaseTags = await database.users
          .all()
          .filter()
          .tagsElementEqualTo('database')
          .sortByDbId()
          .findAll();

      // Assert.
      expect(emptyTags.map((user) => user.name), ['Ben', 'Cid']);
      expect(nonEmptyTags.map((user) => user.name), ['Ana', 'Dee']);
      expect(lengthTwo.map((user) => user.name), ['Ana', 'Dee']);
      expect(lengthLessThanTwo.map((user) => user.name), ['Ben', 'Cid']);
      expect(lengthLessThanTwoInclusive.map((user) => user.name), [
        'Ana',
        'Ben',
        'Cid',
        'Dee',
      ]);
      expect(lengthGreaterThanTwoInclusive.map((user) => user.name), [
        'Ana',
        'Dee',
      ]);
      expect(lengthBetween.map((user) => user.name), isEmpty);
      expect(databaseTags.map((user) => user.name), ['Ana']);
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

    // Scenario: A filter-only query updates compact native bool fields.
    // Covers:
    // - [CindelQuery.updateAll].
    // - Native query-plan update count without Dart object hydration.
    // Expected: Matching documents are updated and the returned count matches.
    test('updates all matching native typed query results.', () async {
      // Arrange.
      final database = await openTestDatabaseInMemory(
        schemas: [ImmutableUserSchema],
      );
      addTearDown(database.close);
      await database.immutableUsers.putAll([
        const ImmutableUser(dbId: 1, email: 'a@example.com', active: true),
        const ImmutableUser(dbId: 2, email: 'b@example.com', active: false),
        const ImmutableUser(dbId: 3, email: 'c@example.com', active: true),
      ]);

      // Act.
      final updated = await database.immutableUsers
          .filter()
          .activeEqualTo(true)
          .updateAll({'active': false});
      final activeCount = await database.immutableUsers
          .filter()
          .activeEqualTo(true)
          .count();
      final inactive = await database.immutableUsers
          .filter()
          .activeEqualTo(false)
          .findAll();

      // Assert.
      expect(updated, 2);
      expect(activeCount, 0);
      expect(inactive.map((user) => user.dbId), [1, 2, 3]);
    });

    // Scenario: A filter-only query updates only its first matching row.
    // Covers:
    // - [CindelQuery.updateFirst].
    // - Native query-plan limit handling for mutating queries.
    // Expected: Only one matching object changes.
    test('updates the first matching native typed query result.', () async {
      // Arrange.
      final database = await openTestDatabaseInMemory(
        schemas: [ImmutableUserSchema],
      );
      addTearDown(database.close);
      await database.immutableUsers.putAll([
        const ImmutableUser(dbId: 1, email: 'a@example.com', active: true),
        const ImmutableUser(dbId: 2, email: 'b@example.com', active: true),
        const ImmutableUser(dbId: 3, email: 'c@example.com', active: false),
      ]);

      // Act.
      final updated = await database.immutableUsers
          .filter()
          .activeEqualTo(true)
          .sortByDbId()
          .updateFirst({'active': false});
      final users = await database.immutableUsers.all().sortByDbId().findAll();

      // Assert.
      expect(updated, isTrue);
      expect(users.map((user) => user.active), [false, true, false]);
    });

    // Scenario: Query updates reject unsupported public mutation shapes.
    // Covers:
    // - Update attempts without a native query plan.
    // - Id field updates.
    // - Values that cannot be encoded as native query update values.
    // Expected: Invalid updates fail before mutating documents.
    test('rejects invalid native typed query updates.', () async {
      // Arrange.
      final database = await openTestDatabaseInMemory(
        schemas: [UserSchema, ImmutableUserSchema],
      );
      addTearDown(database.close);
      await database.users.put(
        _user(dbId: 1, name: 'Ana', email: 'a@example.com'),
      );
      await database.immutableUsers.put(
        const ImmutableUser(dbId: 1, email: 'a@example.com', active: true),
      );

      // Assert.
      await expectLater(
        database.users
            .all()
            .whereMatches(
              CindelFilter.path([
                'primaryRecipient',
                'address',
              ]).equalTo('a@example.com'),
            )
            .updateAll({'active': false}),
        throwsUnsupportedError,
      );
      await expectLater(
        database.immutableUsers.filter().activeEqualTo(true).updateAll({
          'dbId': 99,
        }),
        throwsArgumentError,
      );
      await expectLater(
        database.immutableUsers.filter().activeEqualTo(true).updateAll({
          'active': DateTime.utc(2024),
        }),
        throwsArgumentError,
      );
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

    // Scenario: A generated filter equality targets an indexed field.
    // Covers:
    // - [CindelQuery.whereMatches] recognizing an indexed equality predicate.
    // - Same public results as the generated indexed where helper.
    // Expected: Filter syntax keeps Isar-like ergonomics while using index
    // semantics that match the where path.
    test('uses indexed equality for filter-only indexed fields.', () async {
      // Arrange.
      final database = await _openSeededUsers();
      addTearDown(database.close);

      // Act.
      final filterUsers = await database.users
          .filter()
          .emailEqualTo('team@example.com')
          .sortByName()
          .findAll();
      final whereUsers = await database.users
          .where()
          .emailEqualTo('team@example.com')
          .sortByName()
          .findAll();

      // Assert.
      expect(filterUsers.map((user) => user.name), ['Ana', 'Cid']);
      expect(
        filterUsers.map((user) => user.dbId),
        whereUsers.map((user) => user.dbId),
      );
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
          .dbIdGreaterThan(2)
          .findAll();
      final between = await database.users.filter().dbIdBetween(2, 3).findAll();

      // Assert.
      expect(greaterThan.map((user) => user.name), ['Cid', 'Dee']);
      expect(between.map((user) => user.name), ['Ben', 'Cid']);
    });

    // Scenario: A filter-only query counts and projects without requiring sort
    // or distinct processing.
    // Covers:
    // - Native planner id-window path for [CindelQuery.count].
    // - Native single-field projection path for [CindelPropertyQuery.findAll].
    // Expected: Count and property results preserve id-order filter semantics.
    test('counts and projects filter-only queries.', () async {
      // Arrange.
      final database = await _openSeededUsers();
      addTearDown(database.close);

      // Act.
      final activeCount = await database.users
          .filter()
          .activeEqualTo(true)
          .limit(2)
          .count();
      final activeNames = await database.users
          .filter()
          .activeEqualTo(true)
          .nameProperty()
          .findAll();

      // Assert.
      expect(activeCount, 2);
      expect(activeNames, ['Ana', 'Ben', 'Dee']);
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

    // Scenario: Dynamic query modifiers compose generated filter helpers.
    // Covers:
    // - [CindelQuery.optional] preserving or applying a query part.
    // - Generated query filter [anyOf] and [allOf] helpers.
    // - Empty [anyOf] and [allOf] behavior matching Isar semantics.
    // Expected: Optional filters can be toggled, repeated filters are grouped
    // with OR/AND, empty anyOf matches nothing, and empty allOf is a no-op.
    test('supports optional, anyOf, and allOf query modifiers.', () async {
      // Arrange.
      final database = await _openSeededUsers();
      addTearDown(database.close);

      // Act.
      final optionalDisabled = await database.users
          .all()
          .optional(false, (query) {
            return query.filter().activeEqualTo(false);
          })
          .sortByDbId()
          .findAll();
      final optionalEnabled = await database.users.all().optional(true, (
        query,
      ) {
        return query.filter().activeEqualTo(false);
      }).findAll();
      final anyMatches = await database.users
          .filter()
          .anyOf(['Ana', 'Dee'], (query, name) {
            return query.nameEqualTo(name);
          })
          .sortByDbId()
          .findAll();
      final indexedAnyMatches = await database.users
          .all()
          .anyOf(['team@example.com', 'solo@example.com'], (query, email) {
            return query.filter().emailEqualTo(email);
          })
          .sortByDbId()
          .findAll();
      final emptyAnyMatches = await database.users.filter().anyOf(<String>[], (
        query,
        name,
      ) {
        return query.nameEqualTo(name);
      }).findAll();
      final allMatches = await database.users
          .filter()
          .allOf(['team', 'example'], (query, token) {
            return query.emailContains(token);
          })
          .sortByDbId()
          .findAll();
      final emptyAllMatches = await database.users
          .where()
          .emailStartsWith('team')
          .filter()
          .allOf(<String>[], (query, token) {
            return query.emailContains(token);
          })
          .sortByDbId()
          .findAll();

      // Assert.
      expect(optionalDisabled.map((user) => user.name), [
        'Ana',
        'Ben',
        'Cid',
        'Dee',
      ]);
      expect(optionalEnabled.map((user) => user.name), ['Cid']);
      expect(anyMatches.map((user) => user.name), ['Ana', 'Dee']);
      expect(indexedAnyMatches.map((user) => user.name), ['Ana', 'Ben', 'Cid']);
      expect(emptyAnyMatches, isEmpty);
      expect(allMatches.map((user) => user.name), ['Ana', 'Cid', 'Dee']);
      expect(emptyAllMatches.map((user) => user.name), ['Ana', 'Cid', 'Dee']);
    });

    // Scenario: Query builders reject invalid public modifiers.
    // Covers:
    // - Empty field lists for distinct and projection.
    // - Negative window arguments.
    // - [CindelQuery.anyOf] and [CindelQuery.allOf] rejecting callbacks that
    //   change anything other than filters.
    // Expected: Invalid query shapes fail immediately.
    test('rejects invalid query modifiers.', () async {
      // Arrange.
      final database = await _openSeededUsers();
      addTearDown(database.close);

      // Assert.
      expect(
        () => database.users.all().distinctByFields([]),
        throwsArgumentError,
      );
      expect(() => database.users.all().offset(-1), throwsArgumentError);
      expect(() => database.users.all().limit(-1), throwsArgumentError);
      expect(() => database.users.all().properties([]), throwsArgumentError);
      expect(() => database.users.all().sortBy(' '), throwsArgumentError);
      expect(
        () => CindelQuery.equal(
          database: database,
          schema: UserSchema,
          field: 'missing',
          value: 'value',
        ),
        throwsA(isA<CindelSchemaError>()),
      );
      expect(
        () => CindelQuery.wordsContain(
          database: database,
          schema: UserSchema,
          field: 'email',
          word: 'team',
        ),
        throwsA(isA<CindelQueryError>()),
      );
      expect(
        () => database.users.all().anyOf(['Ana'], (query, name) {
          return query.sortByName();
        }),
        throwsArgumentError,
      );
      expect(
        () => database.users.all().allOf(['Ana'], (query, name) {
          return query.limit(1);
        }),
        throwsArgumentError,
      );
      expect(
        () => database.users.all().sortByEmail().anyOf(['Ana'], (query, name) {
          return query.sortByName();
        }),
        throwsArgumentError,
      );
      expect(
        () => database.users.all().distinctByEmail().allOf(['Ana'], (
          query,
          name,
        ) {
          return query.distinctByName();
        }),
        throwsArgumentError,
      );
    });

    // Scenario: Word-index where helpers receive input without searchable
    // tokens.
    // Covers:
    // - Empty token branch for [CindelQuery.wordsContain].
    // - Empty token branch for [CindelQuery.wordsStartWith].
    // Expected: Inputs that split into no words match no documents.
    test('word queries with no tokens match nothing.', () async {
      // Arrange.
      final database = await _openSeededUsers();
      addTearDown(database.close);

      // Act.
      final exactMatches = await database.users
          .where()
          .bioWordEqualTo('!!!')
          .findAll();
      final prefixMatches = await database.users
          .where()
          .bioWordStartsWith('---')
          .findAll();

      // Assert.
      expect(exactMatches, isEmpty);
      expect(prefixMatches, isEmpty);
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

    // Scenario: A query shape that cannot be represented as a native plan uses
    // Dart-side result helpers.
    // Covers:
    // - Sorting null and bool values.
    // - Offset without limit.
    // - Offset beyond the result length.
    // Expected: Dart-side sorting and windowing keep the public query contract.
    test('processes Dart-side sort and window helpers.', () async {
      // Arrange.
      final database = await _openSeededUsers();
      addTearDown(database.close);

      CindelQuery<User> dartPlannedQuery() {
        return database.users.all().whereMatches(
          CindelFilter.path([
            'primaryRecipient',
            'metadata',
            'label',
          ]).equalTo('seeded'),
        );
      }

      // Act.
      final sorted = await dartPlannedQuery()
          .sortByDisplayName()
          .thenByActive()
          .findAll();
      final offsetOnly = await dartPlannedQuery()
          .sortByName()
          .offset(1)
          .findAll();
      final beyondWindow = await dartPlannedQuery()
          .sortByName()
          .offset(10)
          .findAll();

      // Assert.
      expect(sorted.map((user) => user.name), ['Ana', 'Cid', 'Ben', 'Dee']);
      expect(offsetOnly.map((user) => user.name), ['Ben', 'Cid', 'Dee']);
      expect(beyondWindow, isEmpty);
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
          .sortByDbId()
          .nameProperty()
          .findAll();
      final firstEmail = await database.users
          .all()
          .sortByNameDesc()
          .emailProperty()
          .findFirst();
      final rows = await database.users.all().sortByDbId().limit(2).properties([
        'name',
        'active',
      ]).findAll();
      final firstRow = await database.users.all().sortByDbId().properties([
        'name',
        'email',
      ]).findFirst();
      final missingRow = await database.users
          .where()
          .emailEqualTo('missing@example.com')
          .properties(['name'])
          .findFirst();

      // Assert.
      expect(names, ['Ana', 'Ben', 'Cid', 'Dee']);
      expect(firstEmail, 'team-alpha@example.com');
      expect(rows, [
        {'name': 'Ana', 'active': true},
        {'name': 'Ben', 'active': true},
      ]);
      expect(firstRow, {'name': 'Ana', 'email': 'team@example.com'});
      expect(missingRow, isNull);
    });

    // Scenario: A query aggregates projected primitive values.
    // Covers:
    // - [CindelPropertyQuery.count], min, max, sum, and average.
    // - Native aggregate path for filter-only binary-document queries.
    // - Dart fallback path for query shapes that cannot use native planning.
    // Expected: Aggregates ignore null values and avoid object hydration when
    // native planning is available.
    test('aggregates projected primitive fields.', () async {
      // Arrange.
      final database = await _openSeededUsers();
      addTearDown(database.close);

      // Act.
      final idCount = await database.users.all().dbIdProperty().count();
      final minId = await database.users.all().dbIdProperty().min();
      final maxId = await database.users.all().dbIdProperty().max();
      final activeIdSum = await database.users
          .filter()
          .activeEqualTo(true)
          .dbIdProperty()
          .sum();
      final activeIdAverage = await database.users
          .filter()
          .activeEqualTo(true)
          .dbIdProperty()
          .average();
      final firstCreatedAt = await database.users
          .all()
          .createdAtProperty()
          .min();
      final lastCreatedAt = await database.users
          .all()
          .createdAtProperty()
          .max();
      final firstName = await database.users.all().nameProperty().min();
      final lastName = await database.users.all().nameProperty().max();

      // Assert.
      expect(idCount, 4);
      expect(minId, 1);
      expect(maxId, 4);
      expect(activeIdSum, 7);
      expect(activeIdAverage, closeTo(7 / 3, 0.0001));
      expect(firstCreatedAt, DateTime.utc(2024));
      expect(lastCreatedAt, DateTime.utc(2024, 1, 4));
      expect(firstName, 'Ana');
      expect(lastName, 'Dee');
    });

    // Scenario: A binary-document query can execute the whole common plan
    // natively.
    // Covers:
    // - Native plan filter, sort, distinct, offset, limit, and projection.
    // - Native plan count and aggregate result payloads.
    // - Native plan delete of the first visible result.
    // Expected: The public query API keeps the same result shape on both
    // backends.
    test('executes common query plans through the native path.', () async {
      // Arrange.
      final database = await _openUsersWithDuplicateNames();
      addTearDown(database.close);

      CindelQuery<User> query() {
        return database.users
            .all()
            .filter()
            .activeEqualTo(true)
            .sortByName()
            .distinctByName()
            .offset(1)
            .limit(1);
      }

      // Act.
      final names = await query().nameProperty().findAll();
      final count = await query().count();
      final idSum = await query().dbIdProperty().sum();
      final deleted = await query().deleteFirst();
      final deletedUser = await database.users.get(2);
      final remainingNames = await database.users
          .all()
          .filter()
          .activeEqualTo(true)
          .sortByName()
          .distinctByName()
          .nameProperty()
          .findAll();

      // Assert.
      expect(names, ['Ben']);
      expect(count, 1);
      expect(idSum, 2);
      expect(deleted, isTrue);
      expect(deletedUser, isNull);
      expect(remainingNames, ['Ana']);
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
  final database = await openTestDatabaseInMemory(schemas: [UserSchema]);
  await database.users.put(
    _user(
      dbId: 1,
      name: 'Ana',
      email: 'team@example.com',
      displayName: null,
      sessionLength: const Duration(minutes: 3),
      tags: ['flutter', 'database'],
    ),
  );
  await database.users.put(
    _user(dbId: 2, name: 'Ben', email: 'solo@example.com', displayName: 'same'),
  );
  await database.users.put(
    _user(
      dbId: 3,
      name: 'Cid',
      email: 'team@example.com',
      active: false,
      displayName: 'same',
    ),
  );
  await database.users.put(
    _user(
      dbId: 4,
      name: 'Dee',
      email: 'team-alpha@example.com',
      displayName: 'same',
      tags: ['Flutter', 'todo'],
    ),
  );
  return database;
}

Future<CindelDatabase> _openUsersWithDuplicateNames() async {
  final database = await openTestDatabaseInMemory(schemas: [UserSchema]);
  await database.users.put(
    _user(dbId: 1, name: 'Ana', email: 'z@example.com', active: false),
  );
  await database.users.put(
    _user(dbId: 2, name: 'Ben', email: 'b@example.com', active: true),
  );
  await database.users.put(
    _user(dbId: 3, name: 'Ana', email: 'a@example.com', active: true),
  );
  return database;
}

Future<CindelDatabase> _openUsersForExecutionOrder() async {
  final database = await openTestDatabaseInMemory(schemas: [UserSchema]);
  await database.users.put(
    _user(dbId: 1, name: 'Bob', email: 'team-a@example.com', active: true),
  );
  await database.users.put(
    _user(dbId: 2, name: 'Ana', email: 'team-a@example.com', active: true),
  );
  await database.users.put(
    _user(dbId: 3, name: 'Cid', email: 'team-c@example.com', active: true),
  );
  await database.users.put(
    _user(dbId: 4, name: 'Dee', email: 'team-d@example.com', active: true),
  );
  await database.users.put(
    _user(dbId: 5, name: 'Eli', email: 'solo@example.com', active: true),
  );
  await database.users.put(
    _user(dbId: 6, name: 'Fox', email: 'team-f@example.com', active: false),
  );
  return database;
}

User _user({
  required int dbId,
  required String name,
  required String email,
  bool active = true,
  String? displayName,
  Duration? sessionLength,
  List<String> tags = const [],
}) {
  return User()
    ..dbId = dbId
    ..name = name
    ..email = email
    ..displayName = displayName
    ..active = active
    ..createdAt = DateTime.utc(2024, 1, dbId)
    ..sessionLength = sessionLength
    ..primaryRecipient = (Recipient()
      ..address = email
      ..metadata = (RecipientMetadata()..label = 'seeded'))
    ..tags = tags;
}
