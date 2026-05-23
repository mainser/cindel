import 'dart:io';

import 'package:cindel/cindel.dart';
import 'package:test/test.dart';

import 'backend_test_support.dart';

void main() {
  group('Cindel schema versions', () {
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
