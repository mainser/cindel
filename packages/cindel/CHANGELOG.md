# Changelog

## 0.2.2

- Added an internal MDBX layout prototype for native performance benchmarks.
- Added a benchmark backend that compares SQLite, the current MDBX layout, and
  the layout prototype with the same workload.
- Kept the public Dart API, production storage layout, and native binary
  symbols unchanged.

## 0.2.1

- Added an internal MDBX index abstraction boundary for key creation, unique
  checks, index replacement, deletion, collection clearing, and index stats.
- Kept the existing MDBX storage layout and public Dart API unchanged.
- Updated the development generator dependency constraint to the `0.2.1`
  release line.

## 0.2.0

- Prepared the Cindel API package for the coordinated `0.2.0` release line.
- Updated hosted Cindel package constraints to `^0.2.0`.
- Refreshed package documentation for MDBX as the default backend, SQLite as an
  explicit fallback, and the Android/Windows prebuilt binary scope.

## 0.1.18

- Made MDBX the default storage backend for new Cindel databases.
- Kept SQLite available through `backend: CindelStorageBackend.sqlite`.
- Updated package documentation for the default backend switch.

## 0.1.17

- Prepared the first pub.dev development preview.
- Switched Cindel package dependencies from local paths to hosted development
  preview constraints.
- Declared Android and Windows as the currently available prebuilt platforms.
- Added optional `libmdbx` dependency and Windows build probe behind the
  native `mdbx` Cargo feature.
- Documented MDBX-01 build feasibility and LLVM/libclang requirements.
- Updated Cindel package dependency constraints for the next development
  preview.
- Removed dates from changelog headings so pub.dev renders version labels cleanly.
- Added the internal Rust backend selection boundary while keeping SQLite as
  the FFI default backend.
- Fixed an analyzer lint reported by pub.dev for an unnecessary `await`.
- Added a package example page for pub.dev.
- Added a library-level documentation comment for dartdoc/pub.dev analysis.
- Added the MDBX key encoding spike for document, index, unique index, and
  range-bound keys without changing the default SQLite backend.
- Added the feature-gated minimal `MdbxStorage` prototype and benchmark
  backend selection for SQLite, MDBX, or both.
- Expanded the native benchmark to cover open, schema registration, indexed
  writes, reads, indexed queries, batch writes, and deletes for the MDBX first
  adoption decision.
- Added shared Rust `StorageEngine` contract tests for SQLite and MDBX.
- Brought MDBX storage parity up to the non-explicit-transaction contract,
  including schema versions, compatible migrations, unique index enforcement,
  batch rollback, ids, revisions, and indexed reads/writes.
- Added MDBX explicit transaction integration through an internal write log
  that commits staged writes inside one MDBX transaction without storing
  self-referential transaction handles.
- Added shared Rust transaction contract tests for SQLite and MDBX covering
  commit, rollback, read transaction write rejection, nested transaction
  rejection, and id allocation rollback.
- Added the public `CindelStorageBackend` option and FFI backend selector so
  callers can explicitly choose SQLite or MDBX while SQLite remains the
  default backend.
- Added backend-parameterized Dart tests so the full Cindel package suite can
  run against SQLite or MDBX.
- Added MDBX read-your-writes parity for staged write transactions and shared
  same-directory MDBX environments across multiple Dart database handles.
- Updated package installation snippets for the MDBX-enabled Android and
  Windows prebuilt binaries.

## 0.1.16

- Added `putMany` as a public alias for manual and typed atomic bulk writes.

## 0.1.15

- Added pub.dev-oriented package metadata and documentation.
- Added package-level README guidance for installation, generation, and core
  database features.

## 0.1.14

- Added optimized native batch document reads.
- Regenerated Windows and Android prebuilt native libraries for ABI 4.
