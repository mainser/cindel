import 'dart:io';

import 'package:cindel/cindel.dart';
import 'package:test/test.dart';

import 'backend_test_support.dart';

void main() {
  group('Cindel public migrations', () {
    test(
      'runs verified open-time migration and reopens target schema.',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'cindel_migration_${testStorageBackend.name}_',
        );
        addTearDown(() async {
          if (await directory.exists()) {
            await directory.delete(recursive: true);
          }
        });

        final original = await openTestDatabase(
          directory: directory.path,
          schemas: [_oldUserSchema],
        );
        await original.typedCollection(_oldUserSchema).putAll([
          _OldUser(dbId: 1, name: 'Ana', birthYear: 1990),
          _OldUser(dbId: 2, name: 'Ben', birthYear: 1985),
        ]);
        await original.setMigrationVersion(1);
        expect(await original.schemaVersion('migration_users'), 1);
        await original.close();

        var migrationRuns = 0;
        final plan = CindelMigrationPlan(
          targetVersion: 2,
          baselineVersion: 1,
          steps: [
            CindelMigrationStep(
              fromVersion: 1,
              toVersion: 2,
              openSchemas: [_oldUserSchema],
              targetSchemas: [_newUserSchema],
              verifyBefore: (context) async {
                expect(await context.database.migrationVersion(), 1);
                expect(await context.database.documentIds('migration_users'), [
                  1,
                  2,
                ]);
              },
              migrate: (context) async {
                migrationRuns += 1;
                final oldUsers = await context.exportObjects(_oldUserSchema);
                await context.registerTargetSchemas();
                await context.importObjects(_newUserSchema, [
                  for (final user in oldUsers)
                    _NewUser(
                      dbId: user.dbId,
                      name: user.name,
                      migratedBirthYear: user.birthYear,
                    ),
                ]);
              },
              verifyAfter: (context) async {
                expect(
                  await context.database.schemaVersion('migration_users'),
                  2,
                );
                final users = await context.database
                    .typedCollection(_newUserSchema)
                    .getAll([1, 2]);
                expect(users[0]?.migratedBirthYear, 1990);
                expect(users[1]?.migratedBirthYear, 1985);
              },
            ),
          ],
        );

        final migrated = await Cindel.open(
          directory: directory.path,
          schemas: [_newUserSchema],
          backend: testStorageBackend,
          migrationPlan: plan,
        );
        addTearDown(migrated.close);

        expect(migrationRuns, 1);
        expect(await migrated.migrationVersion(), 2);
        expect(await migrated.schemaVersion('migration_users'), 2);
        expect(
          (await migrated.typedCollection(_newUserSchema).getAll([
            1,
            2,
          ])).map((user) => user?.migratedBirthYear).toList(),
          [1990, 1985],
        );
        await migrated.close();

        final reopened = await Cindel.open(
          directory: directory.path,
          schemas: [_newUserSchema],
          backend: testStorageBackend,
          migrationPlan: plan,
        );
        addTearDown(reopened.close);

        expect(migrationRuns, 1);
        expect(await reopened.migrationVersion(), 2);
        expect(await reopened.schemaVersion('migration_users'), 2);
        expect(
          (await reopened.typedCollection(_newUserSchema).getAll([
            1,
            2,
          ])).map((user) => user?.name).toList(),
          ['Ana', 'Ben'],
        );
      },
    );
  });
}

final _oldUserSchema = CindelCollectionSchema<_OldUser>(
  name: 'migration_users',
  dartName: '_OldUser',
  idField: 'dbId',
  fields: const [
    CindelFieldSchema(
      name: 'dbId',
      dartType: 'int',
      isId: true,
      isIndexed: false,
      binaryType: 'int',
    ),
    CindelFieldSchema(
      name: 'aName',
      dartType: 'String',
      isId: false,
      isIndexed: false,
      binaryType: 'string',
    ),
    CindelFieldSchema(
      name: 'bBirthYear',
      dartType: 'int',
      isId: false,
      isIndexed: false,
      binaryType: 'int',
    ),
  ],
  toDocument: (user) => {
    'dbId': user.dbId,
    'aName': user.name,
    'bBirthYear': user.birthYear,
  },
  fromDocument: (document) => _OldUser(
    dbId: document['dbId'] as int? ?? autoIncrement,
    name: document['aName'] as String,
    birthYear: document['bBirthYear'] as int,
  ),
  toBinaryDocument: (user) => cindelEncodeSchemaBinaryDocument(
    [user.name, user.birthYear],
    const [CindelBinaryFieldType.stringValue, CindelBinaryFieldType.intValue],
  ),
  fromBinaryDocument: (bytes) {
    final values = cindelDecodeSchemaBinaryDocument(bytes, const [
      CindelBinaryFieldType.stringValue,
      CindelBinaryFieldType.intValue,
    ]);
    return _OldUser(
      dbId: autoIncrement,
      name: values[0] as String,
      birthYear: values[1] as int,
    );
  },
  getId: (user) => user.dbId,
  setId: (user, id) => user.dbId = id,
  writeNativeDocument: (writer, user) {
    writer.writeString(0, user.name);
    writer.writeInt(1, user.birthYear);
  },
  readNativeDocument: (reader, index) => _OldUser(
    dbId: reader.readId(index),
    name: reader.readString(index, 0)!,
    birthYear: reader.readInt(index, 1)!,
  ),
);

final _newUserSchema = CindelCollectionSchema<_NewUser>(
  name: 'migration_users',
  dartName: '_NewUser',
  idField: 'dbId',
  fields: const [
    CindelFieldSchema(
      name: 'dbId',
      dartType: 'int',
      isId: true,
      isIndexed: false,
      binaryType: 'int',
    ),
    CindelFieldSchema(
      name: 'aName',
      dartType: 'String',
      isId: false,
      isIndexed: false,
      binaryType: 'string',
    ),
    CindelFieldSchema(
      name: 'cMigratedBirthYear',
      dartType: 'int',
      isId: false,
      isIndexed: true,
      binaryType: 'int',
    ),
  ],
  toDocument: (user) => {
    'dbId': user.dbId,
    'aName': user.name,
    'cMigratedBirthYear': user.migratedBirthYear,
  },
  fromDocument: (document) => _NewUser(
    dbId: document['dbId'] as int? ?? autoIncrement,
    name: document['aName'] as String,
    migratedBirthYear: document['cMigratedBirthYear'] as int,
  ),
  toBinaryDocument: (user) => cindelEncodeSchemaBinaryDocument(
    [user.name, user.migratedBirthYear],
    const [CindelBinaryFieldType.stringValue, CindelBinaryFieldType.intValue],
  ),
  fromBinaryDocument: (bytes) {
    final values = cindelDecodeSchemaBinaryDocument(bytes, const [
      CindelBinaryFieldType.stringValue,
      CindelBinaryFieldType.intValue,
    ]);
    return _NewUser(
      dbId: autoIncrement,
      name: values[0] as String,
      migratedBirthYear: values[1] as int,
    );
  },
  getId: (user) => user.dbId,
  setId: (user, id) => user.dbId = id,
  writeNativeDocument: (writer, user) {
    writer.writeString(0, user.name);
    writer.writeInt(1, user.migratedBirthYear);
  },
  readNativeDocument: (reader, index) => _NewUser(
    dbId: reader.readId(index),
    name: reader.readString(index, 0)!,
    migratedBirthYear: reader.readInt(index, 1)!,
  ),
);

final class _OldUser {
  _OldUser({required this.dbId, required this.name, required this.birthYear});

  int dbId;
  final String name;
  final int birthYear;
}

final class _NewUser {
  _NewUser({
    required this.dbId,
    required this.name,
    required this.migratedBirthYear,
  });

  int dbId;
  final String name;
  final int migratedBirthYear;
}
