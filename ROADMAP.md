# Cindel Roadmap

Cindel is an experimental Flutter-first local database library with a Dart API,
generated schemas, a Rust native core, and a narrow FFI bridge.

This roadmap tracks what has been validated so far and the next areas to build
or explore. Cindel grows deliberately in small, testable slices so each public
API, native feature, and binary distribution change can be validated before the
next layer is added.

## Validated

- [x] Monorepo scaffold with Dart workspace packages.
- [x] Public package split:
  - `packages/cindel`
  - `packages/cindel_annotations`
  - `packages/cindel_flutter_libs`
  - `packages/cindel_generator`
- [x] Dart to Rust FFI bootstrap.
- [x] Rust native core compilation on Windows.
- [x] SQLite storage backend through `rusqlite`.
- [x] Document persistence by collection and id.
- [x] Public manual Dart API:
  - `Cindel.open`
  - `Cindel.openInMemory`
  - `CindelDatabase.put`
  - `CindelDatabase.get`
  - `CindelDatabase.delete`
- [x] Input validation and closed-database errors.
- [x] Generated collection schemas and serializers.
- [x] Schema type expansion:
  - `DateTime`,
  - `Duration`,
  - primitive lists,
  - nullable fields,
  - enum persistence by name, ordinal, and custom value,
  - ignored transient fields.
- [x] Embedded object persistence:
  - single embedded value objects,
  - lists of embedded value objects,
  - nested embedded value objects,
  - property projection decoding for embedded fields.
- [x] Simple index entries generated from schema metadata.
- [x] Equality queries over indexed fields.
- [x] Inclusive range queries over indexed fields.
- [x] Generated query builders for indexed equality, string prefix, and range
  queries.
- [x] Index variants for unique, case-insensitive string, value, and hash
  indexes.
- [x] Full-text search primitives:
  - Unicode-aware word splitting,
  - multi-entry word indexes over string fields,
  - case-insensitive token-prefix queries.
- [x] Query result helpers:
  - `findAll`
  - `findFirst`
  - `count`
- [x] Native auto-increment id allocation.
- [x] Generated typed writes assign native ids for `autoIncrement`.
- [x] Atomic native batch writes and deletes.
- [x] Manual and typed bulk collection APIs:
  - `putAll`
  - `getAll`
  - `deleteAll`
- [x] Query delete operations:
  - `deleteFirst`
  - `deleteAll`
- [x] Document watchers with Dart streams.
- [x] Collection watchers with Dart streams.
- [x] Native collection revision counters after committed writes.
- [x] Schema metadata registration.
- [x] Schema version persistence.
- [x] In-memory databases for tests and short-lived work.
- [x] Compatible additive schema version updates.
- [x] Rejection of incompatible schema changes.
- [x] Internal Rust benchmark comparing SQLite and MDBX.
- [x] Flutter Todo example application:
  - CRUD UI,
  - watcher-driven live list,
  - indexed exact-title search,
  - indexed prefix-title search,
  - schema version display.
- [x] Android release APK build and physical-device install.
- [x] Linux prebuilt native library generation through WSL.
- [x] Rust native targets declared for:
  - Windows,
  - Linux `x86_64-unknown-linux-gnu`,
  - Android `armeabi-v7a`,
  - Android `arm64-v8a`,
  - Android `x86_64`,
  - iOS physical devices,
  - iOS simulators.
- [x] Apache-2.0 license, contribution guide, and package-style README.

## API Ergonomics

- [x] Typed collection APIs generated from schemas.
  - Example target: `db.users.put(user)`, `db.users.get(id)`.
- [x] Auto-increment id support.
  - Native id allocation.
  - Typed generator support for `autoIncrement`.
- [x] Bulk collection operations.
  - `putAll`
  - `getAll`
  - `deleteAll`
  - query-based deletes.
- [x] Query result operations.
  - `findAll`
  - `findFirst`
  - `count`
  - typed result mapping.
- [ ] Query result existence helper.
  - `exists`
- [x] Property projections.
  - Query a single property without hydrating full objects.
  - Support primitive property projections.
  - Support list property projections.

## Query System

- [x] Generated query builders.
  - Equality helpers for indexed fields.
  - Range helpers for sortable indexed fields.
  - Prefix helpers for indexed strings.
  - Typed query result mapping.
- [x] Filter builder for non-indexed predicates.
  - Boolean fields.
  - Numeric comparisons.
  - String equality, contains, starts-with, ends-with.
  - Null checks when nullable fields are supported.
- [x] Boolean query composition.
  - `and`
  - `or`
  - `not`
  - grouped predicates.
- [ ] Dynamic query modifiers.
  - `optional`
  - `anyOf`
  - `allOf`
- [x] Sorting and pagination.
  - `sortBy`
  - `thenBy`
  - ascending and descending order.
  - `offset`
  - `limit`
- [x] Distinct queries.
  - Distinct by one field.
  - Distinct by multiple fields.
- [ ] Index-assisted distinct.
  - Index-assisted distinct where possible.
- [x] Query builder execution planning.
  - Prefer indexed where clauses before filters.
  - Document execution order clearly.
  - Add tests for index-assisted sorting and filtering.

## Indexes

- [ ] Composite indexes.
- [x] Unique indexes.
- [ ] Multi-entry indexes for list values.
- [x] Case-insensitive string indexes.
- [x] Index type options.
  - Value indexes for range and prefix scans.
  - Hash indexes for compact equality lookups.
- [x] Full-text search primitives.
  - Word splitting helper.
  - Multi-entry word indexes.
  - Case-insensitive prefix search over token indexes.
- [ ] Index lifecycle operations.
  - Rebuild indexes when public migration tooling is added.
  - [x] Validate index definitions during open.
  - Detect stale or incompatible index metadata.

## Schema and Serialization

- [x] Expand supported field types.
  - `bool`
  - `int`
  - `double`
  - `String`
  - `DateTime`
  - `Duration`
  - primitive lists.
- [x] Nullable field support.
- [x] Enum persistence strategies.
  - by name,
  - by ordinal,
  - by custom value.
- [x] Ignored or transient fields.
  - Annotation-level ignore.
- [ ] Collection-level ignore list.
- [x] Embedded objects.
  - Single embedded value.
  - Lists of embedded values.
  - Nested serialization and deserialization.
- [ ] Embedded object filters.
  - Generated filter builders for embedded fields.
- [ ] Schema diagnostics.
  - Better generator errors for unsupported types.
  - Clear errors for missing ids, duplicate ids, and invalid indexes.

## Transactions and Consistency

- [x] Transaction API.
  - Explicit read transactions.
  - Explicit write transactions.
  - Atomic multi-document writes.
  - Clear rollback semantics.
- [ ] Enforce write operations inside write transactions for typed APIs.
- [x] Consistent read snapshots inside read transactions.
- [x] Transaction-aware watcher notifications.
  - Notify after commit only.
  - Avoid emissions for rolled-back writes.
- [ ] Concurrency model.
  - Define allowed parallel reads.
  - Define write serialization rules.
  - Document isolate/thread expectations.

## Watchers and Reactivity

- [x] Query watchers.
  - Watch an indexed query result.
  - Emit only when the query result changes.
- [x] Lazy watchers.
  - Object lazy watcher.
  - Collection lazy watcher.
  - Query lazy watcher.
- [x] `fireImmediately` option for all watcher types.
- [x] Typed object watchers.
  - Watch one generated object by id.
  - Emit `null` when deleted.
- [x] Watcher efficiency.
  - Revision-based collection invalidation.
  - Query result comparison.
  - Tests for unchanged query results.

## Schema Evolution

- [x] Schema metadata persistence.
- [x] Compatible additive schema version updates.
- [x] Rejection of unsafe type, id, and index option changes.
- [ ] Public migration tooling after the optimized storage format stabilizes.
  - Explicit user-triggered data migration.
  - Field and collection rename support.
  - Index rebuild support.
  - Backup, rollback, and verification guidance.
- [ ] Enum migration safeguards.

## Relationships

- [ ] Embedded objects first, as the preferred relationship model.
- [ ] Link prototype after embedded objects are stable.
  - One-to-one links.
  - One-to-many links.
  - Many-to-many links.
- [ ] Backlink metadata.
- [ ] Lazy link loading.
- [ ] Link persistence inside transactions.

## Platforms and Native Assets

- [ ] Prebuilt native binary distribution.
  - [x] Add the `cindel_flutter_libs` Flutter plugin package.
  - [x] Package Android `.so` files under `jniLibs` for supported ABIs.
  - [ ] Package iOS native output as a vendored `.xcframework`.
  - [x] Package the Windows native library through platform plugin bundling.
  - [ ] Package the macOS native library through platform plugin bundling.
  - [x] Package the Linux native library through platform plugin bundling.
  - [x] Update Dart native loading so Flutter app consumers do not need
    Rust/Cargo when bundled binaries are available.
  - [x] Keep the Rust hook path available for Cindel core development.
- [ ] Validate iOS build on macOS with Xcode.
- [ ] Validate iOS install on a physical device.
- [x] Validate Android release build on a repeatable local script.
- [x] Validate Windows desktop example build.
- [ ] Add macOS desktop target once native linking is understood.
- [x] Add Linux native library output for desktop consumers.
- [x] Document Rust, NDK, Xcode, and signing requirements for maintainers.
- [x] Document consumer build requirements without Rust/Cargo after prebuilt
  binaries are available.
- [ ] Keep web out of scope until the native MVP is stable.

## Backend Exploration

- [x] Prototype `libmdbx` behind the existing `StorageEngine` trait.
- [x] Compare SQLite and MDBX with the same benchmark workload.
- [x] Evaluate Windows native asset build reliability for MDBX.
- [x] Evaluate binary size and compile-time cost for Windows and Android
  prebuilt binaries.
- [x] Design backend-agnostic storage layout for:
  - documents,
  - index entries,
  - schema metadata,
  - collection revision counters.
- [x] Keep the public Dart API independent of backend details.
- [x] Make MDBX the default backend while keeping SQLite explicitly
  selectable.
- [ ] Add explicit migration/export tooling only when a public database format
  needs preservation before 1.0.

## Performance Roadmap

Cindel's next performance direction is to keep the public Dart API stable while
moving expensive JSON, allocation, filtering, and query-planning work into the
native MDBX path. These stages come from the internal Isar-inspired research,
but Cindel will continue using Dart FFI rather than recreating Isar's older
custom bridge.

Guiding rules:

- Benchmark before and after every performance stage.
- Optimize MDBX first while keeping SQLite as the correctness fallback.
- Keep storage versions explicit. During the pre-release performance work,
  MDBX can move forward without legacy-data migration because there are no
  external production users yet.
- Defer web, compaction, encryption, and broad platform extras until the core
  native performance path is mature.

- [x] PERF-01: Benchmark and profiling baseline.
  - Separate Dart encode/decode, FFI, native storage, native index query, and
    Dart query-processing costs.
  - Produce JSON output and local HTML visualization for SQLite vs MDBX.
  - Keep the benchmark reusable after every later stage.
- [x] PERF-02: Native index abstraction boundary.
  - Move MDBX index key creation, unique checks, insert/delete, clear, and
    accounting into a dedicated native abstraction.
  - Keep behavior unchanged while making later layout changes safer.
- [x] PERF-03: MDBX layout v2 spike.
  - Prototype per-collection and per-index MDBX databases.
  - Compare the current global-table layout against the v2 layout for writes,
    reads, indexed queries, deletes, and database size.
- [x] PERF-04: Versioned binary document format design.
  - Design a generated binary object format with field offsets, null encoding,
    dynamic sections, and support for current Cindel field types.
  - Prove one-field reads without full document decode.
- [x] PERF-05: Storage version metadata and verification.
  - Add layout/document format metadata and storage verification helpers.
  - Defer public migration/dry-run APIs until the optimized format is closer
    to 1.0.
- [x] PERF-06: Binary document storage behind MDBX.
  - Store generated typed models as binary documents.
  - Derive index entries from native binary document bytes.
  - Reject unknown schema-backed fields instead of carrying JSON fallback
    behavior into the optimized path.
  - Keep MDBX in the default native build while SQLite remains selectable.
- [ ] PERF-07: Dart FFI typed writer and reader handles.
  - Add native writer/reader handles and generated FFI calls for typed fields.
  - Reduce per-document JSON payloads and allocation overhead in `putAll` and
    `getAll`.
- [ ] PERF-08: Native filter compiler.
  - Encode generated filter ASTs through FFI and evaluate predicates over
    native binary object readers.
  - Move common filter operations out of Dart-side map scans.
- [ ] PERF-09: Native query planner and iterators.
  - Execute sort, distinct, offset, limit, count, and projections natively when
    possible.
  - Add plan summaries for debugging and benchmarks.
- [ ] PERF-10: Composite and multi-entry indexes.
  - Add composite index metadata, generated helpers, list multi-entry indexes,
    key-order tests, and index rebuild support.
  - Keep SQLite semantics compatible even if slower.
- [ ] PERF-11: Auto-increment optimization.
  - Initialize counters from the last document id and use in-memory counters
    where transaction semantics allow it.
  - Preserve rollback and explicit-id advancement behavior.
- [ ] PERF-12: Allocation, buffer, and cursor reuse.
  - Reuse transaction buffers, key buffers, and query result buffers.
  - Only move lower-level MDBX cursor access if benchmarks prove it is needed.
- [ ] PERF-13: Native watcher change sets.
  - Track changed collections, document ids, and affected index keys during
    native write transactions.
  - Reduce broad Dart-level watcher polling.
- [ ] PERF-14: Native aggregations.
  - Add native count, min, max, sum, and average paths that avoid full document
    hydration.
- [ ] PERF-15: Public migration tooling for 1.0 stabilization.
  - Add explicit migration/export tooling only when the storage format is close
    enough to 1.0 to preserve external user data.
  - Rebuild indexes and verify counts, schemas, revisions, and selected
    queries.
- [ ] PERF-16: Release hardening for optimized storage.
  - Run full Dart and focused SQLite compatibility suites.
  - Regenerate Windows, Android, and Linux prebuilt binaries if native symbols
    change.
  - Validate Windows, Android, and Linux smoke/prebuilt flows before making the
    optimized path the default.
- [ ] Deferred PERF-17: Compaction and database maintenance.
  - Add database stats and explicit compact operations after the optimized
    layout is stable.
- [ ] Deferred PERF-18: Web backend exploration.
  - Explore web after native desktop/mobile performance is mature.
- [ ] Deferred PERF-19: Encryption.
  - Evaluate encryption strategy and performance impact after storage design is
    stable.

## Errors, Diagnostics, and Tooling

- [ ] Better native error reporting.
  - Error codes across FFI.
  - Human-readable native messages in Dart exceptions.
- [ ] Public exception taxonomy.
  - validation errors,
  - schema errors,
  - transaction errors,
  - native storage errors.
- [ ] Debug logging hooks.
- [ ] Inspector or developer tooling prototype.
- [ ] Documentation for generated schemas and current MVP limits.
- [x] Package publishing preparation for the `0.2.0` line.
  - Per-package pub.dev metadata.
  - Changelogs.
  - Package-level README and LICENSE files.
  - Hosted dependency constraints for publishable packages.
- [ ] `dart pub publish --dry-run` validation for every publishable package.
- [ ] Pub score polish after pub.dev re-analysis.

## Quality Goals

- [ ] Keep Dart analyzer clean.
- [ ] Keep Rust formatting clean with `cargo fmt --check`.
- [ ] Expand Rust tests for storage semantics and future migration tooling.
- [ ] Expand Dart tests for public API behavior and generated code.
- [ ] Add widget tests for the example app's real user flows.
- [ ] Add Android build smoke test documentation.
- [ ] Keep tests documented with Scenario, Covers, Expected, and
  Arrange/Act/Assert sections.
- [ ] Add benchmark snapshots before major backend changes.
- [ ] Re-enable CI on push when the workflow is stable and useful again.
- [ ] Add CI matrix gradually:
  - Dart analyzer and tests,
  - Rust tests,
  - Android build smoke test,
  - macOS/iOS build smoke test when runner access exists.

## Longer-Term Ideas

- [ ] Isolate-friendly APIs.
- [ ] Encryption at rest.
- [ ] Database compaction.
- [ ] Import and export utilities.
- [ ] Optional web strategy after the native MVP is stable.
- [ ] Backend plugin API if multiple native engines prove useful.

## Current Focus

The current implementation focus is release validation for the `0.2.x` package
line. Cindel now has the typed query pipeline, index variants, word-token
indexes, expanded generated serialization, embedded value-object persistence,
query/lazy watchers, binary MDBX document storage, and MDBX as the default
backend with SQLite as an explicit fallback.

Platform hardening continues in parallel: Windows, Android, and Linux prebuilt
binaries are available. Apple binaries are still pending collaborator machines:
macOS should produce `ios/cindel.xcframework` and
`macos/libcindel_native.dylib`.
