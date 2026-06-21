import 'dart:io';

import 'package:cindel/cindel.dart';
import 'package:test/test.dart';

import 'backend_test_support.dart';

void main() {
  group('Cindel public migrations', () {
    // Scenario: Migration plan construction rejects impossible baseline and
    // target versions before touching storage.
    // Covers:
    // - `targetVersion` argument validation.
    // - `baselineVersion` argument validation.
    // Expected: Invalid versions throw `ArgumentError` immediately.
    test('rejects negative migration plan versions.', () {
      expect(
        () => CindelMigrationPlan(targetVersion: -1, steps: const []),
        throwsArgumentError,
      );
      expect(
        () => CindelMigrationPlan(
          targetVersion: 1,
          baselineVersion: -1,
          steps: const [],
        ),
        throwsArgumentError,
      );
    });

    // Scenario: A database is opened with an old persisted schema, migrated
    // before target schema registration, and reopened with the final schema.
    // Covers:
    // - `Cindel.open(..., migrationPlan: ...)` native/Web-compatible flow.
    // - Persisted data migration version reads and writes.
    // - Opening with old schemas for migration callbacks.
    // - Explicit target schema registration before importing rewritten data.
    // - Verify-before and verify-after callbacks.
    // - Reopen idempotency after the target version has already been reached.
    // Expected: The migration runs once, persists version 2, rewrites the old
    // birth-year field into the new indexed field, and later opens skip work.
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

    // Scenario: A migration callback uses the document-level helpers instead
    // of typed object helpers.
    // Covers:
    // - Baseline version fallback when schemas exist but migration marker does
    //   not.
    // - `exportDocuments` and `importDocuments`.
    // - Multi-batch export/import paths.
    // - Invalid batch-size validation from callback helpers.
    // Expected: The callback rewrites three source documents into target
    // documents, preserves ids, and persists version 2.
    test('supports document helpers and batching.', () async {
      final directory = await Directory.systemTemp.createTemp(
        'cindel_migration_helpers_${testStorageBackend.name}_',
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
        _OldUser(dbId: 3, name: 'Cam', birthYear: 2001),
      ]);
      expect(await original.migrationVersion(), isNull);
      await original.close();

      final plan = CindelMigrationPlan(
        targetVersion: 2,
        baselineVersion: 1,
        compactOnSuccess: false,
        steps: [
          CindelMigrationStep(
            fromVersion: 1,
            toVersion: 2,
            openSchemas: [_oldUserSchema],
            targetSchemas: [_newUserSchema],
            migrate: (context) async {
              expect(context.fromVersion, 1);
              expect(context.toVersion, 2);
              expect(context.targetSchemasRegistered, isFalse);
              await expectLater(
                context.exportObjects(_oldUserSchema, batchSize: 0),
                throwsArgumentError,
              );
              await expectLater(
                context.importObjects(_newUserSchema, const [], batchSize: 0),
                throwsArgumentError,
              );

              final documents = await context.exportDocuments(
                _oldUserSchema,
                batchSize: 2,
              );
              await context.registerTargetSchemas();
              await context.importDocuments(_newUserSchema, [
                for (final document in documents)
                  {
                    'dbId': document['dbId'],
                    'aName': document['aName'],
                    'cMigratedBirthYear': document['bBirthYear'],
                  },
              ], batchSize: 2);
              expect(context.targetSchemasRegistered, isTrue);
            },
            verifyAfter: (context) {
              expect(context.targetSchemasRegistered, isTrue);
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

      expect(await migrated.migrationVersion(), 2);
      expect(await migrated.documentIds('migration_users'), [1, 2, 3]);
    });

    // Scenario: A migration callback does no manual target schema registration
    // because no data rewrite is needed.
    // Covers:
    // - Automatic `registerTargetSchemas` after `migrate`.
    // Expected: The plan registers target schemas before `verifyAfter`.
    test(
      'registers target schemas automatically when callback skips it.',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'cindel_migration_auto_register_${testStorageBackend.name}_',
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
        await original.setMigrationVersion(1);
        await original.close();

        final plan = CindelMigrationPlan(
          targetVersion: 2,
          compactOnSuccess: false,
          steps: [
            CindelMigrationStep(
              fromVersion: 1,
              toVersion: 2,
              openSchemas: [_oldUserSchema],
              migrate: (context) {
                expect(context.targetSchemasRegistered, isFalse);
              },
              verifyAfter: (context) {
                expect(context.targetSchemasRegistered, isTrue);
              },
            ),
          ],
        );

        final migrated = await Cindel.open(
          directory: directory.path,
          schemas: [_oldUserSchema],
          backend: testStorageBackend,
          migrationPlan: plan,
        );
        addTearDown(migrated.close);

        expect(await migrated.migrationVersion(), 2);
      },
    );

    // Scenario: Invalid migration step graphs fail before mutating target data.
    // Covers:
    // - Missing step from current version.
    // - Non-advancing step.
    // - Step that exceeds the plan target.
    // Expected: Each invalid plan throws `StateError` with a focused message.
    test('rejects invalid migration step graphs.', () async {
      await _expectMigrationPlanError(
        CindelMigrationPlan(
          targetVersion: 2,
          steps: [_noopStep(fromVersion: 1, toVersion: 2)],
        ),
        contains('Missing Cindel migration step from version 0'),
      );
      await _expectMigrationPlanError(
        CindelMigrationPlan(
          targetVersion: 2,
          steps: [_noopStep(fromVersion: 0, toVersion: 0)],
        ),
        contains('must advance the data version'),
      );
      await _expectMigrationPlanError(
        CindelMigrationPlan(
          targetVersion: 2,
          steps: [_noopStep(fromVersion: 0, toVersion: 3)],
        ),
        contains('exceeds target version 2'),
      );
    });
  });
}

Future<void> _expectMigrationPlanError(
  CindelMigrationPlan plan,
  Matcher message,
) async {
  final directory = await Directory.systemTemp.createTemp(
    'cindel_migration_error_${testStorageBackend.name}_',
  );
  try {
    final database = await openTestDatabase(
      directory: directory.path,
      schemas: [_oldUserSchema],
    );
    await database.setMigrationVersion(0);
    await database.close();

    await expectLater(
      plan.run(
        directory: directory.path,
        targetSchemas: [_newUserSchema],
        backend: testStorageBackend,
      ),
      throwsA(
        isA<StateError>().having((error) => error.message, 'message', message),
      ),
    );
  } finally {
    await directory.delete(recursive: true);
  }
}

CindelMigrationStep _noopStep({
  required int fromVersion,
  required int toVersion,
}) {
  return CindelMigrationStep(
    fromVersion: fromVersion,
    toVersion: toVersion,
    openSchemas: [_oldUserSchema],
    targetSchemas: [_newUserSchema],
    migrate: (_) {},
  );
}

// Old fixture shape used to prove migration callbacks can read the persisted
// source layout before Cindel registers the final target schema.
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

// Target fixture shape used after migration. The renamed/indexed field makes
// normal compatible registration insufficient, so the test exercises migrated
// schema registration instead of additive-only schema evolution.
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
