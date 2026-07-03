# Migrations

Migrations let an application open existing stored data with old schemas,
rewrite it into the current schema shape, and then continue with the current
generated API.

Use migrations when a stored model changes in a way that cannot be handled by
opening the database with the new schemas alone.

## Concepts

Cindel stores a database-level data migration version inside the database. A
`CindelMigrationPlan` compares that stored version with `targetVersion`, runs
the missing ordered steps, persists each successful `toVersion`, and returns a
database opened with the target schemas.

```dart
final db = await Cindel.open(
  directory: directory.path,
  schemas: [UserSchema],
  migrationPlan: migrations,
);
```

A migration usually has this shape:

1. Open existing data with the schemas that can read it.
2. Export old objects or documents.
3. Register the target schemas.
4. Convert old data into the new model shape.
5. Import converted objects or documents.
6. Verify the result.
7. Let Cindel persist the completed migration version.

Use migrations for changes such as renamed fields, removed fields, split
models, merged models, changed field types, or data rewrites that must be
controlled.

## `CindelMigrationPlan`

`CindelMigrationPlan` declares the target data version and the ordered steps
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

Use `targetVersion` for the version the current application expects after all
required steps run.

Use `baselineVersion` for databases that do not yet have a stored migration
version.

Pass the same plan every time the application opens the database:

```dart
final db = await Cindel.open(
  directory: directory.path,
  schemas: [UserSchema],
  migrationPlan: migrations,
);
```

Completed steps are skipped on future opens. Missing steps are run in order
until the database reaches `targetVersion`.

## `CindelMigrationStep`

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
      oldUsers.map(User.fromLegacy),
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

Each step should do one controlled version move. For multiple releases, prefer
several small steps instead of one large step that tries to handle every old
shape at once.

## Exporting Old Data

Use `exportObjects` when the old generated schema can hydrate old typed
objects:

```dart
final oldUsers = await context.exportObjects(OldUserSchema);
```

Use `exportDocuments` when you want map-shaped stored documents:

```dart
final oldDocuments = await context.exportDocuments(OldUserSchema);
```

Both export APIs read existing data in id order with bounded batches. This
lets migration code process data predictably without loading by arbitrary query
order.

Use typed objects when conversion is easiest from old models:

```dart
final oldUsers = await context.exportObjects(OldUserSchema);

final newUsers = oldUsers.map(User.fromLegacy);
```

Use documents when the old model shape is inconvenient, when fields are being
renamed heavily, or when you need direct access to persisted field names:

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

The usual order is:

```dart
final oldUsers = await context.exportObjects(OldUserSchema);

await context.registerTargetSchemas();

await context.importObjects(
  UserSchema,
  oldUsers.map(User.fromLegacy),
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
sure required fields are filled, removed fields are not needed, and ids are
preserved when records should keep their identity.

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

## Before And After Verification

Use `verifyBefore` to check assumptions before modifying data.

```dart
verifyBefore: (context) async {
  final ids = await context.database.documentIds('users');
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
error prevents the step from being marked complete.

Good checks include:

- required collections exist,
- document counts match expectations,
- required fields can be read,
- important ids were preserved,
- schema versions are registered,
- converted values are valid for the new model.

## Complete Migration Example

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
        await context.database.documentIds('users');
      },
      migrate: (context) async {
        final oldUsers = await context.exportObjects(OldUserSchema);

        await context.registerTargetSchemas();

        await context.importObjects(
          UserSchema,
          oldUsers.map(User.fromLegacy),
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
  directory: directory.path,
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
Application code can use the current generated API normally:

```dart
final users = await db.users.all().findAll();
```

## Practical Guidance

Keep migration steps small and versioned. A step from version 1 to 2 should
only handle that version move.

Preserve ids when existing records should remain the same logical objects.

Use typed exports when old schemas still produce useful Dart objects. Use
document exports when persisted field names are easier to work with.

Always pass the migration plan at application startup until every supported
database is expected to be at the target version.

Use lower-level migration primitives such as `migrationVersion`,
`setMigrationVersion`, `registerMigratedSchemas`, and `compact` only for
controlled tooling. Most application migrations should use
`CindelMigrationPlan` and `CindelMigrationStep`.
