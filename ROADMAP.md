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

## Status

Delivered items describe the current `dev` implementation, including the 1.1.3
development line; they do not imply that a package version is already published.
Next and Later are remaining validation work or candidates, not release promises.

The current development line is focused on a typed-only public contract:
application code should use generated collections, generated queries, typed
transactions, typed watchers, and open-time sync configuration. MDBX, SQLite
native, and SQLite Web must adapt internally to that same public app surface.

Current package roles:

- `cindel`: runtime API, typed collections, typed queries, watchers,
  transactions, sync, and backend loading.
- `cindel_annotations`: public annotations and shared schema metadata.
- `cindel_generator`: build-time source generator for annotated models.
- `cindel_flutter_libs`: prebuilt native libraries and Web runtime assets for
  Flutter apps.

Current backend policy:

- MDBX is the default native backend and the reference implementation for the
  typed API.
- SQLite is selectable explicitly and must stay aligned with the same typed API.
- Web uses the SQLite/OPFS Worker/Wasm runtime as a supported typed backend
  path, not a separate app API.
- Unsupported backend behavior must fail explicitly instead of silently falling
  back to untyped storage.

Current public API policy:

- Public persistence is generated and typed.
- App code should use `db.users.put(...)`, `db.users.getAll(...)`,
  `db.users.where()...findAll()`, typed transactions, and typed watchers.
- Untyped collection-level document APIs are not part of the public direction.
- Backend-specific implementation details must not leak into app code.
- Sync is configured only at open time through
  `Cindel.open(..., sync: CindelSyncConfig(...))`. There must be no public
  `db.sync` command surface.

## Delivered

### Typed Dart API

- `Cindel.open` and `Cindel.openInMemory`.
- Open-time sync opt-in with `CindelSyncConfig`.
- Generated typed collections.
- Auto-increment ids with `Id` and `autoIncrement` on all three backends,
  including batch ID reservations for `putAll` and overlapping-transaction
  regression coverage.
- Typed `put`, `putAll`, `putMany`, `get`, `getAll`, `delete`, and
  `deleteAll`.
- Typed unique replace helpers generated from unique indexes.
- Query-based `deleteFirst`, `deleteAll`, `updateFirst`, and `updateAll`.
- Explicit `readTxn` and `writeTxn`, with read-only enforcement and rollback of
  writes and ID reservations.
- `openInMemory` for typed tests: SQLite native uses RAM, MDBX uses a temporary
  directory cleaned up on close, and Web uses a unique SQLite/OPFS database name.
- Typed-only runtime paths for MDBX, SQLite native, and SQLite Web.
- Query updates with generated nested filters, with or without distinct, across
  all three backends; MDBX evaluates paths in the engine (ABI 40).

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
- Nullable lists and nullable elements, preserving null, empty, and populated
  lists through single/bulk writes, reads, and projections on all three backends.
- Shared embedded types and nested list/object hydration through generated code.
- Exact numeric-looking strings in SQLite native/Web, with a transactional,
  one-time upgrade of legacy string columns; already lost spelling is unrecoverable.
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
- Limited `findFirst`, including property projections, and optimized
  non-distinct object counts across all three backends.
- SQLite engine projection and aggregate operations avoid intermediate
  full-object hydration, with progressive aggregation without distinct. Web
  planned property queries use these operations; the current SQLite native
  public property-query path still hydrates typed objects in Dart.
- Exact MDBX 64-bit integer filtering and ordering, plus collision-safe distinct
  equality in the native and Dart query paths.
- MDBX direct ID scans in both directions, including filters; bounded-memory
  top-k for eligible limited sorts; progressive unsorted distinct; and ascending
  integer-index range scans ordered by field and ID for eligible limited queries.
- MDBX ID-only query results without copying document payloads, with regression
  checks for retained candidates, discarded payloads, and window completion.
- Early termination of eligible limited MDBX updates, with cursor-read
  regressions and shared first/bulk update-window contracts across all backends.
- Redundant order elimination for unlimited, non-distinct native query updates
  of unindexed fields in MDBX and SQLite native/Web, preserving validation,
  index-sensitive paths and rollback.
- Candidate prefiltering for eligible SQLite native/Web distinct updates,
  preserving ordered representatives, windows and atomic ID batches, with
  shared backend regressions and candidate-reader checks. SQLite update
  candidates are converted to documents once, including nested-filter selection.

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
- Vendored MDBX 0.14.4 integration, preserving the configured storage parameters.
- Native ABI 39 with explicit mismatch rejection before database opening.
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
- Reused schema offsets in Web readers and immutable SQLite row layouts per
  result batch, preserving per-document validation.
- MDBX point reads without auxiliary table opens, and bounded SQLite native/Web
  prepared-read reuse with exclusive readers and schema invalidation.
- Web `getAll` response encoding directly from retrieved rows, without intermediate
  document clones or a second database pass, with checked response sizing.
- One private Dart ID snapshot and one hydrated result list for `getAll` across
  all backends, skipping the extra pass for models without relationships.
- Exact-sized ID batch encoding without per-ID fragments or a redundant native
  list copy, preserving range validation and the existing wire format.
- Prepared-row reuse and preallocated, growable `getAll` results, retaining
  field validation, pending-write snapshots and independent duplicate objects.
- Compact generated binary document format.
- Binary FFI payloads for ids, batches, filters, schema metadata, query plans,
  projections, aggregates, and watcher change sets.
- Native typed document writer and reader hooks.
- Native string-list reader for generated typed hydration.
- Current-document native dynamic bytes and list readers for generated MDBX
  typed hydration after the cursor has selected a document.
- Engine error propagation through MDBX and SQLite native/Web, retaining
  operation, backend, code, and cause when available instead of returning
  partial reads as successful results.
- Dart error types for open, closed-database, transaction, schema, query,
  unique-index, and native failures, with controlled-failure regression tests.

### Relationships And Maintenance

- Typed links/backlinks with explicit `load`/`save` operations.
- Atomic removal of incoming/outgoing links on deletes and unique-index
  evictions, including query and batch operations.
- Paged, atomic `cleanupOrphanLinks` for existing databases.
- Versioned open-time migrations with verification callbacks, streaming
  transformations, and optional compaction across all three backends.
- Atomic migration steps using temporary disk storage and bounded batches;
  data, schemas, indexes, links, IDs, and version commit together.
- Bounded `documentIdsPage` scans for maintenance tooling.
- Typed JSONL backups from a consistent snapshot, including links and migration
  metadata, checksum verification, native gzip, and portable uncompressed output.
- Schema-validated, atomic restores into empty selected collections using
  temporary disk storage (OPFS on Web), with bounded batches and typed
  multi-collection export/import regression coverage.

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
- Shared polling per collection within each database handle.
- Persistent SQLite native/Web revisions committed atomically with writes.
- Safe watcher shutdown, including pending Web snapshot reads, with regressions
  for polling cost, rolled-back writes, and closure.

### Platforms

- Android prebuilt libraries for:
  - `arm64-v8a`
  - `armeabi-v7a`
  - `x86_64`
- iOS static XCFramework for ARM64 devices and ARM64/x64 simulators.
- macOS universal dynamic XCFramework, distributed as a ZIP to preserve
  framework symlinks through Pub packaging.
- Swift Package Manager and CocoaPods support on iOS/macOS with the same public
  Cindel API; macOS framework loading retains legacy dylib support.
- Windows prebuilt library.
- Linux prebuilt library.
- Web SQLite Wasm runtime assets for browser Worker execution.
- Web Worker, JS glue, and Wasm runtime assets declared through
  `cindel_flutter_libs` so Flutter Web apps can receive them from the companion
  package instead of app-local copies.
- `Cindel.open(...)` routes Web callers through the packaged
  `cindel_flutter_libs` Worker/Wasm runtime while native callers keep MDBX as
  the default backend.
- Release workflow that builds Android, Apple, Linux, Windows, and Web artifacts
  before publishing matching-version packages, with ABI/opening checks where
  binaries can execute on the runner.
- Android release build validation.
- Windows desktop validation.
- Linux native prebuilt generation through WSL.
- Web SQLite/OPFS validation through browser probes for the Worker/Wasm
  runtime.
- Separate manual Apple workflow on macOS/Xcode for SwiftPM and CocoaPods with
  Flutter 3.41.0 and 3.47.8. Validation on 2026-10-24 passed macOS Debug/Release,
  iOS Release compilation, and iOS simulator ABI/CRUD/rollback/reopen checks
  in all four combinations using locally archived and extracted Pub packages.
- Apple packaging regressions for FlutterFramework manifest evaluation,
  framework symlink preservation, and smoke-test stdout/stderr capture.

### Sync

- Experimental local-first Sync configured only when opening a database.
- Backend-neutral `CindelSyncAdapter` push/pull contract.
- Durable internal outbox storage in the same database as app data.
- Checkpoint persistence and stable client sequence tracking across reopen.
- Automatic background scheduler with status/error callbacks.
- Typed puts, bulk puts, unique-index puts, deletes, query deletes, and link
  replacements captured as internal sync mutations.
- Remote upserts, deletes, and link replacements applied through guarded
  internal writes so watchers update without re-enqueueing outgoing mutations.
- Backend corrections applied locally through `CindelPushResult`.
- Multi-collection sync mutation and remote change flow.
- SQLite native, MDBX, and SQLite Web implementation paths.
- Query updates explicitly rejected while sync is enabled.
- Internal HTTP-backed validation covers offline writes, reopen, backend
  correction, second-client pull, remote update, and replicated delete across
  SQLite and MDBX.

## Current Focus

### Release Line

- Android, iOS, Linux, macOS, Windows, and Web runtime assets must be generated
  from the current native ABI before benchmarking or release validation.
- Keep root and package READMEs aligned with the actual package roles.
- Keep package changelogs current.
- Keep package versions aligned where binary/Web assets need to be rebuilt for
  the release.

### Sync Hardening

- Keep the public surface restricted to open-time configuration and callbacks.
- Keep all sync actions internal: outbox, retry, checkpoint, remote apply, and
  scheduler.
- Expand real-app sync labs before expanding the public API.
- Validate sync behavior across SQLite native, MDBX, and Web SQLite.
- Keep unsupported sync operations explicit, especially query updates.
- Keep backend requirements documented: idempotent mutation ids, stable
  checkpoints, backend-owned auth, validation, conflict policy, and correction
  rules.

### Typed Backend Parity

- Keep the shared generated Dart API as the contract for all three backends.
- Keep SQLite native aligned with the same typed operations, result ordering,
  errors, transaction behavior, and watcher behavior.
- Keep SQLite Web aligned with the same typed application code; document browser
  storage and numeric limits without introducing a separate public API.
- Classify unsupported Web behavior explicitly and make it fail clearly instead
  of falling back to untyped storage.
- Keep parity labs focused on observable public typed API behavior.

### Runtime Improvements

- Measure remaining serialization, batch-write, and hydration costs before
  selecting further optimizations; batch IDs and query improvements listed in
  Delivered are already implemented.
- Compare time and retained memory against the current implementation. Preserve
  existing performance, and justify any correctness-related cost with measurements.
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

- Treat Web as a supported backend for generated typed Flutter Web apps.
- Keep Web validation focused on SQLite/OPFS persistence, binary Worker
  payloads, query parity, transaction atomicity, watcher behavior, and browser
  storage behavior.
- Establish Web benchmark CSVs for the same typed app workloads used by native
  backend comparisons before starting optimization work.
- Keep single-tab behavior correct before evaluating multi-tab coordination.
- Keep Web Sync scoped to single-tab behavior.

## Next

### Release Hardening

These are repeatable checks for each release, not missing implementations.
Apple consumer validation and the local `cindel_flutter_libs` publication-payload
audit have passed on the current development line; final release artifacts
still need their own checks.

- Run package analysis and tests from a clean release state.
- Run `dart pub publish --dry-run` or `flutter pub publish --dry-run` for
  publishable packages.
- Validate Flutter Android, iOS, Linux, macOS, Windows, and Web consumers with
  current prebuilts/assets.
- Confirm package archives include the expected native and Web files.
- Keep example and package snippets on the correct version line.
- Confirm `cindel` and `cindel_flutter_libs` are published on the same release
  line when the binary assets are regenerated.

### Sync Validation

- Add broader sync tests for multi-collection writes, backend corrections,
  reopen with pending outbox, replicated deletes, and remote apply watcher
  notifications.
- Add Web sync coverage beyond static contract tests before calling Web Sync
  preview-ready.
- Validate sync with generated code from app-style models, not only hand-written
  schemas and test fixtures.
- Keep private console or integration validation against a local HTTP sync
  server before each sync release.
- Document any adapter contract changes before they are exposed in a release.

### Typed API Coverage

- Keep tests centered on generated typed collections and generated queries.
- Add missing typed coverage before changing production behavior.
- Keep MDBX, SQLite native, and SQLite Web parity reports understandable enough
  to identify the exact typed API call, backend, expected result, and actual
  result.
- Prevent reintroduction of untyped collection-level persistence APIs.

### Web Platform Validation

- Keep Web asset packaging reproducible through the internal release workflow.
- Prove `flutter run -d chrome`, `flutter build web`, and served release builds
  load the Worker, JS glue, and `.wasm` assets without 404s.
- Validate fresh browser storage, reopen persistence, typed seed flows,
  transactions, queries, watchers, and checkout-style app mutations.
- Document secure-context, OPFS availability, storage quota, and current
  single-tab limitations.
- Keep multi-tab behavior unsupported until the single-tab watcher path and
  persistence story are validated.

### Flutter App Performance

- Improve insert performance in real Flutter workloads.
- Improve hydration-heavy reads for large typed objects.
- Keep filter and sort paths close to native backend performance.
- Keep MDBX as the default backend for Cindel.

### Documentation

- Keep package READMEs concise and user-facing.
- Document public typed API usage directly.
- Document public limitations directly.
- Keep Sync docs beginner-friendly and explicit that users provide their own
  backend adapter/server.
- Keep Freezed support documented as classic classes and single primary
  factories only; union/sealed multi-constructor models remain out of scope.
- Add focused examples for annotations, generator usage, runtime API, Flutter
  native libraries, and Flutter Web setup.

### Diagnostics

- Refine generator messages for unsupported field shapes and invalid indexes
  where concrete cases remain unclear. Runtime error propagation and Dart
  exception types are already delivered.

## Later

### Migration And Storage Stability

- Add rollback guidance for production migration rollouts.
- Improve migration-specific recovery guidance beyond the delivered atomic
  steps and engine error details.
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

- Keep embedded objects as the primary value-object model.
- Keep links/backlinks focused on explicit `load`/`save` operations.
- Add richer relationship ergonomics only after sync, Web, and release
  packaging stabilize.

### Sync Expansion

- Evaluate query update sync only after a reliable per-document mutation design
  exists.
- Evaluate public manual sync controls only if a real application needs them;
  do not add `db.sync` by default.
- Evaluate realtime signals only as "wake up and pull"; checkpointed pull must
  remain the source of truth.
- Evaluate Web multi-tab sync only after single-tab Web Sync is stable.
- Consider conflict-resolution helpers only if backend-owned correction is not
  sufficient for real apps.

## Quality

Near-term quality goals:

- Keep Dart analyzer clean.
- Keep Rust tests passing.
- Keep package-level tests passing.
- Keep typed backend parity tests passing.
- Keep watcher behavior covered.
- Keep sync outbox, retry, checkpoint, and remote-apply behavior covered.
- Keep Web build and packaged asset checks passing.
- Keep package docs synchronized with the real typed API.

Implemented validation infrastructure:

- `ci.yml`: Dart format/analyze, package and generator tests, Rust tests, and
  dedicated MDBX, SQLite, and Web backend jobs. It has reusable/manual entry
  points and no push trigger.
- `apple-validation.yml`: independent manual Apple build, packaging, and
  consumer checks. It does not call CI, release, or package publication.
- `release.yml`: invokes CI, builds current artifacts with locked Cargo
  dependencies, verifies ABI/opening and Apple consumers, and checks package
  archives before publishing. It remains separate from manual Apple validation.
- Local Pana audit on 2026-10-24 of the complete `cindel_flutter_libs` 1.1.3 publication
  payload: 160/160, all 5 public API elements documented, and a publication
  dry-run with no warnings. Pub.dev performs its own analysis after publication.

Remaining validation work includes broader Flutter consumer coverage on Android,
Windows, and Linux, plus browser coverage beyond the current Web probes.
Existing tests and packaging checks must continue to pass as the code evolves.
