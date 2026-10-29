# Changelog

## 1.1.6

- Reduced candidate loading for eligible updates with `distinct` in SQLite native and Web, preserving selection and atomicity.

## 1.1.5

- Improved `get`/`getAll` performance and reduced temporary allocations across all backends.
- Optimized limited MDBX updates and eligible unlimited query updates across all backends.
- Fixed numeric-looking strings in SQLite native/Web and upgraded legacy string columns.

## 1.1.4

- Released alongside corrected ABI 39 binaries in `cindel_flutter_libs` 1.1.4.

## 1.1.3

- Fixed MDBX `getAll` inside `writeTxn` and generated list/embedded types across backends.
- Improved backup type validation, relationship backups, and atomic restores.
- Added atomic migration steps and bounded-memory backup, restore, and migration processing.
- Improved relationship cleanup and engine error propagation.
- Shared watcher polling, persisted SQLite revisions, and fixed Web watcher shutdown errors.
- Added macOS framework loading for SwiftPM/CocoaPods, retaining dylib support.
- Updated the native ABI to 39.

## 1.1.2

- Optimized eligible MDBX limited, indexed, ID, and distinct queries.
- Improved `findFirst`, `count`, `putAll`, and SQLite native/Web projections and aggregates.
- Fixed auto-increment ID and distinct collisions across backends.
- Fixed MDBX read isolation, 64-bit integer queries, and empty string-list reads.
- Updated the native ABI to 35.

## 1.1.1

- Fixed repeated and concurrent database closure across native and Web backends.
- Added strict native ABI 34 validation before opening a database.

## 1.1.0

- Updated MDBX to 0.14.4 and its Rust wrapper to 0.9.0, retaining existing tuning.
- Adapted native cursors, assertions, and Windows exception handling to the new engine.

## 1.0.0

- Released the first stable version with matching 1.0.0 package dependencies.

## 0.9.3

- Fixed generated embedded string-list reads and MDBX query watchers.
- Fixed Web embedded fields, unique-replace lookups, indexed queries, and nested filters.
- Updated the native ABI to 34.

## 0.9.2

- Exposed `CindelDatabase.deleteAll(collection, ids)` on Web, matching native backends.

## 0.9.1

- Aligned package dependencies with the coordinated 0.9.1 Sync release.

## 0.9.0

- Added opt-in experimental Sync across all backends, with adapters, persistent outbox/checkpoints, and background scheduling.
- Propagated remote changes to watchers without re-enqueuing them.
- Rejected query updates while Sync is enabled.

## 0.8.0

- Added typed `CindelLink`/`CindelLinks`, persisted forward links, and read-only backlinks across all backends.
- Added generated relation metadata, validation, and watcher notifications.

## 0.7.0

- Added versioned open-time migrations with verification, data rewriting, and optional compaction across all backends.
- Added paged document IDs and typed JSONL backups with checksums, progress, native gzip, and empty-target restore validation.
- Updated the native ABI to 32.

## 0.6.5

- Updated documentation links and the `hooks` dependency.
- Fixed a Web library documentation warning.

## 0.6.4

- Unified the generated typed API across MDBX, SQLite native, and Web/OPFS through `Cindel.open`.
- Removed the separate Web entrypoint and untyped collection document APIs.
- Completed Web CRUD, queries, transactions, and single-tab watchers.
- Optimized SQLite native/Web batch reads and writes; added native projections and aggregates.

## 0.6.3

- Added the SQLite Web/OPFS engine, worker transport, and typed CRUD foundation.
- Added persistent Web schemas and packaged Worker/Wasm assets.

## 0.6.2

- Added `@Name` mappings and unique-replace indexes with generated `putBy...`/`putAllBy...` helpers.
- Persisted MDBX auto-increment counters to prevent ID reuse after reopening.
- Updated annotations to `^0.5.4` and the development generator to `^0.6.1`.

## 0.6.1

- Added public Cindel runtime errors compatible with existing `StateError` handling.

## 0.6.0

- Added `optional`, `anyOf`, `allOf`, list-length filters, and nested embedded-list filters.
- Improved native embedded serialization and MDBX `getAll` reads.
- Fixed deep equality for embedded objects and lists.
- Updated the development generator to `^0.6.0`.

## 0.5.13

- Added iOS/macOS prebuilt platform metadata and coordinated tag-based publishing.

## 0.5.12

- Streamed eligible MDBX counts, aggregates, and projections to reduce materialization.
- Fixed Windows native FFI layout generation.

## 0.5.11

- Optimized MDBX string-list writes, reads, updates, and unsorted index queries.
- Improved SQLite string-list reads and avoided unnecessary metadata on typed opens.
- Preserved typed hydration after generic writes; updated the development generator to `^0.5.9`.

## 0.5.10

- Added native embedded-object/list readers and writers, plus nested single-object filters.
- Fixed SQLite typed embedded/list reads and projections; embedded-list nested queries remained unsupported.
- Updated the development generator to `^0.5.8`.

## 0.5.9

- Added Freezed primary-factory schema coverage and updated the development generator to `^0.5.7`.

## 0.5.8

- Changed generated primary IDs to `dbId`, allowing ordinary indexed `id` fields.
- Removed legacy CDBF document compatibility.
- Expanded generated containment filters to strings, lists, and embedded values.

## 0.5.7

- Completed generated SQLite CRUD and query execution through typed collection tables.
- Reduced MDBX unindexed batch insert work.
- Updated the development generator to `^0.5.5`.

## 0.5.6

- Optimized typed SQLite `getAll` with a reusable statement and transactional cursor.
- Added direct native field reads and removed the generated SQLite generic-document fallback.

## 0.5.5

- Registered SQLite schemas and initialized tables atomically during open.
- Tuned SQLite memory mapping and routed typed `putAll` into collection tables.

## 0.5.4

- Preserved typed IDs through generated getters and external collection keys.
- Reduced batch-write, query-update, filter, and sort overhead.
- Updated the development generator to `^0.5.4` and native ABI to 29.

## 0.5.3

- Fixed MDBX compact-document updates, ID sorting, and fallback hydration using collection-key IDs.

## 0.5.2

- Improved MDBX typed inserts, streaming reads, queries, and string-list hydration.
- Reduced boolean-query and watcher bookkeeping overhead.
- Updated annotations to 0.5.2 and native ABI to 28.

## 0.5.1

- Aligned with `cindel_flutter_libs` 0.5.1 and its regenerated native binaries.

## 0.5.0

- Optimized MDBX reads, writes, deletes, filters, sorting, and native query updates.
- Reduced schema, cursor, index, and list serialization overhead; fixed compact string-list decoding.
- Adjusted MDBX geometry/table limits for larger batches and coordinated package dependencies.
- Updated the native ABI to 25.

## 0.4.0

- Introduced compact typed binary storage and generated native readers/writers.
- Optimized MDBX batch operations, indexes, queries, and watchers; tuned native builds for speed.
- Updated MDBX storage to `mdbx-v6`, typed documents to `binary-v2`, and native ABI to 23.
- Removed the legacy native benchmark module.

## 0.3.4

- Replaced native projection, aggregate, and SQLite list-index JSON payloads with binary encoding.
- Removed default-runtime JSON decoding from these paths; updated native ABI to 17.

## 0.3.3

- Connected native change sets to watchers for immediate local notifications, retaining external-change polling.
- Updated the native ABI to 16.

## 0.3.2

- Added native MDBX query plans for supported reads, counts, deletes, projections, and aggregates.
- Retained the public query API and SQLite fallback; updated native ABI to 15.

## 0.3.1

- Replaced schema and reverse-index JSON metadata with versioned binary encoding.
- Rejected legacy JSON, unsupported versions, and corrupt metadata; updated native ABI to 14.

## 0.3.0

- Replaced manual-document JSON storage and batch-read payloads with binary encoding.
- Retained typed-model compatibility and the public API; updated native ABI to 13.

## 0.2.18

- Replaced native filter JSON payloads with binary encoding, preserving filter behavior.
- Updated the native ABI to 12.

## 0.2.17

- Added binary index and indexed-write payloads, including binary hash-index keys.
- Removed the obsolete MDBX benchmark backend; updated native ABI to 11.

## 0.2.16

- Cached MDBX schemas to reduce read overhead and expanded read benchmarks and typed-storage coverage.

## 0.2.15

- Replaced ID-list and generated batch-write JSON payloads with binary encoding.
- Updated the native ABI to 10 without changing the public API.

## 0.2.14

- Added the shared Dart/Rust binary codec and malformed-payload tests, without changing runtime storage or ABI.

## 0.2.13

- Added property aggregates with native MDBX execution and SQLite fallback.
- Added Linux platform metadata and hardened the MDBX release path.
- Updated the native ABI to 9.

## 0.2.12

- Adopted MDBX per-collection document tables and per-index tables, preserving transactions and index support.
- Added local watcher change sets and skipped unnecessary watcher reads.

## 0.2.11

- Reduced allocations and reused buffers in MDBX scans, statistics, and batch reads.

## 0.2.10

- Optimized MDBX auto-increment allocation with shared counters.
- Fixed explicit SQLite backend selection.

## 0.2.9

- Added composite-index equality and primitive-list multi-entry indexes.
- Updated annotations to 0.2.1 and the development generator to 0.2.3.

## 0.2.8

- Added initial MDBX native planning for counts, simple windowed queries, and field projections.
- Updated the native ABI to 8.

## 0.2.7

- Added native MDBX filtering for supported generated queries, retaining Dart fallbacks.
- Updated the native ABI to 7.

## 0.2.6

- Added generated binary MDBX reads/writes; SQLite retained its JSON path.
- Updated the development generator to 0.2.2 and native ABI to 6.

## 0.2.5

- Adopted strict schema-backed MDBX binary storage and made MDBX the default native build/backend.
- Removed the public migration callback and dry-run APIs while stabilizing storage.
- Updated the native ABI to 5.

## 0.2.4

- Added internal storage-version metadata and verification without changing the public API or storage behavior.

## 0.2.3

- Added an internal binary-document prototype and tests without changing production storage or the public API.

## 0.2.2

- Added an experimental MDBX layout and comparative benchmarks without changing production storage.

## 0.2.1

- Added an internal MDBX index abstraction and updated the development generator to 0.2.1.

## 0.2.0

- Coordinated the 0.2.0 package dependencies and updated backend/platform documentation.

## 0.1.18

- Made MDBX the default backend, retaining explicit SQLite selection.

## 0.1.17

- Prepared the pub.dev preview with hosted dependencies, documentation, and Android/Windows prebuilts.
- Added optional MDBX support and public backend selection; SQLite remained the default.
- Added MDBX storage, transaction, and read-your-writes support with shared backend tests and benchmarks.

## 0.1.16

- Added `putMany` as an alias for manual and typed atomic bulk writes.

## 0.1.15

- Added pub.dev metadata and introductory package documentation.

## 0.1.14

- Optimized native batch reads and regenerated Windows/Android binaries for ABI 4.
