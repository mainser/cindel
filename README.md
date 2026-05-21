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

## Supported Platforms

| Platform | Android | iOS | Web | Linux | Windows | macOS |
| --- | --- | --- | --- | --- | --- | --- |
| Status | Yes | Yes | No | No | Yes | No |

## Features

- Flutter-first Dart API.
- Rust native core hidden behind Dart FFI.
- SQLite storage backend for the MVP.
- Generated collection schemas and serializers.
- Manual document API with `put`, `get`, and `delete`.
- Generated typed collection accessors.
- Simple indexed queries by equality and inclusive range.
- Document and collection watchers with Dart streams.
- In-memory databases for tests and short-lived work.
- Schema version registration and compatible additive migrations.
- Prebuilt native library package for Flutter consumers.
- Benchmark baseline for backend evaluation.
- Future backend candidate: `libmdbx`.

## Packages

- `packages/cindel`: public Dart API, FFI bridge, and native Rust core.
- `packages/cindel_annotations`: annotations and shared public types such as
  `@Collection`, `@index`, `Id`, and `autoIncrement`.
- `packages/cindel_flutter_libs`: prebuilt native libraries for Flutter apps.
- `packages/cindel_generator`: source generator for schemas and serializers.
- `examples/cindel_todo`: Flutter example app using Cindel like a normal
  application dependency.

## Quickstart

Add the packages locally while Cindel is private:

```yaml
dependencies:
  cindel:
    path: packages/cindel
  cindel_flutter_libs:
    path: packages/cindel_flutter_libs

dev_dependencies:
  build_runner: ^2.15.0
  cindel_generator:
    path: packages/cindel_generator
```

`cindel_flutter_libs` is the Flutter-only binary package. App developers should
depend on it so Android, iOS, and desktop builds can use bundled native
libraries without compiling Rust locally. Cindel maintainers can still build the
native asset directly with the `hooks.user_defines.cindel.build_native_assets`
flag in the workspace `pubspec.yaml` when they need to validate the native
assets path.

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

## Opening Databases

Open a persistent database:

```dart
final db = await Cindel.open(
  directory: dir.path,
  schemas: [UserSchema],
);
```

Open an in-memory database for tests or short-lived work:

```dart
final db = await Cindel.openInMemory(
  schemas: [UserSchema],
);
```

In-memory databases are isolated per open handle and are discarded when closed.

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

Generated typed collection accessors are available for models with generated
schemas:

```dart
await db.users.put(user);
final savedUser = await db.users.get(user.id);
await db.users.delete(user.id);
```

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

## Native Binaries

Cindel can load native libraries from a Flutter plugin bundle before falling
back to the local native-assets hook. The hook is off by default for consumers
and can be enabled by maintainers with:

```yaml
hooks:
  user_defines:
    cindel:
      build_native_assets: true
```

Maintainers regenerate the bundled libraries with:

```powershell
.\tool\prebuilt\build_windows.ps1
.\tool\prebuilt\build_android.ps1
```

```sh
./tool/prebuilt/build_apple.sh
./tool/prebuilt/build_linux.sh
```

Set `CINDEL_NATIVE_LIBRARY` to an absolute library path when testing a custom
native build without copying it into `cindel_flutter_libs`.

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
See `CHANGELOG.md` for version history.

## Roadmap

The full public roadmap lives in `ROADMAP.md`.

Validated so far:

- [x] Monorepo scaffold with Dart workspace packages.
- [x] Dart to Rust FFI bootstrap.
- [x] Rust native core compilation on Windows.
- [x] SQLite storage backend through `rusqlite`.
- [x] Document persistence by collection and id.
- [x] Manual Dart API with `put`, `get`, and `delete`.
- [x] Generated collection schemas and serializers.
- [x] Generated typed collection accessors.
- [x] Simple indexes generated from schema metadata.
- [x] Equality queries over indexed fields.
- [x] Inclusive range queries over indexed fields.
- [x] Document and collection watchers with Dart streams.
- [x] Native collection revision counters after committed writes.
- [x] Schema metadata registration and version persistence.
- [x] In-memory database support for tests and short-lived work.
- [x] Compatible additive schema migrations.
- [x] Rejection of incompatible schema changes.
- [x] Internal Rust benchmark baseline for SQLite.
- [x] Apache-2.0 license, contribution guide, and package-style README.

Next areas:

- [x] Typed collection APIs.
- [ ] Prebuilt native binary distribution.
- [ ] Query builders.
- [ ] Transaction API.
- [ ] Auto-increment id support.
- [ ] Query watchers.
- [ ] Explicit migration callbacks.
- [ ] Better native error reporting.
- [ ] `libmdbx` prototype behind the existing storage trait.
- [ ] Example Flutter application.
- [ ] Public package publishing polish.

## License

Cindel is licensed under the Apache License, Version 2.0. See `LICENSE`.
