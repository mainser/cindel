# Cindel Roadmap

Cindel is an experimental Flutter-first local database library with a Dart API,
generated schemas, a Rust native core, and a narrow FFI bridge.

This roadmap tracks what has been validated so far and the next areas to build
or explore.

## Validated

- [x] Monorepo scaffold with Dart workspace packages.
- [x] Public package split:
  - `packages/cindel`
  - `packages/cindel_annotations`
  - `packages/cindel_generator`
- [x] Dart to Rust FFI bootstrap.
- [x] Rust native core compilation on Windows.
- [x] SQLite storage backend through `rusqlite`.
- [x] Document persistence by collection and id.
- [x] Public manual Dart API:
  - `Cindel.open`
  - `CindelDatabase.put`
  - `CindelDatabase.get`
  - `CindelDatabase.delete`
- [x] Input validation and closed-database errors.
- [x] Generated collection schemas and serializers.
- [x] Simple index entries generated from schema metadata.
- [x] Equality queries over indexed fields.
- [x] Inclusive range queries over indexed fields.
- [x] Document watchers with Dart streams.
- [x] Collection watchers with Dart streams.
- [x] Native collection revision counters after committed writes.
- [x] Schema metadata registration.
- [x] Schema version persistence.
- [x] Compatible additive schema migrations.
- [x] Rejection of incompatible schema changes.
- [x] Internal Rust benchmark baseline for SQLite.
- [x] Apache-2.0 license, contribution guide, and package-style README.

## Next Features

- [ ] Typed collection APIs generated from schemas.
  - Example target: `db.users.put(user)`, `db.users.get(id)`.
- [ ] Generated query builders.
  - Equality helpers for indexed fields.
  - Range helpers for sortable indexed fields.
  - Typed query result mapping.
- [ ] Transaction API.
  - Explicit write transactions.
  - Atomic multi-document writes.
  - Clear rollback semantics.
- [ ] Auto-increment id support.
  - Native id allocation.
  - Typed generator support for `autoIncrement`.
- [ ] Query watchers.
  - Watch an indexed query result.
  - Emit only when the query result changes.
- [ ] Migration callbacks.
  - Explicit user-defined migrations.
  - Data backfills for newly added fields.
  - Index rebuild migrations.
- [ ] Better native error reporting.
  - Error codes across FFI.
  - Human-readable native messages in Dart exceptions.
- [ ] Example Flutter application.
  - CRUD UI.
  - Watchers driving UI updates.
  - Indexed search.
- [ ] Documentation for generated schemas and current MVP limits.
- [ ] Package publishing preparation.
  - Per-package pub.dev metadata.
  - Changelogs.
  - Pub score polish.

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

## Quality Goals

- [ ] Keep Dart analyzer clean.
- [ ] Keep Rust formatting clean with `cargo fmt --check`.
- [ ] Expand Rust tests for storage semantics and migrations.
- [ ] Expand Dart tests for public API behavior and generated code.
- [ ] Keep tests documented with Scenario, Covers, Expected, and
  Arrange/Act/Assert sections.
- [ ] Add benchmark snapshots before major backend changes.
- [ ] Re-enable CI on push when the workflow is stable and useful again.

## Longer-Term Ideas

- [ ] Composite indexes.
- [ ] Unique indexes.
- [ ] Multi-entry indexes.
- [ ] Sorting and pagination.
- [ ] Full-text search.
- [ ] Embedded objects.
- [ ] Links or relationships between collections.
- [ ] Isolate-friendly APIs.
- [ ] Inspector or developer tooling.
- [ ] Web strategy after the native MVP is stable.

## Current Focus

The next practical milestone is typed generated collection APIs and query
builders. That would move Cindel from a working manual document database toward
the ergonomic API expected from an Isar-inspired local-first database.
