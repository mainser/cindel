# Current Limits

Some capabilities are intentionally not part of Cindel's current public API.
This page summarizes the limits users should account for when designing an
application.

## General Limitations

The current public API does not include:

- incremental backups,
- merge-restore into a non-empty database,
- embedded-field indexes,
- nested lists,
- bundled hosted sync servers,
- public manual sync control commands,
- multi-tab Web coordination.

Most application code should be designed around the available generated typed
API:

```dart
final db = await Cindel.open(
  directory: directory.path,
  schemas: [UserSchema],
);

final users = await db.users.all().findAll();
```

For backups, use full archive import/export:

```dart
await CindelBackup.exportDatabase(
  database: db,
  collections: [CindelBackupCollection(UserSchema)],
  output: output,
);
```

Restore into an empty database opened with matching schemas.

## Modeling Limitations

Current modeling limits:

- indexes inside embedded classes are not supported,
- nested lists are not supported,
- Freezed union or sealed multi-constructor models are not supported.

Embedded objects are still useful for value-shaped data that belongs to a root
document, such as an address or a small settings object. Put indexes on root
collection fields when the app needs optimized lookups.

Freezed classic classes and single primary-factory models are supported. If a
model needs several union cases, keep that union outside the persisted Cindel
collection model or persist an explicit field such as `type` instead.

## Web Limitations

Current Web limits:

- MDBX is not used in browsers.
- Watcher delivery is single-tab.
- Sync watcher delivery is also single-tab.
- Multi-tab coordination is not supported.
- Browser storage quota and OPFS availability depend on the target browser.

Flutter Web still uses the same typed API:

```dart
final db = await Cindel.open(
  directory: 'app-data',
  schemas: [UserSchema],
);
```

Design Web apps so each tab can load its own view of local data. Do not rely on
one tab immediately receiving watcher notifications from another tab.

## Sync Limitations

Sync is experimental and configured only when the database opens.

The current public API does not include manual sync controls such as public
push, pull, pause, resume, or flush methods.

```dart
final db = await Cindel.open(
  directory: directory.path,
  schemas: [OrderSchema],
  sync: CindelSyncConfig(
    adapter: AppSyncAdapter(serverBaseUri),
  ),
);
```

The current sync API also does not include:

- bundled hosted sync servers,
- server-side auth or conflict rules,
- query updates while sync is enabled,
- Web multi-tab sync coordination.

When sync is enabled, replace query updates with typed reads and writes:

```dart
final todos = await db.todos.all().findAll();

for (final todo in todos) {
  todo.completed = true;
}

await db.todos.putAll(todos);
```

Your backend is responsible for authentication, validation, idempotency,
checkpoints, conflict handling, and correction rules.

## Roadmap / Future Notes

MDBX remains the default native backend. SQLite native and SQLite Web are
available through the same generated typed API.

Design application code around documented public APIs rather than assumptions
about future features.

Good current choices:

- use generated typed collections for CRUD,
- use generated queries for reads, deletes, and supported updates,
- use migrations for controlled schema/data changes,
- use full backups for archive flows,
- use sync adapter contracts for local-first replication,
- use Web APIs with the current single-tab watcher limitations in mind.

When a needed capability is listed as a current limit, keep that behavior in
application code or backend code rather than assuming Cindel will provide it
automatically.
