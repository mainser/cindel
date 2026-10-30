# Migrations

Migrations let an app open existing stored data with old schemas, convert that
data to the current shape, and then continue with the current generated API.

Use a migration when an existing database cannot be safely opened with the new
schemas alone. Typical examples include renamed fields, removed fields, split
models, merged models, changed field types, or data rewrites that need
controlled conversion.

## How Migrations Run

Cindel stores a database-level data migration version inside the database. A
`CindelMigrationPlan` compares that stored version with the plan's
`targetVersion`, runs missing steps in order, persists each successful
`toVersion`, and returns a database opened with the target schemas.

```dart
final db = await Cindel.open(
  directory: appDataDirectory.path,
  schemas: [UserSchema],
  migrationPlan: migrations,
);
```

A migration step usually follows this shape:

1. Open existing data with schemas that can read the old stored shape.
2. Register the schemas for the new model shapes.
3. Read the old objects or documents using the context export/stream helpers.
4. Convert each value into the new model shape.
5. Import the converted stream in batches.
6. Verify the result.
7. Let Cindel mark the step as complete.

After the plan completes, app code uses the current generated API normally.

## Failures And Large Migrations

Each migration step either completes fully or leaves the database as it was
before that step. If `migrate` or `verifyAfter` throws, that step is not saved;
earlier successful steps remain complete and are skipped when you reopen.
Changes to files, network services or other application state are not rolled
back. Keep those effects outside migration callbacks where possible.

Open the database with its migration plan before letting the rest of the app
write to it. Writes through another connection during a migration can cause
the step to fail instead of overwriting those changes.

For large collections, convert objects as a stream instead of loading them all:

```dart
await context.registerTargetSchemas();
await context.importObjectStream(
  UserSchema,
  context.streamObjects(OldUserSchema, batchSize: 100).map(UserMigration.fromLegacy),
  batchSize: 100,
);
```

`streamObjects` and `streamDocuments` read the data from the start of the step,
even after registering target schemas. `context.database` reads the current
migration result, so use it in `verifyAfter` to check the converted data.

Choose a positive `batchSize`. Avoid collecting the stream with `toList()` if
you want to process a large collection incrementally. Allow temporary disk
space for a database copy and the changes being made; Web uses browser quota.

Preserve IDs when relationships should keep pointing to the same objects.
Saved links survive when both linked objects remain; links to removed objects
are cleaned up before `verifyAfter`.

`compactOnSuccess` defaults to `true` on the plan. If this final maintenance
fails, `CindelMigrationMaintenanceError.committedVersion` tells you which step
already completed. Its data is saved; reopening does not rerun that step.

## Migration Plans

`CindelMigrationPlan` declares the final data version and the ordered steps
that can move older databases to that version.

```dart
final migrations = CindelMigrationPlan(
  targetVersion: 2,
  baselineVersion: 1,
  steps: [
    migrateUsersFrom1To2,
  ],
);
```

Use `targetVersion` for the version the current app expects after all required
steps run.

`baselineVersion` defaults to `0`. It applies when a database has no stored
migration version but already has schema metadata for a collection named in
the plan or target schemas. Keep the old persisted collection names in the
plan so those databases can be recognized.

A fresh database with neither a migration version nor those schemas starts at
`targetVersion` and does not run the historical steps. Do not put first-install
seed data exclusively in a migration callback. A database newer than the
requested target is rejected; plans do not perform downgrades.

Pass the same plan every time the app opens the database:

```dart
final db = await Cindel.open(
  directory: appDataDirectory.path,
  schemas: [UserSchema],
  migrationPlan: migrations,
);
```

Completed steps are skipped on future opens. Missing steps run in order until
the database reaches `targetVersion`.

## Migration Steps

`CindelMigrationStep` describes one version move.

```dart
final migrateUsersFrom1To2 = CindelMigrationStep(
  fromVersion: 1,
  toVersion: 2,
  openSchemas: [OldUserSchema],
  targetSchemas: [UserSchema],
  migrate: (context) async {
    await context.registerTargetSchemas();

    await context.importObjectStream(
      UserSchema,
      context.streamObjects(OldUserSchema).map(UserMigration.fromLegacy),
    );
  },
);
```

Important fields:

- `fromVersion`: the version this step starts from.
- `toVersion`: the version this step completes.
- `openSchemas`: schemas that can read the existing stored data.
- `targetSchemas`: schemas that should exist after the step.
- `verifyBefore`: optional validation before rewriting data.
- `migrate`: the required migration callback.
- `verifyAfter`: optional validation after rewriting data.

Each step should do one controlled version move. For several releases, prefer
several small steps over one large step that tries to handle every old shape at
once.

## Exporting Old Data

Choose helpers according to whether the caller already holds a collection in
memory or can process it incrementally:

| Read old data | Import converted data |
| --- | --- |
| `streamObjects(schema, batchSize: 100)` | `importObjectStream(schema, stream, batchSize: 100)` |
| `streamDocuments(schema, batchSize: 100)` | `importDocumentStream(schema, stream, batchSize: 100)` |
| `exportObjects(schema)` returns a full list | `importObjects(schema, iterable)` consumes batches |
| `exportDocuments(schema)` returns a full list | `importDocuments(schema, iterable)` consumes batches |

Batch sizes must be positive. Use the context's stream/export helpers to read
old data, and `context.database` to inspect the changes made by the step.

Use `exportObjects` when you want to read the old data as typed objects:

```dart
final oldUsers = await context.exportObjects(OldUserSchema);
```

Use `exportDocuments` when you want map-shaped stored documents:

```dart
final oldDocuments = await context.exportDocuments(OldUserSchema);
```

Both export APIs read the original snapshot in ID order but return a full list,
so their result memory grows with the collection. Use `streamObjects` or
`streamDocuments` with the stream import helpers to keep buffers bounded.

Typed exports are easiest when the old model still represents the stored data
well:

```dart
final oldUsers = await context.exportObjects(OldUserSchema);

final newUsers = oldUsers.map(UserMigration.fromLegacy);
```

Document exports are useful when fields are being renamed heavily or when you
need direct access to persisted field names:

```dart
final oldDocuments = await context.exportDocuments(OldUserSchema);

final newUsers = oldDocuments.map((document) {
  return User()
    ..dbId = document['dbId'] as int
    ..email = document['email_address'] as String
    ..name = document['display_name'] as String;
});
```

## Registering Target Schemas

Call `registerTargetSchemas` before importing rewritten target data.

```dart
await context.registerTargetSchemas();
```

This prepares the collections to accept objects with the target model shapes.

For a streaming conversion, register first and keep reading the original snapshot:

```dart
await context.registerTargetSchemas();
await context.importObjectStream(
  UserSchema,
  context.streamObjects(OldUserSchema).map(UserMigration.fromLegacy),
);
```

Do not import target objects before target schemas have been registered.

## Importing Migrated Data

Use `importObjects` when you have new typed objects:

```dart
await context.importObjects(
  UserSchema,
  newUsers,
);
```

Use `importDocuments` when you have target documents:

```dart
await context.importDocuments(
  UserSchema,
  newDocuments,
);
```

Imported data should match the target schema. When converting old data, make
sure required fields are filled, removed fields are no longer needed, and ids
are preserved when records should remain the same logical objects.

Example typed conversion:

```dart
extension UserMigration on User {
  static User fromLegacy(OldUser old) {
    return User()
      ..dbId = old.dbId
      ..email = old.email
      ..name = old.fullName
      ..active = true;
  }
}
```

## Verification

Use `verifyBefore` to check assumptions before modifying data. For example,
if the updated app requires each user to have a non-empty email:

```dart
verifyBefore: (context) async {
  await for (final user in context.streamObjects(OldUserSchema)) {
    if (user.email.trim().isEmpty) {
      throw StateError('Cannot migrate a user without an email.');
    }
  }
},
```

Use `verifyAfter` to check the migrated result.

```dart
verifyAfter: (context) async {
  final version = await context.database.schemaVersion('users');
  if (version == null) {
    throw StateError('Users schema was not registered.');
  }
},
```

Verification callbacks should throw when the migration should stop. A thrown
error rolls back all changes from that step, including earlier import batches.

Useful checks include:

- required collections exist,
- document counts match expectations,
- required fields can be read,
- important ids were preserved,
- schema versions are registered,
- converted values are valid for the new model.

## Complete Example

This example migrates users from version 1 to version 2. Its validation
assumes the application requires a non-empty email for every user.

```dart
final migrations = CindelMigrationPlan(
  targetVersion: 2,
  baselineVersion: 1,
  steps: [
    CindelMigrationStep(
      fromVersion: 1,
      toVersion: 2,
      openSchemas: [OldUserSchema],
      targetSchemas: [UserSchema],
      verifyBefore: (context) async {
        // Validate the app's email requirement before converting records.
        await for (final user in context.streamObjects(OldUserSchema)) {
          if (user.email.trim().isEmpty) {
            throw StateError('Cannot migrate a user without an email.');
          }
        }
      },
      migrate: (context) async {
        await context.registerTargetSchemas();
        await context.importObjectStream(
          UserSchema,
          context.streamObjects(OldUserSchema).map(UserFromLegacy.fromLegacy),
        );
      },
      verifyAfter: (context) async {
        final version = await context.database.schemaVersion('users');
        if (version == null) {
          throw StateError('Users schema was not registered.');
        }
      },
    ),
  ],
);

final db = await Cindel.open(
  directory: appDataDirectory.path,
  schemas: [UserSchema],
  migrationPlan: migrations,
);
```

Example conversion helper:

```dart
extension UserFromLegacy on User {
  static User fromLegacy(OldUser old) {
    return User()
      ..dbId = old.dbId
      ..email = old.email
      ..name = old.fullName
      ..active = old.deletedAt == null;
  }
}
```

After the migration plan completes, `db` is opened with the target schemas.
App code can use the current generated API normally:

```dart
final users = await db.users.all().findAll();
```

## SQLite String Storage Upgrade in 1.1.5

SQLite databases created by older versions could change numeric-looking text
such as `'00123'` into `123`. Opening them with Cindel 1.1.5 or later applies the
storage correction automatically. You do not need to change your models or
increase the migration plan's version for this correction.

The first open can take longer and requires additional free storage. If it
fails, the affected table is left unchanged. Allow the open operation to finish
before using the database.

The correction preserves intact strings but cannot recover characters already
lost: an old stored `123` can be read as `'123'`, not the original `'00123'`.
Recover the original text from an unaffected backup or another data source.

## Practical Guidance

Keep migration steps small and versioned. A step from version 1 to 2 should
only handle that version move.

Preserve ids when existing records should remain the same logical objects.

Use typed exports when old schemas still produce useful Dart objects. Use
document exports when persisted field names are easier to work with.

Always pass the migration plan at app startup until every supported database is
expected to be at the target version.

Use `CindelMigrationPlan` and `CindelMigrationStep` to manage app upgrades. Test
with a copy of an older database, including a failed step and a second open
after success. Keep a backup before migrating important data.
