# Cindel

Cindel is an experimental Flutter-first local database library inspired by the
architecture that makes Isar compelling: a clean Dart API, generated schemas, a
native Rust core, and a narrow FFI bridge.

Cindel is not affiliated with Isar. It is a separate project that explores a
similar local-first developer experience with its own implementation choices.

## Status

Cindel is in early MVP development. It already has a working vertical slice:

```text
Dart API -> FFI -> Rust core -> SQLite storage -> Rust -> FFI -> Dart
```

The API is still experimental and can change before a public release.

## Features

- Flutter-first Dart API.
- Rust native core hidden behind Dart FFI.
- SQLite storage backend for the MVP.
- Generated collection schemas and serializers.
- Manual document API with `put`, `get`, and `delete`.
- Simple indexed queries by equality and inclusive range.
- Document and collection watchers with Dart streams.
- Schema version registration and compatible additive migrations.
- Benchmark baseline for backend evaluation.
- Future backend candidate: `libmdbx`.

## Packages

- `packages/cindel`: public Dart API, FFI bridge, and native Rust core.
- `packages/cindel_annotations`: annotations and shared public types such as
  `@Collection`, `@index`, `Id`, and `autoIncrement`.
- `packages/cindel_generator`: source generator for schemas and serializers.
- `examples/cindel_todo`: placeholder Flutter example app.

## Quickstart

Add the packages locally while Cindel is private:

```yaml
dependencies:
  cindel:
    path: packages/cindel

dev_dependencies:
  build_runner: ^2.15.0
  cindel_generator:
    path: packages/cindel_generator
```

Define a collection:

```dart
import 'package:cindel/cindel.dart';

part 'user.g.dart';

@Collection(name: 'users')
class User {
  Id id = autoIncrement;

  late String name;

  @index
  late String email;

  bool? active;
}
```

Generate schema code:

```powershell
dart run build_runner build
```

Open a database:

```dart
final db = await Cindel.open(
  directory: dir.path,
  schemas: [UserSchema],
);
```

## CRUD

The current MVP exposes a JSON-like manual document API:

```dart
await db.put('users', 1, {
  'id': 1,
  'name': 'Noel',
  'email': 'noel@example.com',
  'active': true,
});

final user = await db.get('users', 1);

await db.delete('users', 1);
```

Typed collection accessors are planned for a later generator phase.

## Queries

Indexed fields can be queried by equality:

```dart
final users = await db.queryEqual(
  'users',
  'email',
  'noel@example.com',
);
```

Range queries are inclusive:

```dart
final users = await db.queryRange(
  'users',
  'email',
  lower: 'a@example.com',
  upper: 'm@example.com',
);
```

## Watchers

Cindel can watch a single document:

```dart
final subscription = db.watchDocument('users', 1).listen((document) {
  // Update UI state.
});
```

Or an entire collection:

```dart
final subscription = db.watchCollection('users').listen((documents) {
  // Update UI state.
});
```

Watchers emit an initial snapshot and then emit again after committed changes.

## Schema Versions and Migrations

When schemas are registered during `Cindel.open`, Cindel stores schema metadata
inside the native database.

```dart
final version = await db.schemaVersion('users');
```

Compatible additive schema changes advance the collection version. Destructive
changes such as removing fields, changing field types, changing the id field, or
changing index status are rejected until explicit migration support is added.

## Benchmarks

Run the SQLite backend benchmark baseline:

```powershell
cargo run --release --manifest-path packages/cindel/native/Cargo.toml --bin cindel_bench -- --documents 10000 --query-repeats 1000
```

The benchmark prints CSV rows for indexed writes, point reads, equality
queries, and range queries.

See `docs/backend_evaluation.md` for the current `libmdbx` evaluation and
backend adoption criteria.

## Development

Install dependencies:

```powershell
dart pub get
```

Validate the workspace:

```powershell
dart format --output=none --set-exit-if-changed .
dart analyze
cargo fmt --manifest-path packages/cindel/native/Cargo.toml --check
cargo test --manifest-path packages/cindel/native/Cargo.toml
dart test packages/cindel/test -r expanded
```

See `CONTRIBUTING.md` for contribution guidelines.

## Roadmap

The detailed roadmap lives in `ROADMAP.md`.

Completed MVP phases:

- Dart to Rust FFI bootstrap.
- SQLite storage.
- Manual Dart database API.
- Schema generation.
- Simple indexes and queries.
- Watchers and streams.
- Schema versioning and compatibility validation.
- Backend benchmark baseline.

Next areas:

- Typed collection APIs and query builders.
- Explicit migration callbacks.
- `libmdbx` prototype behind the existing storage trait.
- Example Flutter application.
- Public package publishing polish.

## License

Cindel is licensed under the Apache License, Version 2.0. See `LICENSE`.
