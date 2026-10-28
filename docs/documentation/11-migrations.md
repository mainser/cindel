# Migrations

Migrations let an app open existing stored data with old schemas, convert that
data to the current shape, and then continue with the current generated API.

Use a migration when an existing database cannot be safely opened with the new
schemas alone. Typical examples include renamed fields, removed fields, split
models, merged models, changed field types, or data rewrites that need
controlled conversion.

## SQLite String Storage Upgrade in 1.1.5

SQLite native and Web now declare string columns with `TEXT` affinity. Earlier
versions used `str`, which SQLite treats as numeric affinity: a string such as
`'00123'` could become the integer `123`, and subsequent typed reads could fail.
MDBX is unaffected by this storage defect.

When an existing Cindel table is registered during opening, the runtime detects
the legacy declaration and replaces that table transactionally. This is an
internal storage correction: application models, generated APIs, schema
versions, and `CindelMigrationPlan` target versions do not need to change.
IDs, reserved ID counters, relationships, collection revisions, SQL indexes,
and triggers are preserved. Copying rows does not fire the table's triggers.
If the conversion fails, the original table and its data are restored.

The first open of a legacy table copies its rows once using SQLite
`INSERT ... SELECT`. It does not collect documents into a Dart or Rust list.
That open needs time and disk space proportional to the affected table and its
transaction journal. Later opens inspect the column declarations without
rewriting the rows. New tables already use the corrected declaration.

This correction prevents future conversions; it cannot reconstruct text lost
by an earlier version. An already stored integer `123` becomes the readable
string `'123'`, not the unknowable original spelling (`'00123'`, `'+123'`, etc.).
Restoring the original spelling requires an unaffected backup or another source
containing the original value. Existing intact strings and nulls are preserved.

The automatic conversion recognizes Cindel's generated table layout. If the
physical SQL table was manually changed to add unsupported constraints, opening
reports an error rather than silently discarding those constraints.

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

| Read original step snapshot | Write private target workspace |
| --- | --- |
| `streamObjects(schema, batchSize: 100)` | `importObjectStream(schema, stream, batchSize: 100)` |
| `streamDocuments(schema, batchSize: 100)` | `importDocumentStream(schema, stream, batchSize: 100)` |
| `exportObjects(schema)` returns a full list | `importObjects(schema, iterable)` consumes batches |
| `exportDocuments(schema)` returns a full list | `importDocuments(schema, iterable)` consumes batches |

Batch sizes must be positive. Stream reads cap each native page at 4,096
records; increasing the requested size beyond that does not increase that
page cap. `context.database` operates on the working database; only the source
stream/export helpers promise reads from the original step snapshot.

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
