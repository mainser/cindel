# Migrations

Migrations let an app open existing stored data with old schemas, convert that
data to the current shape, and then continue with the current generated API.

Use a migration when an existing database cannot be safely opened with the new
schemas alone. Typical examples include renamed fields, removed fields, split
models, merged models, changed field types, or data rewrites that need
controlled conversion.

## Mental Model

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
2. Register target schemas in the private workspace.
3. Stream old objects or documents from the original step snapshot.
4. Convert each value into the new model shape.
5. Import the converted stream in batches.
6. Verify the result.
7. Let Cindel mark the step as complete.

After the plan completes, app code uses the current generated API normally.

## Atomic Steps and Memory

MDBX and SQLite native/Web execute each step in a private disk-backed workspace.
The original stays unchanged until `verifyAfter` succeeds. Cindel then publishes
data, schemas, indexes, links, ID counters, and `toVersion` in one native
transaction. An error discards that step; earlier committed steps remain. A
concurrent write to the original rejects publication instead of overwriting it.
Callbacks' external effects, such as network requests or other files, are not
part of the transaction.

Use the streaming helpers for large collections:

```dart
await context.registerTargetSchemas();
await context.importObjectStream(
  UserSchema,
  context.streamObjects(OldUserSchema, batchSize: 100).map(UserMigration.fromLegacy),
  batchSize: 100,
);
```

`streamObjects` and `streamDocuments` always read the original step snapshot,
including after target schema registration. Reads seek after the last ID,
retain at most 4,096 records per page, and stop a page once its encoded data
reaches 1 MiB (one large record may exceed that). Import helpers retain one
batch. Application buffering and objects retained by callbacks are additional
memory. Schema metadata and backend caches/dirty pages are outside these buffer
bounds; this is not a fixed process-RSS guarantee.

Preparing and publishing each step each copy the database once, record by
record. Temporary disk space for a full copy and the engines' transaction
storage is required. Normal success, callback failure, or handle closure
removes the private workspace; abrupt process termination may leave temporary
files. No live database files are replaced.

Saved links survive schema reconstruction when both identities remain. Links
to removed identities are cleaned before `verifyAfter`. Preserve IDs when
relationships should continue referring to the same objects.

Compaction runs after publication. If it fails,
`CindelMigrationMaintenanceError.committedVersion` identifies the already
committed step; reopening skips it. Low-level schema registration methods used
outside a migration plan do not acquire these per-step guarantees.

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

Use `baselineVersion` for databases that do not yet have a stored migration
version.

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
    final oldUsers = await context.exportObjects(OldUserSchema);

    await context.registerTargetSchemas();

    await context.importObjects(
      UserSchema,
      oldUsers.map(UserMigration.fromLegacy),
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

Use `exportObjects` when the old generated schema can hydrate useful old typed
objects:

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

This registers the target schemas in migrated mode and prepares the target
collections for imported data.

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

Use `verifyBefore` to check assumptions before modifying data.

```dart
verifyBefore: (context) async {
  final ids = await context.database.documentIdsPage('users', limit: 1);
  if (ids.isEmpty) {
    return;
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
error discards all changes from that step, including batches already written
to its private workspace.

Useful checks include:

- required collections exist,
- document counts match expectations,
- required fields can be read,
- important ids were preserved,
- schema versions are registered,
- converted values are valid for the new model.

## Complete Example

This example migrates users from version 1 to version 2.

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
        await context.database.documentIdsPage('users', limit: 1);
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

## Practical Guidance

Keep migration steps small and versioned. A step from version 1 to 2 should
only handle that version move.

Preserve ids when existing records should remain the same logical objects.

Use typed exports when old schemas still produce useful Dart objects. Use
document exports when persisted field names are easier to work with.

Always pass the migration plan at app startup until every supported database is
expected to be at the target version.

Use lower-level migration primitives such as `migrationVersion`,
`setMigrationVersion`, `registerMigratedSchemas`, and `compact` only for
controlled tooling. Most app migrations should use `CindelMigrationPlan` and
`CindelMigrationStep`.
