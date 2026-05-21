# Changelog

All notable Cindel workspace changes will be documented here.

Cindel is pre-1.0.0, so breaking API and packaging changes can still happen
while the core design settles.

## 0.1.13 - 2026-05-21

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

## 0.1.12 - 2026-05-21

- Added `fireImmediately` to document, collection, object, and query watchers.
- Added document, collection, object, and query lazy watchers.
- Added typed `CindelQuery.watch` and `CindelQuery.watchLazy`.
- Suppressed watcher emissions when the visible document, collection, or query
  result has not changed.
- Added Dart watcher tests for lazy streams, delayed initial emission, and
  query watchers that ignore writes outside the visible query result.

## 0.1.11 - 2026-05-21

- Added `@Embedded` for generated nested value-object persistence.
- Added generated serialization and deserialization for one embedded object.
- Added generated serialization and deserialization for lists of embedded
  objects.
- Added nested embedded-object helper generation.
- Added embedded object decoding for property projections.
- Expanded schema generation tests to round-trip embedded objects and embedded
  object lists through an in-memory database.

## 0.1.10 - 2026-05-21

- Added generated serialization for `DateTime` and `Duration`.
- Added generated primitive list persistence.
- Added `@ignore` for transient fields.
- Added `@Enumerated` with `CindelEnumType.name`, `ordinal`, and custom
  `valueField` strategies.
- Added generated property decoding for fields stored in encoded form.
- Added indexed query support for generated DateTime, Duration, and enum
  encoded values.
- Expanded schema generation tests to round-trip dates, durations, lists,
  nullable fields, enums, and ignored fields through an in-memory database.

## 0.1.9 - 2026-05-21

- Added `CindelIndexType.words` for simple full-text-style word indexes over
  `String` fields.
- Added `Cindel.splitWords` and `cindelSplitWords` for Unicode-aware word
  tokenization.
- Stored word indexes as multiple native index entries per document.
- Added generated `*WordEqualTo`, `*WordStartsWith`, `*WordsContain`, and
  `*WordsStartWith` helpers for word-indexed fields.
- Added case-insensitive token-prefix search for word indexes.
- Updated the Todo example to use a tokenized title index for prefix search.
- Added Dart and Rust tests for tokenization, word indexes, and word-index
  schema metadata.

## 0.1.8 - 2026-05-21

- Added index variants through `@Index(unique:)`, `@Index(caseSensitive:)`,
  and `@Index(type:)`.
- Added `CindelIndexType.value` and `CindelIndexType.hash`.
- Added generated schema metadata for index uniqueness, case sensitivity, and
  storage type.
- Enforced unique index values for single writes and batch writes.
- Added case-insensitive string equality and prefix queries.
- Added hash index equality lookups and rejected range/prefix planning for hash
  indexes.
- Persisted index option metadata in native schema manifests and rejected
  incompatible index option changes until explicit migrations exist.
- Added Dart and Rust tests for index variants and schema compatibility.

## 0.1.7 - 2026-05-21

- Added typed query sorting with generated `sortBy*`, `sortBy*Desc`,
  `thenBy*`, and `thenBy*Desc` helpers.
- Added query `offset` and `limit` pagination.
- Added `distinctBy` and `distinctByFields` support, plus generated
  `distinctBy*` helpers.
- Added primitive property projections through generated `*Property` helpers
  and dynamic multi-field `properties` projections.
- Added `CindelTypedCollection.all()` to start a query over a whole typed
  collection.
- Documented the full query execution order: where, filter, sort, distinct,
  offset, limit, and projection.
- Added Dart tests for sorting, secondary sorting, pagination, distinct,
  projections, and combined execution order.

## 0.1.6 - 2026-05-21

- Added typed filter builders generated for collection fields.
- Added `CindelQuery.all`, `whereMatches`, and `CindelFilter` predicate
  composition.
- Supported bool equality, numeric comparisons, string equality, contains,
  startsWith, endsWith, and inclusive numeric between filters.
- Supported grouped filter predicates with `CindelFilter.all`, `any`, and
  `not`.
- Documented query execution order: indexed `where` first, then Dart-level
  filters.
- Added Dart tests for full collection filters, where-plus-filter queries,
  string filters, numeric filters, and grouped predicates.

## 0.1.5 - 2026-05-21

- Added native explicit read and write transactions.
- Added public `CindelDatabase.readTxn` and `writeTxn` wrappers.
- Routed manual, typed, bulk, and query-delete writes through active native
  write transactions.
- Rejected writes inside read transactions and nested transactions.
- Deferred watcher notifications until successful transaction commit and
  suppressed rollback emissions.
- Regenerated Windows and Android prebuilt native binaries for the new
  transaction FFI symbols.
- Added Rust and Dart tests for commit, rollback, read transactions, nested
  transaction rejection, id-counter rollback, and transaction-aware watchers.

## 0.1.4 - 2026-05-21

- Added atomic native batch writes and deletes.
- Added manual `CindelDatabase.putAll`, `getAll`, and `deleteAll`.
- Added typed collection `putAll`, `getAll`, and `deleteAll`.
- Added query `deleteFirst` and `deleteAll` operations.
- Regenerated Windows and Android prebuilt native binaries for the new FFI
  symbols.
- Added Rust and Dart tests for bulk writes, query deletes, and rollback
  behavior.

## 0.1.3 - 2026-05-21

- Added typed `CindelQuery<T>` with `findAll`, `findFirst`, and `count`.
- Updated generated collection accessors to emit `where()` helpers for indexed
  fields.
- Added generated indexed equality, string prefix, and inclusive range query
  methods.
- Updated `cindel_todo` search to use the generated query builder instead of
  manual `queryEqual` and `queryRange` calls.
- Added Dart tests for typed equality, prefix, range, first, and count query
  builder behavior.

## 0.1.2 - 2026-05-21

- Added native per-collection auto-increment id allocation.
- Persisted native id counters across reopened databases.
- Advanced native id counters after manual `put` calls to avoid collisions.
- Exposed id allocation through Dart FFI and `CindelDatabase.allocateId`.
- Updated generated typed collection writes to replace `autoIncrement` with a
  native id before persistence.
- Updated `cindel_todo` so new todos use native auto-increment ids instead of
  timestamp-manufactured ids.
- Expanded Rust, Dart, and Todo tests for monotonic allocated ids, reopened
  databases, generated id setters, and in-memory typed writes.

## 0.1.1 - 2026-05-21

- Added `Cindel.openInMemory` for tests and short-lived databases.
- Added SQLite in-memory storage support in the native Rust core.
- Added prebuilt native library loading before native-assets fallback.
- Added `cindel_flutter_libs` as the Flutter prebuilt binary package.
- Added Windows and Android prebuilt native binaries.
- Added maintainer scripts for Windows, Android, Apple platforms, and Linux
  prebuilt binary generation.
- Updated `cindel_todo` to depend on `cindel_flutter_libs`.
- Updated `cindel_todo` tests to use real Cindel in-memory databases.
- Expanded Dart, Flutter, and Rust tests for in-memory databases and Todo
  repository behavior.

## 0.1.0 - 2026-05-21

- Established the first explicit development version baseline.
- Added generated typed collection accessors.
- Added typed collection CRUD and watcher tests.
- Added the Cindel Todo example with CRUD, watchers, indexed title search,
  schema version display, Android build validation, and Windows desktop build
  validation.
- Added public documentation for supported platforms and project roadmap.

## 0.0.1 - 2026-05-19

- Created the initial Cindel workspace.
- Added the Dart API package, annotations package, and generator package.
- Added the Rust native core behind Dart FFI.
- Added SQLite-backed document persistence.
- Added generated schema metadata and serializers.
- Added manual document CRUD APIs.
- Added indexed equality and inclusive range query primitives.
- Added document and collection watchers.
- Added schema metadata registration and compatible additive migration checks.
- Added Rust benchmark baseline and backend evaluation notes.
