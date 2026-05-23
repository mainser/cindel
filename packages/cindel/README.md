# cindel

Ultra-fast, lightweight NoSQL local database API for Flutter and Dart apps.
Cindel provides typed collections, generated schemas, indexed queries,
transactions, watchers, and a compact Rust native runtime behind Dart FFI.

## Usage

```yaml
dependencies:
  cindel: ^0.2.0
  cindel_flutter_libs: ^0.2.0

dev_dependencies:
  build_runner: ^2.15.0
  cindel_generator: ^0.2.0
```

Define a collection:

```dart
import 'package:cindel/cindel.dart';

part 'user.g.dart';

@Collection(name: 'users')
class User {
  Id id = autoIncrement;

  @Index(unique: true)
  late String email;

  late String name;
}
```

Generate code:

```sh
dart run build_runner build --delete-conflicting-outputs
```

Open a database:

```dart
final db = await Cindel.open(
  directory: directory.path,
  schemas: [UserSchema],
);
```

For tests and short-lived work:

```dart
final db = await Cindel.openInMemory(schemas: [UserSchema]);
```

MDBX is the default storage backend. SQLite remains available when a caller
needs the older storage layout explicitly:

```dart
final db = await Cindel.open(
  directory: directory.path,
  schemas: [UserSchema],
  backend: CindelStorageBackend.sqlite,
);
```

Existing SQLite database directories are not migrated automatically by the
default switch. Open them with `backend: CindelStorageBackend.sqlite` until an
explicit migration helper exists in a later release.

## Features

- Typed collection CRUD and bulk writes.
- Native auto-increment IDs.
- Indexed equality, range, prefix, hash, case-insensitive, unique, and word
  token queries.
- Filter builders, sorting, pagination, distinct, and primitive projections.
- Explicit read and write transactions.
- Document, collection, object, query, and lazy watchers.
- Embedded objects and embedded object lists.
- Schema versions and compatible additive schema updates.

## Supported Platforms

The current release ships prebuilt native binaries for Android, Windows, and
Linux through `cindel_flutter_libs`.

iOS and macOS support are planned, but they are not advertised as available
until their native binaries are generated and validated.

## Release Status

Cindel is still pre-1.0.0. The `0.2.0` package line is the first normal
release line after the development previews and ships MDBX as the default
backend with SQLite available explicitly.
