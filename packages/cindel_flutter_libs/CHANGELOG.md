# Changelog

## 1.1.6

- Updated the runtime to ABI 40 for nested-filter query updates.

## 1.1.5

- Updated the Web runtime with optimized reads and eligible unlimited query updates.
- Fixed SQLite string preservation and upgraded legacy string columns in the Web runtime.

## 1.1.4

- Fixed release packaging to include freshly built ABI 39 binaries on every platform.

## 1.1.3

- Added Swift Package Manager support for iOS/macOS alongside CocoaPods.
- Matched `cindel` 1.1.3 and native ABI 39.

## 1.1.2

- Matched `cindel` 1.1.2 and native ABI 35.

## 1.1.1

- Fixed Web worker rollback and resource cleanup during database closure.

## 1.0.0

- Released the first stable Flutter libraries package alongside `cindel` 1.0.0.

## 0.9.3

- Matched `cindel` 0.9.3 and ABI 34, fixing native embedded string-list reads.

## 0.9.2

- Matched `cindel` 0.9.2 with updated Web assets for the `deleteAll` fix.

## 0.9.1

- Aligned all Cindel packages with the coordinated 0.9.1 release.

## 0.9.0

- Updated native/Web assets for the `cindel` 0.9.0 Sync release.

## 0.7.0

- Updated native/Web runtimes for migrations, compaction, and paged document IDs; requires ABI 32 binaries.

## 0.6.5

- Aligned with `cindel` 0.6.5.

## 0.6.4

- Added Flutter Web plugin support and bundled the typed SQLite/OPFS Worker/Wasm runtime.
- Included Web CRUD, queries, transactions, and single-tab watchers.

## 0.6.1

- Added Web SQLite Wasm assets under `web/pkg`.

## 0.6.0

- Prepared native libraries for `cindel` 0.6.0 and its updated MDBX typed readers, retaining SQLite support.

## 0.5.13

- Added iOS/macOS platform metadata and automated native builds for all five desktop/mobile platforms.
- Retained MDBX as the default backend with explicit SQLite selection.

## 0.5.12

- Rebuilt Windows/Android/Linux libraries for 0.5.12 with MDBX streaming counts, aggregates, and projections.

## 0.5.11

- Rebuilt Windows/Android/Linux libraries for 0.5.11 with MDBX read/query and SQLite read/open improvements.

## 0.5.8

- Rebuilt Windows/Android/Linux libraries for the 0.5.8 storage format and `dbId` changes.

## 0.5.7

- Rebuilt the Windows library for the completed SQLite typed backend in 0.5.7.

## 0.5.6

- Rebuilt the Windows library for the SQLite `getAll` reader ABI in 0.5.6.

## 0.5.4

- Rebuilt Windows/Android/Linux libraries for ABI 29 with MDBX batch-write and query optimizations.

## 0.5.3

- Rebuilt Windows/Android/Linux libraries for the 0.5.3 native fixes.

## 0.5.2

- Rebuilt Windows/Android/Linux libraries to match `cindel` 0.5.2.

## 0.5.1

- Rebuilt Windows/Android/Linux libraries for the 0.5.0 native API, including typed string-list batch writers.

## 0.5.0

- Aligned package versions and rebuilt the Windows library for ABI 25 with MDBX read, write, filter, and schema improvements.

## 0.4.0

- Rebuilt Windows/Android/Linux libraries for ABI 23.

## 0.3.4

- Rebuilt Windows/Android/Linux libraries for ABI 17 with binary query result payloads.

## 0.3.3

- Rebuilt Windows/Android/Linux libraries for ABI 16 with binary watcher change sets.

## 0.3.2

- Rebuilt Windows/Android/Linux libraries for ABI 15 with native query plans.

## 0.3.1

- Rebuilt Windows/Android/Linux libraries for ABI 14 with binary schemas and metadata.

## 0.3.0

- Rebuilt Windows/Android/Linux libraries for ABI 13 with binary manual documents.

## 0.2.18

- Rebuilt Windows/Android/Linux libraries for ABI 12 with binary native filters.

## 0.2.17

- Rebuilt Windows/Android/Linux libraries for ABI 11 with binary indexes and indexed-write batches.

## 0.2.16

- Rebuilt Windows/Android/Linux libraries with cached MDBX schemas for faster reads; retained ABI 10.

## 0.2.15

- Rebuilt Windows/Android/Linux libraries for ABI 10 with binary ID lists.

## 0.2.13

- Rebuilt and validated Windows/Android/Linux libraries for ABI 9 with native aggregates.
- Added Linux plugin metadata and publication files.

## 0.2.12

- Rebuilt Windows/Android/Linux libraries with the updated MDBX v2 table layout.

## 0.2.11

- Rebuilt Windows/Android/Linux libraries with reduced MDBX allocations and buffer reuse.

## 0.2.10

- Rebuilt Windows/Android/Linux libraries with optimized MDBX auto-increment counters.

## 0.2.9

- Rebuilt Windows/Android/Linux libraries with composite and multi-entry indexes.

## 0.2.8

- Rebuilt Windows/Android/Linux libraries for ABI 8.

## 0.2.7

- Rebuilt Windows/Android/Linux libraries for ABI 7.

## 0.2.6

- Rebuilt Windows/Android/Linux libraries for ABI 6.

## 0.2.5

- Rebuilt native libraries for ABI 5 with MDBX as default and SQLite available.
- Added Linux to the advertised Android/Windows prebuilt platforms.

## 0.2.0

- Aligned package/plugin metadata with the coordinated 0.2.0 release, advertising Android/Windows prebuilts.

## 0.1.11

- Documented MDBX as the default backend and SQLite as an explicit alternative.

## 0.1.10

- Prepared the pub.dev preview with updated documentation, metadata, and examples.
- Limited published plugin support to Android/Windows and bundled MDBX-enabled binaries.

## 0.1.9

- Added pub.dev metadata and advertised Android/iOS/Windows support; Linux/macOS prebuilts remained pending.

## 0.1.8

- Rebuilt Android/Windows libraries for the current native ABI.
