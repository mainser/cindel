import 'dart:io';

import 'package:cindel/cindel.dart';
import 'package:test/test.dart';

void main() {
  group('Cindel schema migrations', () {
    // Scenario: A schema is registered and the database is reopened with it.
    // Covers:
    // - [Cindel.open] registering schema metadata with the native engine.
    // - [CindelDatabase.schemaVersion] reading the persisted schema version.
    // - Reopening with the same schema without creating a migration.
    // Expected: The collection keeps schema version 1 across reopen.
    test('persists the initial schema version.', () async {
      // Arrange.
      final directory = await _createDatabaseDirectory();
      addTearDown(() => directory.delete(recursive: true));

      // Act.
      final firstDatabase = await Cindel.open(
        directory: directory.path,
        schemas: [_userSchema()],
      );
      final firstVersion = await firstDatabase.schemaVersion('users');
      await firstDatabase.close();
      final reopenedDatabase = await Cindel.open(
        directory: directory.path,
        schemas: [_userSchema()],
      );
      addTearDown(reopenedDatabase.close);
      final reopenedVersion = await reopenedDatabase.schemaVersion('users');

      // Assert.
      expect(firstVersion, 1);
      expect(reopenedVersion, 1);
    });

    // Scenario: A registered schema gains a new persisted field.
    // Covers:
    // - Compatible additive schema changes.
    // - Native schema version increments after a compatible migration.
    // Expected: The expanded schema opens successfully at version 2.
    test('advances schema version for additive changes.', () async {
      // Arrange.
      final directory = await _createDatabaseDirectory();
      addTearDown(() => directory.delete(recursive: true));
      final originalDatabase = await Cindel.open(
        directory: directory.path,
        schemas: [_userSchema()],
      );
      await originalDatabase.close();

      // Act.
      final expandedDatabase = await Cindel.open(
        directory: directory.path,
        schemas: [_userSchema(includeActive: true)],
      );
      addTearDown(expandedDatabase.close);
      final version = await expandedDatabase.schemaVersion('users');

      // Assert.
      expect(version, 2);
    });

    // Scenario: A registered schema changes the type of an existing field.
    // Covers:
    // - Incompatible schema validation during [Cindel.open].
    // - Rejection before the stored schema version is advanced.
    // Expected: Opening fails and the original schema remains at version 1.
    test('rejects incompatible schema changes.', () async {
      // Arrange.
      final directory = await _createDatabaseDirectory();
      addTearDown(() => directory.delete(recursive: true));
      final database = await Cindel.open(
        directory: directory.path,
        schemas: [_userSchema()],
      );
      await database.close();

      // Act.
      final incompatibleOpen = Cindel.open(
        directory: directory.path,
        schemas: [_userSchema(emailType: 'int')],
      );

      // Assert.
      await expectLater(incompatibleOpen, throwsA(isA<StateError>()));

      // Act.
      final reopenedDatabase = await Cindel.open(
        directory: directory.path,
        schemas: [_userSchema()],
      );
      addTearDown(reopenedDatabase.close);
      final version = await reopenedDatabase.schemaVersion('users');

      // Assert.
      expect(version, 1);
    });

    // Scenario: A schema version is requested for an unregistered collection.
    // Covers:
    // - Nullable version reads for collections without registered metadata.
    // - Public API behavior before FFI data is decoded.
    // Expected: Missing schema metadata is represented as null.
    test('returns null for unregistered schema versions.', () async {
      // Arrange.
      final directory = await _createDatabaseDirectory();
      addTearDown(() => directory.delete(recursive: true));
      final database = await Cindel.open(directory: directory.path);
      addTearDown(database.close);

      // Act.
      final version = await database.schemaVersion('users');

      // Assert.
      expect(version, isNull);
    });
  });
}

CindelCollectionSchema<Map<String, Object?>> _userSchema({
  String emailType = 'String',
  bool includeActive = false,
}) {
  return CindelCollectionSchema<Map<String, Object?>>(
    name: 'users',
    dartName: 'User',
    idField: 'id',
    fields: [
      const CindelFieldSchema(
        name: 'id',
        dartType: 'int',
        isId: true,
        isIndexed: false,
      ),
      CindelFieldSchema(
        name: 'email',
        dartType: emailType,
        isId: false,
        isIndexed: true,
      ),
      if (includeActive)
        const CindelFieldSchema(
          name: 'active',
          dartType: 'bool?',
          isId: false,
          isIndexed: false,
        ),
    ],
    toDocument: (object) => object,
    fromDocument: (document) => document,
  );
}

Future<Directory> _createDatabaseDirectory() {
  return Directory.systemTemp.createTemp('cindel_');
}
