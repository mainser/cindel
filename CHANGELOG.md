# Changelog

All notable Cindel workspace changes will be documented here.

Cindel is pre-1.0.0, so breaking API and packaging changes can still happen
while the core design settles.

## 0.1.17

- Prepared the first pub.dev development preview.
- Switched package dependencies from local paths to hosted development preview
  constraints.
- Declared Android and Windows as the currently available prebuilt platforms.
- Added optional `libmdbx` dependency and Windows build probe behind the native
  `mdbx` Cargo feature.
- Documented MDBX-01 build feasibility and LLVM/libclang requirements.
- Updated package versions and hosted dependency constraints for the next
  development preview.
- Removed dates from changelog headings so pub.dev renders version labels
  cleanly.
- Added the internal Rust backend selection boundary while keeping SQLite as
  the FFI default backend.
- Fixed an analyzer lint reported by pub.dev for an unnecessary `await`.
- Added package example pages so pub.dev can render Example tabs for the
  publishable packages.
- Added library-level documentation comments to public package entrypoints for
  dartdoc/pub.dev analysis.
- Added the MDBX-03 key encoding spike for deterministic MDBX document,
  index, unique index, and range-bound keys.
- Updated Cindel Flutter libs example constraints for the current development
  preview.
- Added the MDBX-04 minimal storage prototype and benchmark backend selector.
- Updated Cindel Flutter libs example constraints for the MDBX-04 development
  preview.

## 0.1.16

- Added `CindelDatabase.putMany` and `CindelTypedCollection.putMany` as public
  aliases for atomic bulk writes.

## 0.1.15

- Added pub.dev-oriented metadata to the publishable Cindel packages.
- Added package-level README and CHANGELOG files for the public packages.
- Added a pub.dev publication preparation plan under `docs/`.
- Updated public wording to describe Cindel as an ultra-fast, lightweight NoSQL
  local database built on its own Rust native core.
- Added real repository and maintainer information for publication materials.

## 0.1.14

- Added a native batch document read path so collection reads, indexed queries,
  watchers, migrations, and `getAll` avoid one FFI call per document.
- Replaced watcher snapshot stringification with allocation-light deep
  comparison.
- Bumped the native ABI to 4 and regenerated Windows and Android prebuilt
  libraries.
- Added Rust coverage for ordered batch reads with missing documents.

## 0.1.13

- Added explicit migration callbacks to `Cindel.open` and
  `Cindel.openInMemory`.
- Added `CindelMigration` helpers for field renames, collection renames,
  document backfills, and index rebuilds.
- Added dry-run migration diagnostics through `Cindel.dryRunMigration`.
- Added native schema registration after explicit migrations so renamed fields
  and changed index metadata can advance schema versions intentionally.
- Bumped the native ABI to 3 and regenerated Windows and Android prebuilt
  libraries.
- Expanded schema migration tests with versioned fixtures for backfills, field
  renames, collection renames, dry-run diagnostics, and rebuilt indexes.

## 0.1.12

- Added persisted schema metadata and automatic additive schema versioning.
- Added incompatible schema and index option rejection in the native storage
  layer.
- Exposed `CindelDatabase.schemaVersion` and example UI schema version display.
- Bumped the native ABI to 2 and regenerated Windows and Android prebuilt
  libraries.

## 0.1.11

- Added in-memory database support through `Cindel.openInMemory`.
- Added `Cindel.openInMemory` schema registration and typed collection tests.
- Added native in-memory storage isolation tests.
- Updated the Todo example and repository tests to use in-memory databases for
  fast local verification.

## 0.1.10

- Added collection, document, object, query, and lazy watchers.
- Added native collection revision counters so streams can emit after committed
  changes.
- Updated the Todo example to watch live collections through generated typed
  accessors.
- Added watcher tests for local writes, external handles, lazy streams,
  `fireImmediately`, and query-visible changes.

## 0.1.9

- Added generated embedded object and embedded object list schema support.
- Added expanded schema serialization for nested Dart object graphs.
- Added generator tests and typed round-trip coverage for embedded models.

## 0.1.8

- Added word-token index support for simple full-text-style lookups.
- Added case-insensitive word normalization for generated query helpers.
- Added Todo example prefix search over indexed title words.
- Added Rust and Dart tests for word indexes.

## 0.1.7

- Added value, hash, unique, and case-insensitive index variants.
- Added generated query helpers for index variants.
- Added native uniqueness enforcement and index metadata validation.
- Added tests for duplicate unique values, hash range rejection, and
  case-insensitive lookups.

## 0.1.6

- Added sorting, pagination, distinct, and primitive property projections to
  typed queries.
- Added generated sort/distinct/property helpers.
- Added tests for query modifier order and projected field values.

## 0.1.5

- Added generated filter builders for non-indexed predicates.
- Added boolean filter composition and typed query filtering.
- Added tests for string, numeric, boolean, grouped, and indexed-plus-filter
  queries.

## 0.1.4

- Added explicit read and write transaction APIs.
- Added transaction-aware watcher notifications.
- Added rollback behavior for failed write transactions.

## 0.1.3

- Added native atomic batch writes and deletes.
- Added manual and typed `putAll`, `getAll`, and `deleteAll` APIs.
- Added query `deleteFirst` and `deleteAll` operations.
- Added rollback tests for invalid batch writes and deletes.

## 0.1.2

- Added typed query builder primitives.
- Added generated indexed equality, prefix, range, first, and count helpers.
- Updated the Todo example search flow to use generated query builders.

## 0.1.1

- Added native auto-increment id allocation.
- Added generated typed collection accessors.
- Added typed collection CRUD and watcher APIs.
- Updated the Todo example to use native auto-increment ids and typed
  collections.

## 0.1.0

- Added the first usable Cindel vertical slice with Dart API, FFI bindings,
  Rust native core, SQLite storage, schemas, indexes, and generated models.
- Added Windows and Android prebuilt native library workflow.
- Added package layout for `cindel`, `cindel_annotations`, `cindel_generator`,
  and `cindel_flutter_libs`.
- Added the Cindel Todo Flutter example app.

## 0.0.1

- Initial Cindel workspace scaffold and architecture notes.
