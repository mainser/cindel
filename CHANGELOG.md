# Changelog

All notable Cindel workspace changes will be documented here.

Cindel is pre-1.0.0, so breaking API and packaging changes can still happen
while the core design settles.

## 0.4.1

- Cached native function resolution across Cindel database openings.
- Cached generated native field layouts for typed MDBX reads and writes.
- Reduced MDBX query-plan `filter + sort` overhead by keeping sorted query
  documents in borrowed native storage form longer and specializing compact
  string sort keys.
- Added native query-plan updates for compact MDBX binary documents, matching
  Isar-style property updates without Dart object hydration.
- Allowed generated schemas to hydrate immutable explicit-id collection models
  through constructor parameters.
- Fixed geometry and table count settings.
- Raised the MDBX default map limit to support large batch updates and deletes
  without forcing application-level chunking.
- Skipped MDBX index rewrites when schema-backed binary updates leave derived
  index entries unchanged.
- Skipped MDBX index derivation during schema-backed batch deletes when the
  collection schema declares no indexes.
- Reused MDBX cursors while cleaning indexes during schema-backed batch deletes.
- Reused MDBX document cursors during native batch writes.
- Reduced schema binary document encode overhead by avoiding per-dynamic-field
  header allocations.
- Reduced compact binary string index preparation by reading string payloads
  directly instead of materializing and cloning intermediate values.
- Reused prepared MDBX index cursors during schema-backed batch writes.
- Deleted schema-backed MDBX index entries through positioned cursors during
  batch updates.
- Reduced native batch writer reallocations by reusing observed document
  capacity for subsequent documents.

## 0.4.0

- Removed the legacy native benchmark module and optional `benchmarks` Cargo
  feature; local backend experiments now live outside committed package
  sources.
- Aligned the MDBX open profile with Isar's native engine by using a
  `cindel.mdbx` no-subdir database file, `NoMetaSync`, coalescing, 1 MiB
  minimum map size, 128 MiB default maximum map size, 5 MiB growth steps, and
  20 MiB shrink threshold.
- Changed the MDBX default table limit from 2048 to 512.
- Removed `MDBX_ACCEDE` from the default MDBX open flags.
- Shortened MDBX document table names and marked the storage layout as
  `mdbx-v4`.
- Added schema-specific typed binary document storage aligned to Isar's
  static/dynamic layout.
- Marked generated typed document storage as `binary-v2`.
- Compacted MDBX index table names and table-local index keys, marking the
  storage layout as `mdbx-v5`.
- Removed MDBX reverse-index metadata writes from the schema-backed binary
  document path, marking the storage layout as `mdbx-v6`.
- Optimized MDBX indexed batch writes by preparing document and index tables
  once per native `putAll`.
- Aligned native schema registration with generated binary document field
  slots.
- Added native compact-document writer and reader handles for Isar-like FFI
  typed paths.
- Reworked the native compact-document writer to use a single object buffer
  and static null template.
- Added an MDBX fast path for no-schema/no-index batch document writes.
- Added generated id getters for typed schemas and preserved generated field
  order in native schema registration.
- Added generated native typed writer and reader serializers for supported
  schema fields.
- Streamed schema-backed indexed native `putAll` without prepared document
  batches.
- Optimized compact-document index iteration for typed MDBX writes.
- Reduced native writer string marshaling overhead for large repeated strings.
- Reduced native index extraction reparsing for schema-backed binary documents.
- Skipped native change-set id tracking for generated writes when no watchers
  are registered.
- Treated generated native-writer documents as trusted schema documents during
  MDBX typed batch writes.
- Optimized ASCII word-index extraction for generated binary documents.
- Replaced per-entry MDBX index table hash lookups with prepared table lookup.
- Reused MDBX index key buffers during generated typed batch writes.
- Added native query-plan document readers for generated typed `findAll`
  results.
- Added ASCII string reads and native repeated-large-string interning to the
  generated document reader.
- Skipped redundant query-plan presence checks during generated typed
  materialization.
- Added generated direct binary document hydration without intermediate field
  lists.
- Optimized lazy collection and query watchers to avoid eager snapshot
  hydration.
- Aligned typed query watcher emissions with potential-change notifications.
- Changed the native release profile from size-optimized to speed-optimized.
- Bumped the native ABI to 23.
- Updated all publishable packages and the Todo example to the `0.4.0`
  release line.

## 0.3.4

- Removed the remaining default-runtime `serde_json` dependency from the native
  Rust core.
- Replaced legacy native projection and aggregate JSON result payloads with
  CindelWireV1 `ProjectionRows` and `Scalar` buffers.
- Replaced SQLite stable list-index JSON keys with canonical binary
  `WireIndexValue` bytes encoded as hex.
- Removed Dart runtime `jsonDecode` usage from the FFI projection and aggregate
  paths while keeping public query APIs source-compatible.
- Bumped the native ABI to 17 for the final anti-JSON runtime contract.
- Updated `cindel` and `cindel_flutter_libs` to `0.3.4`.
- Updated the Todo example dependency constraints and build number for the ABI
  17 package line.
- Prepared `cindel_generator` 0.2.4 for pub.dev downgrade analysis by restoring
  analyzer 9 compatibility while keeping analyzer 10+ field-origin handling.

## 0.3.3

- Added CindelWireV1 native watcher change-set payloads carrying collection
  name, post-commit revision, and affected document ids.
- Exposed committed SQLite and MDBX change sets through FFI so Dart watchers
  can wake from native metadata and skip unrelated local document refreshes.
- Kept `pollInterval` as the compatibility fallback for writes observed from
  other database handles.
- Added Dart and Rust change-set wire fixture coverage plus watcher tests for
  compact `putAll` and delete id reporting.
- Documented the isolate-pool ownership boundaries for future async execution.
- Bumped the native ABI to 16 for the binary watcher change-set contract.
- Updated `cindel` and `cindel_flutter_libs` to `0.3.3`.
- Updated the Todo example dependency constraints and build number for the ABI
  16 package line.

## 0.3.2

- Added a CindelWireV1 native query plan payload for common MDBX query
  execution paths.
- Moved MDBX binary-document `findAll`, `count`, `deleteFirst`, `deleteAll`,
  single-field projections, and property aggregates onto native plan execution
  when the query shape is supported.
- Expanded native planning beyond the old id-only fast path so sort, distinct,
  offset, and limit can execute before Dart object hydration.
- Kept SQLite on the existing compatibility fallback path with the same public
  Dart query builder API.
- Added Dart and Rust query-plan wire fixture coverage and a backend test for
  native filter/sort/distinct/window/projection/aggregate/delete behavior.
- Bumped the native ABI to 15 for the binary native query plan contract.
- Updated `cindel` and `cindel_flutter_libs` to `0.3.2`.
- Updated the Todo example dependency constraints and build number for the ABI
  15 package line.

## 0.3.1

- Replaced schema registration JSON with the CindelWireV1 binary schema
  manifest sent across FFI.
- Replaced SQLite and MDBX `schema_collections` JSON records with explicitly
  versioned binary schema metadata.
- Replaced MDBX reverse document-index JSON metadata with CindelWireV1 binary
  `IndexEntryList` records.
- Added fail-closed rejection for JSON-era preview schema and reverse-index
  metadata, future schema metadata versions, and corrupt binary metadata.
- Added explicit schema metadata format storage metadata and aligned SQLite and
  MDBX document metadata on binary storage.
- Bumped the native ABI to 14 for the binary schema metadata contract.
- Updated `cindel` and `cindel_flutter_libs` to `0.3.1`.
- Updated the Todo example dependency constraints and build number for the ABI
  14 package line.

## 0.3.0

- Replaced manual `CindelDocument` JSON runtime storage with
  GenericDocumentV1 binary payloads for `put`, `get`, `getAll`, `queryAll`,
  and id-based hydration.
- Switched `getMany` over FFI from a JSON document array to the binary
  document-batch payload, while preserving generated typed binary documents.
- MDBX now stores manual GenericDocumentV1 bytes and generated typed binary
  bytes directly; SQLite stores manual GenericDocumentV1 bytes as BLOB data.
- Removed the native manual-document JSON conversion helpers from the MDBX
  write/read path.
- Bumped the native ABI to 13 and regenerated Windows, Android, and Linux
  prebuilt native libraries.
- Measured a local 5000-document, 500-repeat performance run: MDBX now measured
  48.85 ms for manual `get`, 12.66 ms for `getAll`, and 11.33 ms for indexed
  equality on that machine.
- Updated `cindel` and `cindel_flutter_libs` to `0.3.0`.

## 0.2.18

- Completed JSON-04 by moving native query filters from JSON envelopes to
  CindelWireV1 binary filter AST payloads.
- Added Dart and Rust filter AST codecs with byte-for-byte fixture coverage and
  deterministic malformed-payload rejection.
- Replaced `NativeFilter::from_json` with binary filter decoding while
  preserving existing equality, comparison, contains, startsWith, endsWith,
  all, any, not, and null behavior.
- Bumped the native ABI to 12 for the binary filter contract.
- Regenerated Windows, Android, and Linux prebuilt native libraries for ABI 12.
- Updated `cindel` and `cindel_flutter_libs` to `0.2.18`.

## 0.2.17

- Completed JSON-03 by moving indexed write metadata from JSON envelopes to
  CindelWireV1 binary payloads for `putIndexed`, `putManyIndexed`, indexed
  equality/range values, and unique-index checks.
- Added a CindelWireV1 indexed document write batch codec with byte-for-byte
  Dart and Rust fixture tests.
- Replaced stable hash-index hashing over JSON strings with hashing over the
  canonical binary index-value bytes shared by Dart and Rust.
- Removed the obsolete Rust-only `mdbx-v2-spike` benchmark backend because the
  useful layout work now lives in the real MDBX backend.
- Bumped the native ABI to 11 for the binary index/write contract.
- Updated `cindel` and `cindel_flutter_libs` to `0.2.17`.

## 0.2.16

- Completed the first GET-01 read-path optimization pass for MDBX get-family
  routes.
- Cached MDBX collection schema manifests in memory after schema registration
  so single `get` and `getMany` reads no longer parse schema JSON on every
  lookup.
- Expanded native and Dart benchmarks to split manual `get`, raw stored-byte
  `getStored`, generated binary-document reads, typed `get`, `getAll`,
  size-specific `getMany` batches, query hydration, and read transaction loops.
- Regenerated Windows, Android, and Linux prebuilt native libraries with the
  MDBX read-path optimization. Native ABI remains 10.
- Updated `cindel` and `cindel_flutter_libs` to `0.2.16`.

## 0.2.15

- Moved runtime FFI id-list payloads from JSON arrays to CindelWireV1 binary
  buffers for document id scans, `getMany`, `getManyStored`, `deleteMany`,
  indexed equality/range query results, native filter candidates/results,
  projection candidates, and aggregate candidates.
- Reused CindelWireV1 `DocumentWriteBatch` for generated binary batch writes so
  the stored-document batch path no longer carries a one-off binary format.
- Bumped the native ABI to 10 for the binary id-list contract.
- Regenerated Windows, Android, and Linux prebuilt native libraries for ABI 10.
- Updated `cindel` and `cindel_flutter_libs` to `0.2.15`.
- Updated the Todo example dependency constraints and build number for the ABI
  10 package line.

## 0.2.14

- Added the internal CindelWireV1 binary codec foundation for the anti-JSON
  optimization roadmap.
- Added shared Dart and Rust byte-for-byte fixture tests covering id lists,
  index values, scalar results, document write batches, projection rows, schema
  manifests, and reverse index entry lists.
- Added malformed wire-payload tests for truncation, invalid tags, invalid
  UTF-8, invalid bool bytes, trailing bytes, and unsafe native item counts.
- Documented the JSON-00 baseline and JSON-01 codec foundation in the roadmap,
  backend evaluation notes, and implementation checklist.
- Updated `cindel` to `0.2.14`. `cindel_flutter_libs` remains at `0.2.13`
  because JSON-01 does not change the native ABI or regenerated prebuilt
  binaries.

## 0.2.13

- Added native property aggregates for count, min, max, sum, and average.
- MDBX now executes aggregate property queries over binary documents without
  hydrating full Dart objects when native query planning is available.
- Kept SQLite aggregate behavior compatible through the existing Dart/JSON
  fallback paths.
- Added native aggregate benchmark workloads and bumped the native ABI to 9.
- Declared Linux in package platform metadata and included the Linux runtime
  library in `cindel_flutter_libs` publication archives.
- Completed release hardening for the optimized MDBX storage path with Rust,
  Dart, Flutter, build, prebuilt, benchmark, and pub.dev dry-run validation.
- Updated `cindel` and `cindel_flutter_libs` to `0.2.13`.

## 0.2.12

- Promoted the faster MDBX v2 table layout into the real MDBX backend path.
- MDBX now uses per-collection document tables and per-index duplicate-sorted
  tables while preserving binary documents, explicit transactions, unique
  indexes, composite indexes, multi-entry indexes, and in-memory id counters.
- Added native-backed watcher change sets so local watchers receive changed
  document ids and written documents when available.
- Document and query watchers can now skip safe local reads when high-frequency
  writes do not affect their visible result.
- Kept the Rust-only `mdbx-v2-spike` backend as a temporary benchmark fixture
  behind the explicit `--backend all-with-spike` benchmark option.
- Regenerated Windows, Android, and Linux prebuilt native libraries.
- Updated `cindel` and `cindel_flutter_libs` to `0.2.12`.

## 0.2.11

- Reduced MDBX allocations in id scans, range/equality query scans, collection
  stats, and multi-document reads.
- Reused document-key buffers for MDBX `get_many` paths outside active write
  transactions.
- Kept lower-level MDBX cursor access deferred because the high-level cursor
  API is still sufficient after the allocation cleanup.
- Regenerated Windows, Android, and Linux prebuilt native libraries.
- Updated `cindel` and `cindel_flutter_libs` to `0.2.11`.

## 0.2.10

- Optimized MDBX auto-increment id allocation with shared in-memory counters
  initialized from document primary keys.
- Stopped using MDBX persisted counter table writes for the normal generated
  auto-increment insert path.
- Added benchmark measurements for native id allocation and auto-increment
  indexed writes.
- Fixed explicit SQLite backend opening so it routes through the native backend
  selector instead of the default MDBX open symbol.
- Regenerated Windows, Android, and Linux prebuilt native libraries.
- Updated `cindel` and `cindel_flutter_libs` to `0.2.10`.

## 0.2.9

- Added `CompositeIndex` collection metadata and generated composite equality
  query helpers.
- Added `CindelIndexType.multiEntry` for primitive list membership indexes.
- Added native tuple key encoding for composite indexes and SQLite secondary
  backend compatibility for composite values.
- Regenerated Windows, Android, and Linux prebuilt native libraries.
- Updated `cindel_annotations` to `0.2.1`, `cindel_generator` to `0.2.3`,
  and `cindel` plus `cindel_flutter_libs` to `0.2.9`.

## 0.2.8

- Added a first native query planner path for MDBX binary-document queries.
- Count and simple windowed list queries can now operate on native candidate
  ids before hydrating documents.
- Added native single-field projection over binary document bytes for
  projection queries that do not require Dart-side sort or distinct handling.
- Added FFI bindings for native projection queries and bumped the native ABI
  to 8.
- Regenerated Windows, Android, and Linux prebuilt native libraries for ABI 8.
- Updated `cindel` and `cindel_flutter_libs` to `0.2.8`.

## 0.2.7

- Added a native MDBX filter compiler for generated Cindel predicates over
  binary document bytes.
- Routed generated `filter()` and supported `where().filter()` queries through
  native filtering when MDBX and binary documents are active, while keeping the
  Dart filter path as the SQLite/custom-predicate fallback.
- Added FFI bindings for native filter queries and bumped the native ABI to 7.
- Regenerated Windows, Android, and Linux prebuilt native libraries for ABI 7.
- Updated `cindel` and `cindel_flutter_libs` to `0.2.7`.

## 0.2.6

- Added generated binary serializers for typed Cindel models.
- Added native FFI read paths for raw stored document bytes so typed MDBX reads
  can avoid JSON map decoding.
- Updated typed collection writes and reads to use Cindel binary documents when
  MDBX is the selected backend, while keeping SQLite on the JSON compatibility
  path.
- Kept MDBX transaction queries consistent by deriving staged index entries
  from binary document bytes.
- Bumped the native ABI to 6 for the new stored-byte FFI symbols.
- Regenerated Windows, Android, and Linux prebuilt native libraries for ABI 6.
- Updated `cindel_generator` to `0.2.2`, `cindel` to `0.2.6`, and
  `cindel_flutter_libs` to `0.2.6`.
- Relaxed the generator `analyzer` constraint to keep the Todo example
  compatible with Riverpod while still supporting current pub.dev analyzer
  scoring.

## 0.2.5

- Switched MDBX schema-backed document storage to Cindel's native binary
  document format.
- MDBX now derives index entries from binary document bytes for generated
  schema collections.
- Made schema-backed MDBX writes strict: unknown fields are rejected instead of
  falling back to JSON.
- Removed the public migration callback and dry-run APIs while Cindel remains
  pre-1.0 and the optimized storage format is still settling.
- Made MDBX part of the default native Cargo build while keeping SQLite
  compiled as an explicit secondary backend.
- Moved the native benchmark and experimental MDBX layout prototype behind the
  `benchmarks` Cargo feature so production builds stay smaller.
- Updated the native MDBX default path so the Rust engine opens MDBX by default
  when the native library is compiled with MDBX support.
- Bumped the native ABI to 5 for the migration API cleanup.
- Regenerated Windows, Android, and Linux prebuilt native libraries for ABI 5.
- Updated `cindel_flutter_libs` to `0.2.5` and advertised Linux alongside
  Android and Windows.

## 0.2.4

- Added internal storage metadata for layout and document format versions.
- Added native storage verification helpers for layout, document-format, and
  index metadata.
- Kept the public Dart API, production storage behavior, and native binary
  symbols unchanged.

## 0.2.3

- Added the first native binary document format prototype.
- Documented the planned versioned object layout with field slots, static and
  dynamic sections, null encoding, and maximum object size limits.
- Added native tests proving supported field shapes can round-trip without JSON
  and that a single field can be read by offset without decoding the whole
  document.
- Kept the public Dart API, production storage layout, and native binary
  symbols unchanged.

## 0.2.2

- Added an internal MDBX layout prototype for performance benchmarking.
- Extended the native benchmark so SQLite, the current MDBX layout, and the
  layout prototype can be compared with the same workload.
- Kept the public Dart API, production storage layout, and prebuilt binary
  symbols unchanged.

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
