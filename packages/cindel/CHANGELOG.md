# Changelog

## 0.4.1

- Prepared native MDBX filters against schema field layouts before scan
  evaluation, reducing repeated field lookup work in unindexed filter queries.
- Aligned native sorted query tie handling with the core comparator path and
  removed typed reader string interning work from generated native hydration.
- Reduced generated typed `getAll` hydration overhead for native list fields by
  reusing reader scratch buffers between parent documents and child lists.
- Fixed schema binary document decoding for compact native string-list payloads.
- Tightened native `List<String>` payloads to use the compact nested list
  layout while keeping backward-compatible reads for the previous marker
  format.
- Added native list readers for generated typed hydration, so
  primitive list fields no longer force query results back through generic Dart
  binary document decoding.
- Reduced unindexed MDBX `filter query` overhead by applying offset/limit while
  iterating unsorted native query plans and evaluating string/list `contains`
  filters directly from compact binary payloads.
- Cached native function resolution across Cindel database openings.
- Registered schemas during MDBX native open so typed opens avoid the extra
  Dart-to-native schema registration round trip.
- Cached generated native field layouts for typed MDBX reads and writes.
- Reduced MDBX query-plan `filter + sort` overhead by keeping sorted query
  documents in borrowed native storage form longer and specializing compact
  string sort keys.
- Reduced MDBX batch delete overhead for compact documents with one simple
  non-unique bool value index by deleting the index entry directly with
  prepared cursors.
- Reused one MDBX document cursor for batched `getAll` reads instead of
  opening a table lookup for every requested id.
- Trusted compact static layout metadata for generated MDBX `getAll` readers,
  matching the native query-plan reader path.
- Added a direct MDBX query-update path for simple non-unique bool value
  indexes, updating compact document bytes in place and moving the index entry
  with positioned cursors.
- Added native query-plan updates for compact MDBX binary documents, enabling
  property updates without Dart object hydration.
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
- Added nested native list writers for generated typed MDBX batch
  inserts, including direct string value-record writing for primitive lists.
- Reduced generated typed MDBX insert overhead for `List<String>` fields by
  storing native string lists with a compact offset table and by sharing the
  native string buffer between parent and list writers.
- Bumped the native ABI to 25.

## 0.4.0

- Removed the legacy native benchmark module and optional `benchmarks` Cargo
  feature from the committed native package sources.
- Aligned the MDBX open profile by storing the
  physical database as `cindel.mdbx` with no-subdir mode, `NoMetaSync`,
  coalescing, 1 MiB minimum map size, 128 MiB default maximum map size, 5 MiB
  growth steps, and 20 MiB shrink threshold.
- Changed the MDBX default table limit from 2048 to 512.
- Removed `MDBX_ACCEDE` from the default MDBX open flags.
- Shortened MDBX document table names and marked the storage layout as
  `mdbx-v4`.
- Added schema-specific typed binary document storage with a compact
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
- Added native compact-document writer and reader handles for generated FFI
  typed paths.
- Reworked the native compact-document writer to use a single object buffer
  and static null template.
- Added an MDBX fast path for no-schema/no-index batch document writes.
- Added generated id getters for typed schemas and preserved generated field
  order in native schema registration.
- Added generated native typed writer and reader serializers for supported
  schema fields.
- Reduced native index extraction reparsing for schema-backed binary documents.
- Streamed schema-backed indexed native `putAll` without prepared document
  batches.
- Optimized compact-document index iteration for typed MDBX writes.
- Reduced native writer string marshaling overhead for large repeated strings.
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

## 0.3.4

- Removed the default-runtime `serde_json` dependency from the native Rust core.
- Replaced legacy native projection and aggregate JSON result payloads with
  CindelWireV1 `ProjectionRows` and `Scalar` buffers.
- Replaced SQLite stable list-index JSON keys with canonical binary
  `WireIndexValue` bytes encoded as hex.
- Removed Dart runtime `jsonDecode` usage from FFI projection and aggregate
  paths while keeping public query APIs source-compatible.
- Bumped the native ABI to 17.

## 0.3.3

- Added CindelWireV1 native watcher change-set payloads for collection name,
  post-commit revision, and affected document ids.
- Wired Dart watchers to committed SQLite and MDBX native change sets so local
  writes can wake subscriptions without first rereading collection revision.
- Kept the public watcher API unchanged and retained `pollInterval` as the
  fallback for external database-handle changes.
- Added change-set codec fixtures in Dart and Rust plus watcher coverage for
  compact batched writes and delete id reporting.
- Bumped the native ABI to 16.

## 0.3.2

- Added CindelWireV1 native query plan payloads for MDBX binary-document
  queries.
- Moved supported `findAll`, `count`, `deleteFirst`, `deleteAll`, property
  projection, and property aggregate query shapes onto native plan execution.
- Let native planning handle filter, sort, distinct, offset, and limit before
  Dart object hydration when no Dart-only source filter is required.
- Kept the public Dart query builder API unchanged and kept SQLite on the
  compatibility fallback path.
- Added query-plan codec fixtures in Dart and Rust plus backend coverage for
  native plan behavior.
- Bumped the native ABI to 15.

## 0.3.1

- Replaced schema registration JSON with CindelWireV1 binary schema manifests.
- Replaced SQLite and MDBX collection schema JSON records with explicitly
  versioned binary schema metadata.
- Replaced MDBX reverse document-index JSON metadata with binary
  `IndexEntryList` records.
- Added fail-closed rejection for JSON-era preview schema metadata, JSON-era
  reverse-index metadata, future schema metadata versions, and corrupt binary
  metadata.
- Bumped the native ABI to 14 while keeping the public Dart API unchanged.

## 0.3.0

- Replaced manual `CindelDocument` JSON runtime storage with
  GenericDocumentV1 binary payloads.
- Switched `getMany` FFI results from JSON arrays to binary document batches.
- Kept generated typed models on the existing typed binary document format,
  with manual reads normalizing typed payloads through generated mappers when
  needed.
- Added GenericDocumentV1 Dart tests for nested values, UTF-8 key ordering, and
  invalid payload rejection.
- Bumped the native ABI to 13 while keeping the public Dart API unchanged.

## 0.2.18

- Replaced native query filter JSON payloads with CindelWireV1 binary filter
  AST buffers.
- Added `WireFilter` codec coverage in Dart and Rust so field/group/not filters
  are tested byte-for-byte across the FFI boundary.
- Preserved current filter semantics for null equality, numeric comparisons,
  string contains/prefix/suffix filters, list contains, object equality, and
  all/any/not groups.
- Bumped the native ABI to 12 while keeping the public Dart API unchanged.

## 0.2.17

- Replaced JSON FFI payloads for index values, index entry lists, and manual
  indexed document write batches with CindelWireV1 binary buffers.
- Added `WireIndexedDocumentWrite` codec coverage in Dart and Rust so indexed
  batch writes are tested byte-for-byte across the FFI boundary.
- Changed hash index canonicalization to hash binary `WireIndexValue` bytes
  instead of JSON strings.
- Removed the obsolete `mdbx-v2-spike` benchmark backend and its dedicated
  storage module now that the real MDBX backend carries the optimized layout.
- Bumped the native ABI to 11 while keeping the public Dart API unchanged.

## 0.2.16

- Optimized MDBX get-family reads by caching collection schema manifests after
  registration, avoiding repeated schema metadata reads and JSON parsing during
  `get` and `getMany` style lookups.
- Expanded the benchmark harness to measure manual `get`, raw stored-byte
  reads, generated binary-document reads, typed `get`, `getAll`, batch-size
  variants, query hydration, and `readTxn` get loops separately.
- Added typed collection coverage confirming MDBX generated writes store the
  Cindel binary document format used by the fast typed read path.
- Kept the public Dart API and native ABI unchanged.

## 0.2.15

- Replaced JSON array id-list FFI payloads with CindelWireV1 binary buffers for
  document ids, `getMany`, `getManyStored`, `deleteMany`, indexed query id
  results, native filter candidate/result ids, projection candidate ids, and
  aggregate candidate ids.
- Reused CindelWireV1 `DocumentWriteBatch` for generated binary batch writes.
- Bumped the native ABI to 10 for the binary id-list contract.
- Kept the public Dart API unchanged; callers still use `getAll`,
  `documentIds`, query builders, projections, aggregates, and deletes the same
  way.

## 0.2.14

- Added the internal CindelWireV1 binary codec foundation shared by Dart and
  Rust.
- Added byte-for-byte Dart and Rust fixture coverage for id lists, index
  values, scalar results, document write batches, projection rows, schema
  manifests, and reverse index entry lists.
- Added malformed-payload validation coverage for truncated buffers, invalid
  tags, invalid UTF-8, invalid bool bytes, trailing bytes, and unsafe native
  item counts.
- Kept the public Dart API, native ABI, runtime storage behavior, and prebuilt
  native binaries unchanged; runtime FFI paths still switch away from JSON in
  the later JSON-02 and JSON-03 stages.

## 0.2.13

- Added `CindelPropertyQuery` aggregate helpers for count, min, max, sum, and
  average.
- MDBX can execute supported property aggregates over native binary documents
  without hydrating full Dart objects.
- Kept SQLite behavior compatible through fallback aggregate evaluation.
- Added FFI bindings for native aggregate queries and bumped the native ABI to
  9.
- Declared Linux in pub.dev platform metadata now that Linux prebuilt
  generation is part of release validation.
- Completed release hardening for the optimized MDBX default storage path.

## 0.2.12

- Promoted the faster MDBX v2 table layout into the real MDBX backend path.
- MDBX now stores documents in per-collection tables and indexes in per-index
  duplicate-sorted tables while preserving the existing public Dart API.
- Kept binary documents, explicit transactions, unique/composite/multi-entry
  indexes, and optimized auto-increment counters on the converged backend.
- Added watcher change sets for local writes, including changed document ids
  and written documents when Dart has them available.
- Document and query watchers can skip safe local reads when a write does not
  affect the watched document or visible query result.
- Left the Rust-only `mdbx-v2-spike` path as a temporary benchmark fixture
  behind the explicit `--backend all-with-spike` option.

## 0.2.11

- Reduced MDBX allocations in id scans, range/equality query scans, collection
  stats, and multi-document reads.
- Reused MDBX document-key buffers for `get_many` paths outside active write
  transactions.
- Kept the existing safe MDBX cursor API; lower-level cursor work remains
  deferred until benchmarks prove it is needed.

## 0.2.10

- Optimized MDBX auto-increment id allocation with shared in-memory counters
  initialized from document primary keys.
- MDBX no longer writes persisted counter rows for the normal generated
  auto-increment insert path.
- Added native benchmark operations for id allocation and auto-increment
  indexed writes.
- Fixed explicit SQLite backend opening so it routes through the native backend
  selector instead of the default MDBX open symbol.

## 0.2.9

- Added collection-level composite index schema metadata and generated equality
  query helpers.
- Added multi-entry primitive list indexes for generated membership queries.
- Added native composite index key encoding and SQLite compatibility handling.
- Updated the annotations dependency to `0.2.1` and the generator dependency to
  `0.2.3`.

## 0.2.8

- Added a first native query planner path for MDBX binary-document queries.
- Count and simple windowed list queries now use native candidate ids before
  document hydration when sort/distinct processing is not required.
- Added native single-field projection over binary document bytes.
- Added FFI bindings for native projection queries and bumped the native ABI to
  8.

## 0.2.7

- Added native MDBX filtering for generated Cindel filter predicates over
  binary document bytes.
- Routed supported generated `filter()` and `where().filter()` queries through
  native filtering on MDBX, with the existing Dart filter path retained for
  SQLite and custom predicates.
- Added FFI bindings for native filter queries and bumped the native ABI to 7.

## 0.2.6

- Added generated binary document callbacks to collection schemas.
- Added MDBX typed collection write and read paths that use Cindel binary
  document bytes instead of JSON map decoding.
- Added FFI bindings for raw stored document reads and bumped the native ABI to
  6.
- Kept SQLite available on the existing JSON document path.
- Updated the development generator dependency constraint to the `0.2.2`
  release line.

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

## 0.2.4

- Added internal storage metadata for layout and document format versions.
- Added native storage verification helpers for layout, document-format, and
  index metadata.
- Kept the public Dart API, production storage behavior, and native binary
  symbols unchanged.

## 0.2.3

- Added an internal native binary document format prototype.
- Documented the planned versioned object layout for future generated
  serializers.
- Added native tests for round-tripping supported field shapes without JSON and
  reading one field by offset without full document decoding.
- Kept the public Dart API, production storage layout, and native binary
  symbols unchanged.

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
