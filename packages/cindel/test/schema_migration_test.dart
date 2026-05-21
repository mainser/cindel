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

    // Scenario: A schema adds a field and uses a callback to backfill data.
    // Covers:
    // - [Cindel.open] migration callback execution.
    // - [CindelMigration.backfillCollection].
    // - Schema registration after the callback completes.
    // Expected: Existing documents receive the new field and the schema
    // advances to version 2.
    test('runs migration callback for additive backfills.', () async {
      // Arrange.
      final directory = await _createDatabaseDirectory();
      addTearDown(() => directory.delete(recursive: true));
      final originalDatabase = await Cindel.open(
        directory: directory.path,
        schemas: [_userSchema()],
      );
      await originalDatabase.put('users', 1, {'id': 1, 'email': 'a@b.test'});
      await originalDatabase.close();

      // Act.
      final migratedDatabase = await Cindel.open(
        directory: directory.path,
        schemas: [_userSchema(includeActive: true)],
        migration: (migration) async {
          if ((migration.oldVersion('users') ?? 0) < 2) {
            await migration.backfillCollection('users', (id, document) {
              return {...document, 'active': true};
            });
          }
        },
      );
      addTearDown(migratedDatabase.close);
      final document = await migratedDatabase.get('users', 1);
      final version = await migratedDatabase.schemaVersion('users');

      // Assert.
      expect(document, {'id': 1, 'email': 'a@b.test', 'active': true});
      expect(version, 2);
    });

    // Scenario: A persisted field is renamed and remains indexed afterward.
    // Covers:
    // - Explicit migration registration for otherwise incompatible schemas.
    // - [CindelMigration.renameField].
    // - [CindelMigration.rebuildIndexes].
    // Expected: The new field is persisted, the old field is removed, and the
    // rebuilt index can find the migrated document.
    test('renames fields and rebuilds indexes explicitly.', () async {
      // Arrange.
      final directory = await _createDatabaseDirectory();
      addTearDown(() => directory.delete(recursive: true));
      final originalDatabase = await Cindel.open(
        directory: directory.path,
        schemas: [_userSchema()],
      );
      await originalDatabase.put('users', 1, {'id': 1, 'email': 'a@b.test'});
      await originalDatabase.close();

      // Act.
      final migratedDatabase = await Cindel.open(
        directory: directory.path,
        schemas: [_userSchema(indexedField: 'address')],
        migration: (migration) async {
          if ((migration.oldVersion('users') ?? 0) < 2) {
            await migration.renameField('users', from: 'email', to: 'address');
            await migration.rebuildIndexes('users');
          }
        },
      );
      addTearDown(migratedDatabase.close);
      final document = await migratedDatabase.get('users', 1);
      final indexedDocuments = await migratedDatabase.queryEqual(
        'users',
        'address',
        'a@b.test',
      );
      final version = await migratedDatabase.schemaVersion('users');

      // Assert.
      expect(document, {'id': 1, 'address': 'a@b.test'});
      expect(indexedDocuments, [
        {'id': 1, 'address': 'a@b.test'},
      ]);
      expect(version, 2);
    });

    // Scenario: A collection is renamed by copying documents to the new
    // collection and deleting the old collection documents.
    // Covers:
    // - [CindelMigration.renameCollection].
    // - New collection schema registration after an explicit migration.
    // Expected: The target collection contains the original documents and the
    // old collection is empty.
    test('renames collections explicitly.', () async {
      // Arrange.
      final directory = await _createDatabaseDirectory();
      addTearDown(() => directory.delete(recursive: true));
      final originalDatabase = await Cindel.open(
        directory: directory.path,
        schemas: [_userSchema()],
      );
      await originalDatabase.put('users', 1, {'id': 1, 'email': 'a@b.test'});
      await originalDatabase.close();

      // Act.
      final migratedDatabase = await Cindel.open(
        directory: directory.path,
        schemas: [_userSchema(collection: 'people')],
        migration: (migration) async {
          await migration.renameCollection('users', 'people');
          await migration.rebuildIndexes('people');
        },
      );
      addTearDown(migratedDatabase.close);
      final peopleDocument = await migratedDatabase.get('people', 1);
      final oldIds = await migratedDatabase.documentIds('users');
      final peopleVersion = await migratedDatabase.schemaVersion('people');

      // Assert.
      expect(peopleDocument, {'id': 1, 'email': 'a@b.test'});
      expect(oldIds, isEmpty);
      expect(peopleVersion, 1);
    });

    // Scenario: A migration is inspected in dry-run mode.
    // Covers:
    // - [Cindel.dryRunMigration].
    // - Dry-run diagnostics for migration helper operations.
    // - No document or schema writes through dry-run helpers.
    // Expected: Diagnostics are returned and stored data remains unchanged.
    test(
      'reports dry-run diagnostics without writing helper changes.',
      () async {
        // Arrange.
        final directory = await _createDatabaseDirectory();
        addTearDown(() => directory.delete(recursive: true));
        final originalDatabase = await Cindel.open(
          directory: directory.path,
          schemas: [_userSchema()],
        );
        await originalDatabase.put('users', 1, {'id': 1, 'email': 'a@b.test'});
        await originalDatabase.close();

        // Act.
        final report = await Cindel.dryRunMigration(
          directory: directory.path,
          schemas: [_userSchema(indexedField: 'address')],
          migration: (migration) async {
            await migration.renameField('users', from: 'email', to: 'address');
            await migration.rebuildIndexes('users');
          },
        );
        final reopenedDatabase = await Cindel.open(
          directory: directory.path,
          schemas: [_userSchema()],
        );
        addTearDown(reopenedDatabase.close);
        final document = await reopenedDatabase.get('users', 1);
        final version = await reopenedDatabase.schemaVersion('users');

        // Assert.
        expect(report.oldVersions, {'users': 1});
        expect(report.diagnostics.map((diagnostic) => diagnostic.operation), [
          'renameField',
          'rebuildIndexes',
        ]);
        expect(document, {'id': 1, 'email': 'a@b.test'});
        expect(version, 1);
      },
    );

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

    // Scenario: A registered schema changes an existing index option.
    // Covers:
    // - Native compatibility checks for index variant metadata.
    // - Public open failure before schema version advancement.
    // Expected: Changing uniqueness, case sensitivity, or index type requires
    // a future explicit migration.
    test('rejects incompatible index option changes.', () async {
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
        schemas: [_userSchema(emailUnique: true)],
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
  String collection = 'users',
  String indexedField = 'email',
  String emailType = 'String',
  bool emailUnique = false,
  bool includeActive = false,
}) {
  return CindelCollectionSchema<Map<String, Object?>>(
    name: collection,
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
        name: indexedField,
        dartType: emailType,
        isId: false,
        isIndexed: true,
        isIndexUnique: emailUnique,
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
