# Changelog

## 0.1.17

<!-- pub.dev prerelease: 0.1.17-dev.5 -->

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

## 0.1.16

- Added `putMany` as a public alias for manual and typed atomic bulk writes.

## 0.1.15

- Added pub.dev-oriented package metadata and documentation.
- Added package-level README guidance for installation, generation, and core
  database features.

## 0.1.14

- Added optimized native batch document reads.
- Regenerated Windows and Android prebuilt native libraries for ABI 4.
