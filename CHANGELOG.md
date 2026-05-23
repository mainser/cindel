# Changelog

All notable Cindel workspace changes will be documented here.

Cindel is pre-1.0.0, so breaking API and packaging changes can still happen
while the core design settles.

## 0.2.1

- Added an MDBX index abstraction boundary in the Cindel native core.
- Kept the storage format, public Dart API, and prebuilt binary symbols
  unchanged.
- Expanded the Cindel generator `analyzer` dependency constraint to support
  the current stable analyzer release line reported by pub.dev.
- Replaced deprecated analyzer field-origin checks in the generator.

## 0.2.0

- Prepared the coordinated `0.2.0` pub.dev release line for all publishable
  Cindel packages.
- Updated public documentation, package examples, release notes, and
  publication guidance to describe MDBX as the default backend and SQLite as
  the explicit secondary backend.
- Aligned package dependency constraints on the `^0.2.0` Cindel package set.

## 0.1.18

- Made MDBX the default backend for new databases.
- Kept SQLite available as an explicit secondary backend.
- Moved the next touched publishable packages back to normal pub.dev versions
  instead of development prerelease suffixes.

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
- Expanded the MDBX benchmark comparison and recorded the first adoption
  decision for continuing toward storage parity.
- Added shared Rust `StorageEngine` contract tests for SQLite and MDBX.
- Completed MDBX-06 storage parity for the non-explicit-transaction surface,
  including schema versions, compatible migrations, unique index enforcement,
  batch rollback, ids, revisions, and indexed reads/writes.
- Added MDBX-07 explicit transaction integration using an internal write log
  committed through one MDBX transaction, plus shared Rust transaction contract
  tests for SQLite and MDBX.
- Added the MDBX-08 public Dart backend option and FFI backend selector while
  keeping SQLite as the default backend.
- Completed MDBX-09 full Dart behavior parity by running the package suite
  against MDBX and fixing staged transaction reads plus multi-handle MDBX
  environment reuse.
- Completed MDBX-10 packaging for Windows and Android by regenerating prebuilt
  native libraries with MDBX support and documenting the remaining Linux and
  Apple validation gap.
- Added the MDBX-11 CI backend matrix with separate SQLite and MDBX validation
  jobs plus a manual backend benchmark workflow.

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
