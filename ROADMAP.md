# Cindel Roadmap

Cindel is a Flutter-first local database with a generated typed Dart API, a Rust
native core, MDBX as the default backend, SQLite as an explicit native backend,
and SQLite Web/OPFS as the browser backend.

[Status](#status) |
[Delivered](#delivered) |
[Current Focus](#current-focus) |
[Next](#next) |
[Later](#later) |
[Quality](#quality)

> Cindel is still pre-1.0. The typed public API and storage format can still
> change while backend parity, Web behavior, and release packaging settle.

## Status

The current development line is focused on a typed-only public contract:
application code should use generated collections, generated queries, typed
transactions, and typed watchers. MDBX, SQLite native, and SQLite Web must
adapt internally to that same public app surface.

Current package roles:

- `cindel`: runtime API, typed collections, typed queries, watchers,
  transactions, and backend loading.
- `cindel_annotations`: public annotations and shared schema metadata.
- `cindel_generator`: build-time source generator for annotated models.
- `cindel_flutter_libs`: prebuilt native libraries and Web runtime assets for
  Flutter apps.

Current backend policy:

- MDBX is the default native backend and the reference implementation for the
  typed API.
- SQLite is selectable explicitly and must stay aligned with the same typed API.
- Web uses the SQLite/OPFS Worker/Wasm runtime. It is still experimental, but it
  is a real typed backend path, not a separate app API.
- Unsupported backend behavior must fail explicitly instead of silently falling
  back to untyped storage.

Current public API policy:

- Public persistence is generated and typed.
- App code should use `db.users.put(...)`, `db.users.getAll(...)`,
  `db.users.where()...findAll()`, typed transactions, and typed watchers.
- Untyped collection-level document APIs are not part of the public direction.
- Backend-specific implementation details must not leak into app code.

## Delivered

### Typed Dart API

- `Cindel.open` and `Cindel.openInMemory`.
- Generated typed collections.
- Native auto-increment ids with `Id` and `autoIncrement`.
- Typed `put`, `putAll`, `putMany`, `get`, `getAll`, `delete`, and
  `deleteAll`.
- Typed unique replace helpers generated from unique indexes.
- Query-based `deleteFirst`, `deleteAll`, `updateFirst`, and `updateAll`.
- Explicit `readTxn` and `writeTxn`.
- In-memory databases for typed tests and short-lived typed work.
- Typed-only runtime paths for MDBX, SQLite native, and SQLite Web.

### Models And Schemas

- `@Collection` and generated collection schemas.
- `@Name` persisted collection and field names.
- `@Embedded` value objects and embedded object lists.
- `@ignore` transient fields.
- `@Enumerated` enum persistence by name, ordinal, or value field.
- Freezed classic class and primary-factory collection models, including
  parameter-level `@Index`, `@Enumerated`, and optional `@ignore` annotations.
- Supported persisted field shapes:
  - `bool`
  - `int`
  - `double`
  - `String`
  - `DateTime`
  - `Duration`
  - enums
  - embedded objects
  - nullable supported values
  - lists of supported non-list values
- Schema metadata persistence.
- Compatible additive schema version bumps.
- Rejection of unsafe type, id, and index option changes.
- Generated native reader and writer hooks for backend-specific storage.

### Queries

- Generated `where()` helpers for indexed fields.
- Generated `filter()` helpers for persisted fields.
- Equality, range, prefix, contains, suffix, and null predicates where
  supported.
- Boolean filter composition.
- `optional`, `anyOf`, and `allOf` query modifiers.
- `findAll`, `findFirst`, and `count`.
- Sorting and pagination.
- Secondary sort keys.
- Distinct queries.
- Single-property projections.
- Multi-property projections.
- Property aggregates.
- Nested filter helpers for fields inside single embedded objects.
- Nested filter helpers for fields inside embedded object-list elements.
- Deep equality for whole embedded object filters and embedded-list element
  equality filters.
- Native query-plan execution for supported typed queries on MDBX, SQLite, and
  Web SQLite.
- Typed native-reader materialization when a query needs Dart-side filtering.

### Indexes

- Value indexes.
- Unique indexes.
- Unique replace indexes with generated natural-key `putBy...` and
  `putAllBy...` helpers.
- Hash indexes.
- Case-insensitive string indexes.
- Word-token indexes.
- Primitive-list multi-entry indexes.
- Collection-level composite indexes.
- Native index maintenance for typed writes, updates, and deletes.

### Storage And Native Runtime

- Rust native core behind Dart FFI.
- MDBX storage backend for generated typed binary documents.
- SQLite storage backend for generated typed app data, including schema
  collection tables, open-time schema registration, typed batch writes, ordered
  reads, query-based update/delete, filter queries, sorted queries, projections,
  aggregates, transactions, watchers, and direct native typed reads.
- SQLite Web/OPFS Worker/Wasm backend for generated typed app data, including
  persisted schema metadata, runtime schema registration, typed batch writes,
  ordered reads, deletes, id allocation, native-document write/delete batches,
  index queries, native query-plan ids/documents/count/projection/aggregate/
  update/delete operations, collection revisions, change-set draining, explicit
  read/write transactions, nested-transaction rejection, and controlled-close
  rollback of active Web transactions.
- Web SQLite native batch writes with a direct wire encoder for generated rows
  and prepared SQLite insert statement reuse across full chunks in the Wasm
  runtime.
- Compact generated binary document format.
- Binary FFI payloads for ids, batches, filters, schema metadata, query plans,
  projections, aggregates, and watcher change sets.
- Native typed document writer and reader hooks.
- Native string-list reader for generated typed hydration.
- Current-document native dynamic bytes and list readers for generated MDBX
  typed hydration after the cursor has selected a document.

### Watchers

- Typed object watchers.
- Typed collection watchers.
- Query watchers.
- Lazy object, collection, and query watchers.
- `fireImmediately` support.
- Native collection revision counters.
- Native committed change sets with changed document ids.
- Local watcher notifications after commit only.
- Single-tab Web watcher path through Worker change sets.

### Platforms

- Android prebuilt libraries for:
  - `arm64-v8a`
  - `armeabi-v7a`
  - `x86_64`
- iOS prebuilt `xcframework`.
- macOS universal prebuilt library.
- Windows prebuilt library.
- Linux prebuilt library.
- Experimental Web SQLite Wasm runtime assets for browser Worker execution.
- Web Worker, JS glue, and Wasm runtime assets declared through
  `cindel_flutter_libs` so Flutter Web apps can receive them from the companion
  package instead of app-local copies.
- `Cindel.open(...)` routes Web callers through the packaged
  `cindel_flutter_libs` Worker/Wasm runtime while native callers keep MDBX as
  the default backend.
- Tag-based GitHub release workflow that builds Android, Apple, Linux, and
  Windows prebuilts before publishing coordinated package releases.
- Android release build validation.
- Windows desktop validation.
- Linux native prebuilt generation through WSL.
- Web SQLite/OPFS validation through browser probes for the Worker/Wasm
  runtime.
- Public open-time data migration tooling with database-level versions,
  before/after verification callbacks, paged export/import helpers, migrated
  schema registration, and backend compact requests across SQLite native, MDBX,
  and Web SQLite.
- Bounded `documentIdsPage` scans for maintenance tooling that needs to walk
  large collections without reading every id at once.
- Full typed backup/export/import streams with JSONL archives, checksum
  verification, native gzip compression, empty-target restore, and cross-backend
  SQLite/MDBX coverage.

## Current Focus

### Release Line

- Keep accumulating confirmed fixes in the `0.7.0` line until the next publish
  decision.
- Android, iOS, Linux, macOS, Windows, and Web runtime assets must be generated
  from the current native ABI before benchmarking or release validation.
- Keep root and package READMEs aligned with the actual package roles.
- Keep package changelogs current.

### Typed Backend Parity

- Keep MDBX as the reference backend for the typed API.
- Keep SQLite native aligned with the same typed operations, result ordering,
  errors, transaction behavior, and watcher behavior.
- Keep SQLite Web aligned with the same typed app code wherever the browser
  platform can support the behavior.
- Classify unsupported Web behavior explicitly and make it fail clearly instead
  of falling back to untyped storage.
- Keep parity labs focused on observable public typed API behavior.

### Runtime Improvements

- Keep the MDBX typed insert path close to Isar's streaming write model.
- Continue reducing extra work in MDBX generated binary serialization and batch
  writes.
- Keep SQLite behavior aligned with the typed app benchmark while MDBX remains
  the default backend.
- Continue Web SQLite/OPFS work on the shared SQLite engine, keeping the Web
  Worker as transport, scheduling, and Wasm initialization code rather than a
  separate app API.
- Keep Web benchmarks separated into UI, Worker, Wasm, SQLite, serialization,
  and OPFS/startup costs before optimization work.
- Preserve lazy local watcher change-set creation when no watcher is
  registered.

### Web Runtime

- Treat Web as an experimental but real backend for generated typed Flutter Web
  apps.
- Keep Web validation focused on SQLite/OPFS persistence, binary Worker
  payloads, query parity, transaction atomicity, watcher behavior, and browser
  storage behavior.
- Establish Web benchmark CSVs for the same typed app workloads used by native
  backend comparisons before starting optimization work.
- Keep single-tab behavior correct before evaluating multi-tab coordination.

## Next

### Release Hardening

- Run package analysis and tests from a clean release state.
- Run `dart pub publish --dry-run` for publishable packages.
- Validate Flutter Android, iOS, Linux, macOS, Windows, and Web consumers with
  current prebuilts/assets.
- Confirm package archives include the expected native and Web files.
- Keep example and package snippets on the correct version line.

### Typed API Coverage

- Keep tests centered on generated typed collections and generated queries.
- Add missing typed coverage before changing production behavior.
- Keep MDBX, SQLite native, and SQLite Web parity reports understandable enough
  to identify the exact typed API call, backend, expected result, and actual
  result.
- Prevent reintroduction of untyped collection-level persistence APIs.

### Web Platform Preview

- Keep Web asset packaging reproducible through the internal release workflow.
- Prove `flutter run -d chrome`, `flutter build web`, and served release builds
  load the Worker, JS glue, and `.wasm` assets without 404s.
- Validate fresh browser storage, reopen persistence, typed seed flows,
  transactions, queries, watchers, and checkout-style app mutations.
- Document secure-context, OPFS availability, storage quota, and current
  single-tab limitations before calling Web preview-ready.
- Keep multi-tab behavior out of the stable Web preview until the single-tab
  watcher path and persistence story are validated.

### Flutter App Performance

- Improve insert performance in real Flutter workloads.
- Improve hydration-heavy reads for large typed objects.
- Keep filter and sort paths close to native backend performance.
- Keep MDBX as the default backend for Cindel.

### Documentation

- Keep package READMEs concise and user-facing.
- Document public typed API usage directly.
- Document public limitations directly.
- Keep Freezed support documented as classic classes and single primary
  factories only; union/sealed multi-constructor models remain out of scope.
- Add focused examples for annotations, generator usage, runtime API, Flutter
  native libraries, and Flutter Web setup.

### Diagnostics

- Improve native error reporting across FFI.
- Add clearer Dart exception types for validation, schema, transaction, Web
  storage, and native storage failures.
- Improve generator errors for unsupported field shapes and invalid indexes.

## Later

### Migration And Storage Stability

- Add rollback guidance for production migration rollouts.
- Add richer migration diagnostics and native error details.
- Add database statistics around migrated collection sizes and compaction
  effects.

### Platforms

- Add broader Web browser validation after the Chrome/Edge Worker/OPFS path is
  stable.
- Evaluate multi-tab Web coordination with Web Locks or a single-writer
  coordinator after single-tab correctness is validated.

### Maintenance APIs

- Add database statistics.
- Add incremental backup or merge-restore only if a real app needs it.
- Add more maintenance operations beyond migration compact, bounded id pages,
  and full typed backup.
- Evaluate encryption at rest after storage layout and performance are stable.

### Relationships

- Keep embedded objects as the primary relationship model for now.
- Explore links only after embedded objects, migrations, and storage stability
  are mature.
- Consider one-to-one, one-to-many, many-to-many, backlinks, and lazy link
  loading later.

## Quality

Near-term quality goals:

- Keep Dart analyzer clean.
- Keep Rust tests passing.
- Keep package-level tests passing.
- Keep typed backend parity tests passing.
- Keep watcher behavior covered.
- Keep Web build and packaged asset checks passing.
- Keep package docs synchronized with the real typed API.

Future CI goals:

- Dart analyzer and tests.
- Rust tests.
- Android build smoke test.
- Windows desktop smoke test.
- Linux native/prebuilt validation.
- Web Worker/Wasm asset validation.
- Apple build smoke tests when macOS runner access is available.
