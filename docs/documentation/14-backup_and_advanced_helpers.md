# Backup And Advanced Helpers

Most application code should use generated typed collections. Cindel also
exposes backup and low-level database helpers for maintenance flows, import and
export tooling, diagnostics, and generated code.

Use these APIs when you need database-wide archives, controlled scans, or
advanced collection maintenance. For normal reads and writes, prefer generated
collections such as `db.users`.

## `CindelBackup`

`CindelBackup` exports typed archives and imports them into an empty target
opened with matching schemas. MDBX, SQLite native, and SQLite Web use the same
public API and generated schemas. Include the target collections of every
forward link in the collection set, even if a collection currently has no rows.

### Export And Import

Supply a `StreamConsumer<List<int>>` for output and a `Stream<List<int>>` for
input. This keeps file, browser download, and transport handling in the caller:

```dart
final collections = [
  CindelBackupCollection(UserSchema),
  CindelBackupCollection(OrderSchema),
];

final report = await CindelBackup.exportDatabase(
  database: db,
  collections: collections,
  output: output,
  compression: CindelBackupCompression.none,
  batchSize: 1000,
  onProgress: (progress) {
    print('${progress.phase}: ${progress.documents} documents');
  },
);

print('Documents: ${report.documents}');
print('JSONL bytes: ${report.uncompressedBytes}');
print('Archive bytes: ${report.archiveBytes}');

await CindelBackup.importDatabase(
  database: restoredDb,
  collections: collections,
  input: input,
  compression: CindelBackupCompression.none,
  batchSize: 1000,
);
```

`restoredDb` must be opened separately with those generated schemas. The
heterogeneous `collections` list preserves each schema's model type without
requiring explicit type arguments on each `CindelBackupCollection`.

For native file I/O, `output` can be `File(path).openWrite()` and `input` can be
`File(path).openRead()`, using `dart:io`. Web callers provide browser-compatible
streams instead; the backup calls remain the same.

Export pipes its stream into the supplied consumer and closes that consumer
when the pipe completes. Give each export its own output and await the export
future before reading or sharing the archive. Do not write more data or flush
an already closed file sink afterward. If export fails, the output can contain
an incomplete archive; completion of `exportDatabase` is the success signal.

Compression defaults to gzip on native and none on Web. Choose `none`
explicitly on both for a portable uncompressed archive. Web does not provide
the built-in gzip codec. Import must use the archive's compression; there is
no automatic compression detection.

### Archive Contents And Compatibility

Version 2 archives contain newline-delimited JSON records after decompression:

- a header with archive version, backend, creation time, and migration version,
- schema manifests,
- typed document records with their IDs,
- saved forward-link records,
- a footer with document/link counts and a checksum.

Import rebuilds indexes and backlinks from the restored data and forward links,
restores ID allocation state from the imported IDs, and restores the migration
version. An archive is not a copy of in-memory loaded relationship objects.
Use compatible generated schemas and values supported by the destination
runtime, including [Web numeric limits](03-data_modeling.md#value-representation-and-portable-limits).
The same API does not bypass schema validation.

`CindelBackupReport` exposes `documents`, `uncompressedBytes`, `archiveBytes`,
`checksum`, and `compression`. Progress callbacks receive `phase`, `collection`
(which can be null for metadata), and `documents`. Progress counts processed
documents; it does not mean an import has committed.

The checksum is FNV-1a over non-footer JSONL records. It detects accidental
corruption; it does not authenticate or encrypt an archive.

### Snapshot And Atomic Restore

Export holds one read snapshot while reading schemas, documents, and links.
Later writes do not produce a mixed-time archive. The snapshot remains open
while the caller consumes the stream, so a slow output prolongs its lifetime.
Do not start backup operations inside an application transaction.

Import validates archive structure, schema compatibility, record limits,
counts, and checksum while staging data on disk. It publishes documents,
indexes, links, ID counters, and migration metadata atomically after validation.
Failure before publication leaves the target unchanged; a failed batch is not
a partially restored live database. The target's emptiness is checked as part
of restoration. Wait for `importDatabase` to complete before using restored
contents.

The emptiness requirement concerns the selected restore collections. A separate
empty database is the simplest restore destination: it also avoids changing
database-wide migration metadata alongside unrelated existing collections.
Keep every forward-link target in the selected set. Progress notifications
during staging are not permission to expose partially restored data to the UI.

Version 1 archives do not contain relationships. Restoring such an archive
with linked schemas requires `allowLegacyWithoutLinks: true`; this explicitly
accepts a documents-only restore and cannot reconstruct the missing links.
There is no incremental backup or merge-restore into existing data.

### Batching, Memory, And Temporary Storage

Both operations accept:

| Option | Default | Meaning |
| --- | --- | --- |
| `batchSize` | `1000` | Maximum batch/page record count; valid range is 1 through 100000. |
| `maxRecordBytes` | `16 * 1024 * 1024` | Maximum size of an individual uncompressed JSONL record. Must be positive. |

Export pages through IDs and links and serializes documents progressively.
Import additionally bounds document/link batches by a 1 MiB encoded-data
budget; one larger record is handled on its own, up to `maxRecordBytes`.
It does not retain all imported documents until publication.

These are application-buffer bounds, not a fixed process-memory guarantee.
Schema metadata, decoded objects, one record's encoding, compression buffers,
engine caches, and transaction pages also consume memory. A caller that
collects the complete stream into a list defeats streaming's memory benefit.

Restoration requires temporary disk space for staging and engine transaction
storage; on Web this uses browser storage quota. Staging is cleaned up on
normal completion, failure, or handle closure. Abrupt process termination may
leave temporary files. No live database file replacement is required.

## `allocateId` And `allocateIds`

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

For a reserved range, use one call:

```dart
final ids = await db.allocateIds('todos', 100);
```

`allocateIds` returns the reserved IDs as a list. A zero count returns an empty
list; a negative count is invalid. Allocation changes database state and is
not allowed inside `readTxn`. Reservations are not gapless numbering: see
[bulk ID allocation](04-generated_typed_api.md#automatic-ids-in-bulk-writes).

Mutable models normally use automatic assignment. These helpers are also
useful for immutable models that need their final ID at construction time;
see [immutable IDs](03-data_modeling.md#ids-in-immutable-models). Use them for
advanced tooling that needs to reserve IDs before constructing documents.

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

SQLite native, MDBX, and Web SQLite expose the same API. When all pages must
represent one consistent view, run the complete loop inside `db.readTxn`.
Separate calls outside a transaction can observe intervening writes. Keep
processing incremental rather than accumulating every page in memory.

## Orphan-Link Maintenance

`cleanupOrphanLinks()` checks persisted relationship edges in bounded pages and
atomically removes those whose source or target document no longer exists.
Normal deletion already removes incoming and outgoing links transactionally.
Use this helper outside explicit transactions for older data or maintenance;
see [relationships](05-relationships.md#deletion-and-orphan-cleanup).

## Maintenance Metadata

Cindel stores a small amount of database metadata for schemas and migrations.
Most applications do not need to read it during normal use, but it can help in
maintenance tools, diagnostics, and migration checks.

### `migrationVersion`

`migrationVersion` returns the data migration version stored for the database.
This is separate from each collection's schema version.

```dart
final version = await db.migrationVersion();
```

Migration plans update this value after a successful migration. Application
screens usually should not depend on it.

### `compact`

`compact` invokes backend maintenance after work such as a completed migration.
Call it outside any explicit transaction:

```dart
await db.compact();
```

SQLite executes `VACUUM`. MDBX's current helper completes an empty write
transaction through its configured storage policy; it does not create a
separate compacted database copy or promise a smaller file. Do not depend on
identical physical file-size changes across backends.

Most apps should let `CindelMigrationPlan` handle compaction through its
`compactOnSuccess` option. Call `compact` directly only from maintenance code
that already controls when cleanup is safe.

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
