# Changelog

All notable Cindel workspace changes will be documented here.

Cindel is pre-1.0.0, so breaking API and packaging changes can still happen
while the core design settles.

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
