# Changelog

## 0.1.17

<!-- pub.dev prerelease: 0.1.17-dev.10 -->

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

## 0.1.16

- Added `putMany` as a public alias for manual and typed atomic bulk writes.

## 0.1.15

- Added pub.dev-oriented package metadata and documentation.
- Added package-level README guidance for installation, generation, and core
  database features.

## 0.1.14

- Added optimized native batch document reads.
- Regenerated Windows and Android prebuilt native libraries for ABI 4.
