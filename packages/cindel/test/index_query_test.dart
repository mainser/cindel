import 'dart:io';

import 'package:cindel/cindel.dart';
import 'package:test/test.dart';

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
      final database = await Cindel.open(
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
      final database = await Cindel.open(
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
      final database = await Cindel.open(
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

    // Scenario: A query is requested without a valid registered index.
    // Covers:
    // - Missing schema rejection.
    // - Non-indexed field rejection.
    // Expected: Invalid index queries fail before FFI.
    test('rejects queries without a registered indexed field.', () async {
      // Arrange.
      final directory = await _createDatabaseDirectory();
      addTearDown(() => directory.delete(recursive: true));
      final databaseWithoutSchema = await Cindel.open(
        directory: directory.path,
      );
      addTearDown(databaseWithoutSchema.close);
      final databaseWithSchema = await Cindel.open(
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

Map<String, Object?> _user(int id, String name, String email) {
  return {'id': id, 'name': name, 'email': email, 'active': true};
}

Future<Directory> _createDatabaseDirectory() {
  return Directory.systemTemp.createTemp('cindel_');
}
