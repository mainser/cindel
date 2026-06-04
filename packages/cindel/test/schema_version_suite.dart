import 'dart:io';

import 'package:cindel/cindel.dart';
import 'package:test/test.dart';

import 'backend_test_support.dart';

void main() {
  group('Cindel schema versions', () {
    // Scenario: A collection schema is opened for the first time.
    // Covers:
    // - Initial schema manifest persistence.
    // - Public schema version lookup by collection name.
    // Expected: The registered collection reports schema version 1.
    test('persists the initial schema version.', () async {
      final directory = await _createDatabaseDirectory();
      addTearDown(() => directory.delete(recursive: true));
      final database = await openTestDatabase(
        directory: directory.path,
        schemas: [_userSchema()],
      );
      addTearDown(database.close);

      expect(await database.schemaVersion('users'), 1);
    });

    // Scenario: A stored collection schema is reopened with an additive field.
    // Covers:
    // - Compatible schema evolution.
    // - Version increments for additive metadata changes.
    // Expected: Reopening with the expanded schema advances the version to 2.
    test('advances schema version for additive compatible changes.', () async {
      final directory = await _createDatabaseDirectory();
      addTearDown(() => directory.delete(recursive: true));
      final original = await openTestDatabase(
        directory: directory.path,
        schemas: [_userSchema()],
      );
      await original.close();

      final expanded = await openTestDatabase(
        directory: directory.path,
        schemas: [_userSchema(includeActive: true)],
      );
      addTearDown(expanded.close);

      expect(await expanded.schemaVersion('users'), 2);
    });

    // Scenario: A stored collection schema is reopened with an incompatible
    // field type change.
    // Covers:
    // - Schema compatibility validation.
    // - Version preservation after a rejected incompatible open.
    // Expected: The incompatible open throws and the original version remains 1.
    test(
      'rejects incompatible schema changes without migration support.',
      () async {
        final directory = await _createDatabaseDirectory();
        addTearDown(() => directory.delete(recursive: true));
        final database = await openTestDatabase(
          directory: directory.path,
          schemas: [_userSchema()],
        );
        await database.close();

        await expectLater(
          openTestDatabase(
            directory: directory.path,
            schemas: [_userSchema(emailType: 'int')],
          ),
          throwsA(isA<StateError>()),
        );

        final reopened = await openTestDatabase(
          directory: directory.path,
          schemas: [_userSchema()],
        );
        addTearDown(reopened.close);
        expect(await reopened.schemaVersion('users'), 1);
      },
    );

    // Scenario: A schema version is requested for a collection that has not
    // been registered.
    // Covers:
    // - Public schema version lookup for missing collections.
    // Expected: Missing collection versions are reported as null.
    test('returns null for unregistered schema versions.', () async {
      final directory = await _createDatabaseDirectory();
      addTearDown(() => directory.delete(recursive: true));
      final database = await openTestDatabase(directory: directory.path);
      addTearDown(database.close);

      expect(await database.schemaVersion('users'), isNull);
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
