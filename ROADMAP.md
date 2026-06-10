# Cindel Roadmap

Cindel is a Flutter-first local database with a generated Dart API, a Rust
native core, MDBX as the default backend, and SQLite available as an explicit
secondary backend.

[Status](#status) |
[Delivered](#delivered) |
[Current Focus](#current-focus) |
[Next](#next) |
[Later](#later) |
[Quality](#quality)

> Cindel is still pre-1.0. The API and storage format can still change while
> the optimized native path settles.

## Status

The current development line is focused on hardening the optimized MDBX runtime,
keeping the generated typed API stable, keeping SQLite aligned as the complete
explicit secondary backend for the current typed app surface, and bringing the
experimental Web SQLite/OPFS runtime toward a reproducible preview.

Current package roles:

- `cindel`: runtime API, typed collections, queries, watchers, and FFI loading.
- `cindel_annotations`: public annotations and shared schema metadata.
- `cindel_generator`: build-time source generator for annotated models.
- `cindel_flutter_libs`: prebuilt native libraries for Flutter apps.

Current native backend policy:

- MDBX is the default backend.
- SQLite remains selectable explicitly.
- Web uses the experimental SQLite/OPFS runtime path; MDBX is not a browser
  backend and remains the native default.

## Delivered

### Dart API

- `Cindel.open` and `Cindel.openInMemory`.
- Manual document API by collection and id.
- Generated typed collections.
- Native auto-increment ids with `Id` and `autoIncrement`.
- Bulk `putAll`, `getAll`, and `deleteAll`.
- Query-based `deleteFirst`, `deleteAll`, `updateFirst`, and `updateAll`.
- Explicit `readTxn` and `writeTxn`.
- In-memory databases for tests and short-lived work.

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

### Queries

- Generated `where()` helpers for indexed fields.
- Generated `filter()` helpers for persisted fields.
- Equality, range, prefix, contains, suffix, and null predicates where
  supported.
- Boolean filter composition.
- `findAll`, `findFirst`, and `count`.
- Sorting and pagination.
- Distinct queries.
- Property projections.
- Property aggregates.
- Nested filter helpers for fields inside single embedded objects.
- Nested filter helpers for fields inside embedded object-list elements.
- Deep equality for whole embedded object filters and embedded-list element
  equality filters.
- Native query-plan execution for supported generated binary-document queries
  on MDBX and SQLite.

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
- Native index maintenance for writes, updates, and deletes.

### Storage And Native Runtime

- Rust native core behind Dart FFI.
- MDBX storage backend.
- SQLite storage backend for the generated typed app path, including schema
  collection tables, open-time schema registration, `putAll`, `getAll`,
  query-based update/delete, filter queries, sorted queries, projections,
  aggregates, and direct native typed reads.
- Experimental Web SQLite/OPFS baseline with persisted schema metadata and
  runtime schema registration for native document cursors after reopen.
- Experimental Web typed CRUD worker/Wasm surface over the shared SQLite
  engine, including typed batch writes, ordered reads, deletes, id allocation,
  stored-document reads, native-document write/delete batches, index queries,
  native query-plan ids/documents/count/projection/aggregate/update/delete
  operations, collection revisions, change-set draining, explicit
  read/write transactions, nested-transaction rejection, and controlled-close
  rollback of active Web transactions.
- Compact generated binary document format.
- Generic binary manual document format.
- Binary FFI payloads for ids, batches, filters, schema metadata, query plans,
  projections, aggregates, and watcher change sets.
- Native typed document writer and reader hooks.
- Native string-list reader for generated typed hydration.
- Current-document native dynamic bytes and list readers for generated MDBX
  typed hydration after the cursor has selected a document.

### Watchers

- Manual document watchers.
- Collection watchers.
- Typed object watchers.
- Query watchers.
- Lazy object, collection, and query watchers.
- `fireImmediately` support.
- Native collection revision counters.
- Native committed change sets with changed document ids.
- Local watcher notifications after commit only.

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
- Tag-based GitHub release workflow that builds Android, Apple, Linux, and
  Windows prebuilts before publishing coordinated package releases.
- Android release build validation.
- Windows desktop validation.
- Linux native prebuilt generation through WSL.
- Web SQLite/OPFS validation through browser probes for the Worker/Wasm
  runtime.

## Current Focus

### Release Line

- Keep accumulating confirmed fixes in the `0.6.4` line until the next publish
  decision.
- Android, iOS, Linux, macOS, and Windows native prebuilts are generated by the
  release workflow for the current native ABI.
- Keep root and package READMEs aligned with the actual package roles.
- Keep package changelogs current.

### Runtime Improvements

- Keep the MDBX typed insert path close to Isar's streaming write model.
- Continue reducing extra work in MDBX generated binary serialization and batch
  writes.
- Keep SQLite behavior aligned with the typed app benchmark while MDBX remains
  the default backend.
- Continue Web SQLite/OPFS work on the shared SQLite engine, keeping the Web
  Worker as transport, scheduling, and Wasm initialization code rather than a
  separate storage backend.
- Preserve lazy local watcher change-set creation when no watcher is
  registered.

### Web Runtime

- Package the Web Worker, Wasm glue, and `.wasm` assets so Flutter Web apps can
  consume Cindel without copying files by hand.
- Keep Web validation focused on SQLite/OPFS persistence, binary Worker
  payloads, query parity, transaction atomicity, and browser behavior.
- Establish Web benchmark CSVs for the same typed app workloads used by native
  backend comparisons before starting optimization work.
- Add single-tab Web watcher support after the Worker emits committed change
  sets through the existing watcher model.

## Next

### Release Hardening

- Run package analysis and tests from a clean release state.
- Run `dart pub publish --dry-run` for publishable packages.
- Validate Flutter Android, iOS, Linux, macOS, and Windows consumers with
  prebuilts.
- Validate Flutter Web consumers with packaged Worker/Wasm assets once Web
  packaging is in place.
- Confirm package archives include the expected native files.
- Keep example and package snippets on the correct version line.

### Web Platform Preview

- Make Web asset packaging reproducible for local development and release
  workflows.
- Prove `flutter run -d chrome`, `flutter build web`, and served release builds
  load the Worker, JS glue, and `.wasm` assets without 404s.
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
- Document public limitations directly.
- Keep Freezed support documented as classic classes and single primary
  factories only; union/sealed multi-constructor models remain out of scope.
- Add focused examples for annotations, generator usage, runtime API, and
  Flutter native libraries.

### Diagnostics

- Improve native error reporting across FFI.
- Add clearer Dart exception types for validation, schema, transaction, and
  native storage failures.
- Improve generator errors for unsupported field shapes and invalid indexes.

## Later

### Migration And Storage Stability

- Add public migration tooling only when the storage format is close to 1.0.
- Support explicit export and import utilities.
- Add index rebuild and verification tools.
- Add guidance for backups and rollback before migrations.

### Platforms

- Add broader Web browser validation after the Chrome/Edge Worker/OPFS path is
  stable.
- Evaluate multi-tab Web coordination with Web Locks or a single-writer
  coordinator after single-tab watchers are working.

### Maintenance APIs

- Add database statistics.
- Add explicit compaction or maintenance operations.
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
- Keep watcher behavior covered.
- Keep package docs synchronized with the real API.

Future CI goals:

- Dart analyzer and tests.
- Rust tests.
- Android build smoke test.
- Windows desktop smoke test.
- Linux native/prebuilt validation.
- Apple build smoke tests when macOS runner access is available.
