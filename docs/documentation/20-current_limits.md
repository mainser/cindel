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

The restore implementation requires the selected collections to be empty;
using a separate empty database also isolates restored migration metadata.

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

## Value And Memory Limits

`openInMemory` has the same public entrypoint across backends but does not
promise RAM-only storage: MDBX uses temporary files, SQLite native uses RAM,
and Web uses a unique persisted OPFS name. Web close does not delete that
database. See [temporary databases](02-getting_started.md#temporary-databases).

Supported model shapes are shared across all backends, but portable values must
fit the destination runtime. JavaScript Web requires safe integers, including
integer-backed dates and durations. Enum-list storage uses names; annotated
ordinal/value enum lists are not supported. See the
[type matrix](03-data_modeling.md#type-compatibility-across-backends).

Bounded query candidates and maintenance batches do not bound the entire
process's memory. `findAll`, multi-property results, and `putAll` inputs can
materialize full lists. Distinct needs keys for seen values, and backend
transactions/caches use additional memory. Current projection and aggregate
execution costs are described in
[projections and aggregates](08-projections_and_aggregates.md#windows-nulls-and-execution-cost).

Backups reject records beyond `maxRecordBytes`. Atomic restores and migration
steps require temporary disk storage, so check native disk capacity or browser
quota before large maintenance operations.

## Transactional Bulk Reads

Typed `getAll` supports active write transactions on all three backends. MDBX
combines its committed cursor with the requested pending values, including
deletions. It retains one copy per unique requested pending document for the
reader's lifetime; untouched committed documents still use the cursor without
copying their payloads. Pending data for unrequested IDs is not copied into the
reader. Returned Dart objects and lists also consume memory.

Use a native binary built with the 1.1.3 correction. The former MDBX error about
an active write transaction is fixed without changing the public API or ABI 39;
an older binary with the same ABI can still contain the defect.

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
