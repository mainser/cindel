# Backup And Advanced Helpers

Most application code should use generated typed collections. Cindel also
exposes backup and low-level database helpers for maintenance flows, import and
export tooling, diagnostics, and generated code.

Use these APIs when you need database-wide archives, controlled scans, or
advanced collection maintenance. For normal reads and writes, prefer generated
collections such as `db.users`.

## `CindelBackup`

`CindelBackup` exports and imports full typed database archives.

The archive format is JSONL after decompression and includes:

- a header,
- schema records,
- document records,
- a footer with document count and checksum.

Native Dart uses gzip by default. Web-compatible callers can pass
`compression: CindelBackupCompression.none` and store or transport the same
JSONL bytes without gzip.

### Exporting A Database

Use `CindelBackup.exportDatabase` to stream a backup archive to a
`StreamConsumer<List<int>>`.

```dart
final report = await CindelBackup.exportDatabase(
  database: db,
  collections: [
    CindelBackupCollection(UserSchema),
    CindelBackupCollection(OrderSchema),
  ],
  output: File('backup.cindelbak').openWrite(),
);
```

The returned `CindelBackupReport` reports:

- document count,
- archive size,
- checksum,
- compression.

Example:

```dart
print('Exported ${report.documentCount} documents');
print('Archive size: ${report.archiveSizeBytes}');
```

For Web-compatible uncompressed export:

```dart
final report = await CindelBackup.exportDatabase(
  database: db,
  collections: [
    CindelBackupCollection(UserSchema),
  ],
  compression: CindelBackupCompression.none,
  output: output,
);
```

### Importing A Database

Use `CindelBackup.importDatabase` to stream an archive into an empty database.

```dart
await CindelBackup.importDatabase(
  database: restoredDb,
  collections: [
    CindelBackupCollection(UserSchema),
    CindelBackupCollection(OrderSchema),
  ],
  input: File('backup.cindelbak').openRead(),
);
```

Restore targets must be opened with matching schemas and must be empty.

```dart
final restoredDb = await Cindel.open(
  directory: restoredDirectory.path,
  schemas: [UserSchema, OrderSchema],
);
```

Use the same collection schemas during import that were used to export the
archive.

### Backup Supporting Types

Backup APIs include:

- `CindelBackup.exportDatabase`: streams a backup archive to a
  `StreamConsumer<List<int>>`.
- `CindelBackup.importDatabase`: streams an archive into an empty database.
- `CindelBackupCollection`: keeps generated schema typing intact for backup.
- `CindelBackupProgress`: reports phase, collection, and document count.
- `CindelBackupReport`: reports document count, archive size, checksum, and
  compression.

Use backup APIs for full database archive flows. Do not use them as a
replacement for normal application reads and writes.

## `allocateId`

`allocateId` allocates the next id for a collection.

```dart
final id = await db.allocateId('todos');
```

Generated typed `put` and `putAll` use id allocation automatically when an
object id is `autoIncrement`.

```dart
final todo = Todo()
  ..title = 'Write docs';

await db.todos.put(todo);

print(todo.dbId);
```

Most application code should not call `allocateId` directly. Use it for
advanced tooling that needs to reserve ids before constructing documents.

When calling `allocateId`, pass the persisted collection name:

```dart
final id = await db.allocateId('users');
```

## `documentIds`

`documentIds` returns every id in a collection, ordered ascending.

```dart
final ids = await db.documentIds('todos');
```

To hydrate objects from ids, use the typed collection:

```dart
final todos = await db.todos.getAll(ids);
```

Use `documentIds` for maintenance flows where the full id list is expected to
be manageable:

```dart
final ids = await db.documentIds('users');
final users = await db.users.getAll(ids);
```

For very large collections, prefer `documentIdsPage` so the app can process ids
in bounded batches.

## `documentIdsPage`

`documentIdsPage` returns a bounded page of ids in a collection, ordered
ascending.

```dart
final ids = await db.documentIdsPage(
  'todos',
  afterId: afterId,
  limit: 1000,
);
```

The optional `afterId` cursor is exclusive. `limit` must be greater than zero.

Example paged scan:

```dart
int? afterId;

while (true) {
  final ids = await db.documentIdsPage(
    'todos',
    afterId: afterId,
    limit: 1000,
  );

  if (ids.isEmpty) {
    break;
  }

  final todos = await db.todos.getAll(ids);
  // Export, verify, or copy this page.

  afterId = ids.last;
}
```

Use `documentIdsPage` for backup/export tooling, verification jobs, copy flows,
or maintenance tasks where reading every id at once may be too large.

SQLite native, MDBX, and Web SQLite expose the same API.

## Practical Guidance

Use generated typed collections for normal app features:

```dart
final todos = await db.todos.all().findAll();
```

Use backup APIs for full archive import/export.

Use `documentIdsPage` instead of `documentIds` when collection size is unknown
or potentially large.

Use persisted collection names when calling low-level helpers:

```dart
await db.documentIds('todos');
```

Keep advanced helper usage isolated in tooling, maintenance services, or
well-named repository methods so normal application code stays typed.
