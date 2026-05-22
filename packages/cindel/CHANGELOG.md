# Changelog

## 0.1.17-dev.2

- Added optional `libmdbx` dependency and Windows build probe behind the
  native `mdbx` Cargo feature.
- Documented MDBX-01 build feasibility and LLVM/libclang requirements.
- Updated Cindel package dependency constraints for the next development
  preview.
- Removed dates from changelog headings so pub.dev renders version labels cleanly.

## 0.1.17-dev.1

- Prepared the first pub.dev development preview.
- Switched Cindel package dependencies from local paths to hosted development
  preview constraints.
- Declared Android and Windows as the currently available prebuilt platforms.

## 0.1.16

- Added `putMany` as a public alias for manual and typed atomic bulk writes.

## 0.1.15

- Added pub.dev-oriented package metadata and documentation.
- Added package-level README guidance for installation, generation, and core
  database features.

## 0.1.14

- Added optimized native batch document reads.
- Regenerated Windows and Android prebuilt native libraries for ABI 4.
