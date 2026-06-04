import 'dart:io';

import 'package:test/test.dart';

import 'backend_test_support.dart';

import 'schema_generation_fixture.dart';

void main() {
  group('Cindel index queries', () {
    // Scenario: Multiple documents share the same indexed email.
    // Covers:
    // - [Cindel.open] registering generated schemas.
    // - [CindelDatabase.put] writing index entries from schema metadata.
    // - [CindelDatabase.queryEqual] reading matching documents by index.
    // Expected: Equality queries return only documents with the indexed value.
    test('finds documents by indexed equality.', () async {
      // Arrange.
      final directory = await _createDatabaseDirectory();
      addTearDown(() => directory.delete(recursive: true));
      final database = await openTestDatabase(
        directory: directory.path,
        schemas: [UserSchema],
      );
      addTearDown(database.close);

      // Act.
      await database.put('users', 1, _user(1, 'Ana', 'team@example.com'));
      await database.put('users', 2, _user(2, 'Ben', 'solo@example.com'));
      await database.put('users', 3, _user(3, 'Cid', 'team@example.com'));
      final documents = await database.queryEqual(
        'users',
        'email',
        'team@example.com',
      );

      // Assert.
      expect(documents.map((document) => document['id']), [1, 3]);
    });

    // Scenario: Documents are queried by an indexed string range.
    // Covers:
    // - [CindelDatabase.queryRange] passing inclusive bounds to Rust.
    // - SQLite-backed index ordering for string values.
    // Expected: Range queries return matching documents ordered by index value.
    test('finds documents by indexed range.', () async {
      // Arrange.
      final directory = await _createDatabaseDirectory();
      addTearDown(() => directory.delete(recursive: true));
      final database = await openTestDatabase(
        directory: directory.path,
        schemas: [UserSchema],
      );
      addTearDown(database.close);

      // Act.
      await database.put('users', 1, _user(1, 'Ana', 'a@example.com'));
      await database.put('users', 2, _user(2, 'Ben', 'b@example.com'));
      await database.put('users', 3, _user(3, 'Cid', 'c@example.com'));
      final documents = await database.queryRange(
        'users',
        'email',
        lower: 'b@example.com',
        upper: 'c@example.com',
      );

      // Assert.
      expect(documents.map((document) => document['email']), [
        'b@example.com',
        'c@example.com',
      ]);
    });

    // Scenario: An indexed document is overwritten and deleted.
    // Covers:
    // - Index replacement when [CindelDatabase.put] updates an existing id.
    // - Index cleanup when [CindelDatabase.delete] removes a document.
    // Expected: Queries do not return stale index entries.
    test('updates and deletes index entries with documents.', () async {
      // Arrange.
      final directory = await _createDatabaseDirectory();
      addTearDown(() => directory.delete(recursive: true));
      final database = await openTestDatabase(
        directory: directory.path,
        schemas: [UserSchema],
      );
      addTearDown(database.close);

      // Act.
      await database.put('users', 1, _user(1, 'Ana', 'old@example.com'));
      await database.put('users', 1, _user(1, 'Ana', 'new@example.com'));
      final oldDocuments = await database.queryEqual(
        'users',
        'email',
        'old@example.com',
      );
      final newDocuments = await database.queryEqual(
        'users',
        'email',
        'new@example.com',
      );

      // Assert.
      expect(oldDocuments, isEmpty);
      expect(newDocuments.map((document) => document['id']), [1]);

      // Act.
      await database.delete('users', 1);
      final deletedDocuments = await database.queryEqual(
        'users',
        'email',
        'new@example.com',
      );

      // Assert.
      expect(deletedDocuments, isEmpty);
    });

    // Scenario: A generated unique index receives duplicate values.
    // Covers:
    // - [Index.unique] metadata generated into [CindelFieldSchema].
    // - Public write-time validation before native index entries are replaced.
    // Expected: A second document with the same unique value is rejected.
    test('rejects duplicate values for unique indexes.', () async {
      // Arrange.
      final database = await openTestDatabaseInMemory(schemas: [UserSchema]);
      addTearDown(database.close);

      // Act.
      await database.put(
        'users',
        1,
        _user(1, 'Ana', 'ana@example.com', username: 'ana'),
      );
      final duplicate = database.put(
        'users',
        2,
        _user(2, 'Ann', 'ann@example.com', username: 'ana'),
      );
      final replaceSameDocument = database.put(
        'users',
        1,
        _user(1, 'Ana Maria', 'ana@example.com', username: 'ana'),
      );

      // Assert.
      await expectLater(duplicate, throwsA(isA<StateError>()));
      await expectLater(replaceSameDocument, completes);
      final users = await database.queryEqual('users', 'username', 'ana');
      expect(users.map((document) => document['id']), [1]);
    });

    // Scenario: A string index is configured as case-insensitive.
    // Covers:
    // - [Index.caseSensitive] generated metadata.
    // - Normalized equality and prefix lookups over indexed strings.
    // Expected: Different query casing still matches the stored value.
    test('supports case-insensitive string indexes.', () async {
      // Arrange.
      final database = await openTestDatabaseInMemory(schemas: [UserSchema]);
      addTearDown(database.close);
      await database.put(
        'users',
        1,
        _user(1, 'Noel', 'noel@example.com', displayName: 'Noel Alvarez'),
      );
      await database.put(
        'users',
        2,
        _user(2, 'Ben', 'ben@example.com', displayName: 'Ben'),
      );

      // Act.
      final exact = await database.queryEqual(
        'users',
        'displayName',
        'noel alvarez',
      );
      final prefix = await database.users
          .where()
          .displayNameStartsWith('NOE')
          .findAll();

      // Assert.
      expect(exact.map((document) => document['id']), [1]);
      expect(prefix.map((user) => user.name), ['Noel']);
    });

    // Scenario: A field uses a hash index.
    // Covers:
    // - [CindelIndexType.hash] generated metadata.
    // - Equality lookup over compact stable index values.
    // - Range rejection for hash indexes.
    // Expected: Hash indexes support equality and reject range operations.
    test('supports hash indexes for equality only.', () async {
      // Arrange.
      final database = await openTestDatabaseInMemory(schemas: [UserSchema]);
      addTearDown(database.close);
      await database.put(
        'users',
        1,
        _user(1, 'Ana', 'ana@example.com', accessToken: 'secret-a'),
      );
      await database.put(
        'users',
        2,
        _user(2, 'Ben', 'ben@example.com', accessToken: 'secret-b'),
      );

      // Act.
      final users = await database.users
          .where()
          .accessTokenEqualTo('secret-b')
          .findAll();
      final range = database.queryRange(
        'users',
        'accessToken',
        lower: 'secret-a',
      );

      // Assert.
      expect(users.map((user) => user.name), ['Ben']);
      await expectLater(range, throwsA(isA<StateError>()));
    });

    // Scenario: Callers request only ids from indexed database queries.
    // Covers:
    // - [CindelDatabase.queryEqualIds] over normal and word indexes.
    // - [CindelDatabase.queryRangeIds] over normal indexes.
    // - Hash-index and missing-bound validation on id-only query APIs.
    // Expected: Id-only queries return the same matching ids as document
    //   queries and reject invalid index shapes before returning ids.
    test('returns ids for indexed equality and range queries.', () async {
      // Arrange.
      final database = await openTestDatabaseInMemory(schemas: [UserSchema]);
      addTearDown(database.close);
      await database.put(
        'users',
        1,
        _user(
          1,
          'Ana',
          'a@example.com',
          accessToken: 'secret-a',
          bio: 'Local database',
        ),
      );
      await database.put(
        'users',
        2,
        _user(
          2,
          'Ben',
          'b@example.com',
          accessToken: 'secret-b',
          bio: 'Remote database',
        ),
      );
      await database.put(
        'users',
        3,
        _user(
          3,
          'Cid',
          'c@example.com',
          accessToken: 'secret-c',
          bio: 'Local runtime',
        ),
      );

      // Act.
      final exactIds = await database.queryEqualIds(
        'users',
        'email',
        'b@example.com',
      );
      final wordIds = await database.queryEqualIds('users', 'bio', 'database');
      final rangeIds = await database.queryRangeIds(
        'users',
        'email',
        lower: 'b@example.com',
        upper: 'c@example.com',
      );
      final hashExactIds = database.queryEqualIds(
        'users',
        'accessToken',
        'secret-b',
      );
      final hashRangeIds = database.queryRangeIds(
        'users',
        'accessToken',
        lower: 'secret-a',
      );
      final missingBounds = database.queryRangeIds('users', 'email');

      // Assert.
      expect(exactIds, [2]);
      expect(wordIds, [1, 2]);
      expect(rangeIds, [2, 3]);
      await expectLater(hashExactIds, throwsA(isA<StateError>()));
      await expectLater(hashRangeIds, throwsA(isA<StateError>()));
      await expectLater(missingBounds, throwsA(isA<ArgumentError>()));
    });

    // Scenario: A string field is indexed as words.
    // Covers:
    // - [CindelIndexType.words] generated metadata.
    // - Multi-entry token writes for one document field.
    // - Case-insensitive exact word and token-prefix queries.
    // Expected: Documents can be found by indexed words rather than linear
    // contains filters.
    test('supports case-insensitive word indexes.', () async {
      // Arrange.
      final database = await openTestDatabaseInMemory(schemas: [UserSchema]);
      addTearDown(database.close);
      await database.put(
        'users',
        1,
        _user(1, 'Ana', 'ana@example.com', bio: 'Café rapido local database'),
      );
      await database.put(
        'users',
        2,
        _user(2, 'Ben', 'ben@example.com', bio: 'Remote cache database'),
      );

      // Act.
      final exact = await database.users
          .where()
          .bioWordEqualTo('CAFÉ')
          .findAll();
      final prefix = await database.users
          .where()
          .bioWordStartsWith('dat')
          .findAll();

      // Assert.
      expect(exact.map((user) => user.name), ['Ana']);
      expect(prefix.map((user) => user.name), ['Ana', 'Ben']);
    });

    // Scenario: A query is requested without a valid registered index.
    // Covers:
    // - Missing schema rejection.
    // - Non-indexed field rejection.
    // Expected: Invalid index queries fail before FFI.
    test('rejects queries without a registered indexed field.', () async {
      // Arrange.
      final directory = await _createDatabaseDirectory();
      addTearDown(() => directory.delete(recursive: true));
      final databaseWithoutSchema = await openTestDatabase(
        directory: directory.path,
      );
      addTearDown(databaseWithoutSchema.close);
      final databaseWithSchema = await openTestDatabase(
        directory: directory.path,
        schemas: [UserSchema],
      );
      addTearDown(databaseWithSchema.close);

      // Act.
      final queryWithoutSchema = databaseWithoutSchema.queryEqual(
        'users',
        'email',
        'demo@example.com',
      );
      final queryNonIndexedField = databaseWithSchema.queryEqual(
        'users',
        'name',
        'Ana',
      );

      // Assert.
      await expectLater(queryWithoutSchema, throwsA(isA<StateError>()));
      await expectLater(queryNonIndexedField, throwsA(isA<StateError>()));
    });
  });
}

Map<String, Object?> _user(
  int id,
  String name,
  String email, {
  String? username,
  String? displayName,
  String? accessToken,
  String? bio,
}) {
  return {
    'id': id,
    'name': name,
    'email': email,
    if (username != null) 'username': username,
    if (displayName != null) 'displayName': displayName,
    if (accessToken != null) 'accessToken': accessToken,
    if (bio != null) 'bio': bio,
    'active': true,
    'createdAt': 0,
    'tags': <String>[],
    'role': 'member',
    'status': 0,
    'plan': 'free',
  };
}

Future<Directory> _createDatabaseDirectory() {
  return Directory.systemTemp.createTemp('cindel_');
}
