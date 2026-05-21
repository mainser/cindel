# Cindel Roadmap

Cindel is an experimental Flutter-first local database library with a Dart API,
generated schemas, a Rust native core, and a narrow FFI bridge.

This roadmap tracks what has been validated so far and the next areas to build
or explore. It is inspired by Isar's developer experience, but Cindel should
grow deliberately in small, testable slices instead of trying to clone every
feature at once.

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
- [x] In-memory SQLite databases for tests and short-lived work.
- [x] Compatible additive schema migrations.
- [x] Rejection of incompatible schema changes.
- [x] Internal Rust benchmark baseline for SQLite.
- [x] Flutter Todo example application:
  - CRUD UI,
  - watcher-driven live list,
  - indexed exact-title search,
  - indexed prefix-title search,
  - schema version display.
- [x] Android release APK build and physical-device install.
- [x] Rust native targets declared for:
  - Windows,
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
  - Rebuild indexes after migrations.
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

## Migrations and Schema Evolution

- [ ] Migration callbacks.
  - Explicit user-defined migrations.
  - Data backfills for newly added fields.
  - Index rebuild migrations.
- [ ] Field rename support.
- [ ] Collection rename support.
- [ ] Enum migration safeguards.
- [ ] Migration dry-run diagnostics.
- [ ] Versioned migration test fixtures.

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
  - [ ] Package macOS and Linux native libraries through platform plugin
    bundling.
  - [x] Update Dart native loading so Flutter app consumers do not need
    Rust/Cargo when bundled binaries are available.
  - [x] Keep the Rust hook path available for Cindel core development.
- [ ] Validate iOS build on macOS with Xcode.
- [ ] Validate iOS install on a physical device.
- [x] Validate Android release build on a repeatable local script.
- [x] Validate Windows desktop example build.
- [ ] Add macOS desktop target once native linking is understood.
- [ ] Add Linux desktop target once native linking is understood.
- [x] Document Rust, NDK, Xcode, and signing requirements for maintainers.
- [x] Document consumer build requirements without Rust/Cargo after prebuilt
  binaries are available.
- [ ] Keep web out of scope until the native MVP is stable.

## Backend Exploration

- [ ] Prototype `libmdbx` behind the existing `StorageEngine` trait.
- [ ] Compare SQLite and MDBX with the same benchmark workload.
- [ ] Evaluate Windows native asset build reliability for MDBX.
- [ ] Evaluate binary size and compile-time cost.
- [ ] Design backend-agnostic storage layout for:
  - documents,
  - index entries,
  - schema metadata,
  - collection revision counters.
- [ ] Keep the public Dart API independent of backend details.

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
- [ ] Package publishing preparation.
  - Per-package pub.dev metadata.
  - Changelogs.
  - Pub score polish.

## Quality Goals

- [ ] Keep Dart analyzer clean.
- [ ] Keep Rust formatting clean with `cargo fmt --check`.
- [ ] Expand Rust tests for storage semantics and migrations.
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

The next implementation milestone is explicit migration callbacks. Cindel now
has the first complete typed query pipeline plus index variants, word-token
indexes, expanded generated serialization, embedded value-object persistence,
and query/lazy watchers.

Platform hardening continues in parallel: Apple and Linux prebuilt binaries are
still pending collaborator machines. macOS should produce
`ios/cindel.xcframework` and `macos/libcindel_native.dylib`, and Linux should
produce `linux/libcindel_native.so`.
