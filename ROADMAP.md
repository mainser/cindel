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
keeping the generated typed API stable, and keeping SQLite aligned as the
complete explicit secondary backend for the current typed app surface.

Current package roles:

- `cindel`: runtime API, typed collections, queries, watchers, and FFI loading.
- `cindel_annotations`: public annotations and shared schema metadata.
- `cindel_generator`: build-time source generator for annotated models.
- `cindel_flutter_libs`: prebuilt native libraries for Flutter apps.

Current native backend policy:

- MDBX is the default backend.
- SQLite remains selectable explicitly.
- Web is out of scope until the native desktop/mobile path is stable.

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
- Native query-plan execution for supported MDBX binary-document queries.

### Indexes

- Value indexes.
- Unique indexes.
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
  query-based update/delete, filter queries, sorted queries, and direct native
  typed reads.
- Compact generated binary document format.
- Generic binary manual document format.
- Binary FFI payloads for ids, batches, filters, schema metadata, query plans,
  projections, aggregates, and watcher change sets.
- Native typed document writer and reader hooks.
- Native string-list reader for generated typed hydration.

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
- Windows prebuilt library.
- Linux prebuilt library.
- Android release build validation.
- Windows desktop validation.
- Linux native prebuilt generation through WSL.

## Current Focus

### Release Line

- Keep accumulating confirmed fixes in the `0.5.2` line until the next publish
  decision.
- Regenerate native prebuilts before release so `cindel_flutter_libs` matches
  the current native ABI.
- Keep root and package READMEs aligned with the actual package roles.
- Keep package changelogs current.

### Runtime Improvements

- Keep the MDBX typed insert path close to Isar's streaming write model.
- Continue reducing extra work in MDBX generated binary serialization and batch
  writes.
- Keep SQLite behavior aligned with the typed app benchmark while MDBX remains
  the default backend.
- Preserve lazy local watcher change-set creation when no watcher is
  registered.

## Next

### Release Hardening

- Run package analysis and tests from a clean release state.
- Run `dart pub publish --dry-run` for publishable packages.
- Validate Flutter Android, Windows, and Linux consumers with regenerated
  prebuilts.
- Confirm package archives include the expected native files.
- Keep example and package snippets on the correct version line.

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

- Generate and validate iOS native binaries.
- Generate and validate macOS native binaries.
- Add Apple platforms to the advertised Flutter libs package only after the
  binaries are bundled and tested.
- Revisit web after the native path is stable.

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
