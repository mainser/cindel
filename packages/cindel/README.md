# Cindel Database

Fast local database for Flutter and Dart apps, powered by a generated Dart API
and a compact Rust native core.

[Quickstart](#quickstart) |
[Features](#features) |
[CRUD](#crud) |
[Queries](#queries) |
[Watchers](#watchers) |
[Native Binaries](#native-binaries)

> Cindel is a Flutter-first local database with typed collections, generated
> schemas, MDBX storage by default, and SQLite available only when requested.

## Status

Cindel is in active pre-1.0 development. The API and storage format can still
change before a stable release. New projects should treat old preview database
files as disposable while the optimized native format settles.

## Features

- Typed collections generated from regular Dart model classes.
- Rust native core behind Dart FFI.
- MDBX default backend with SQLite as an explicit secondary backend.
- Native auto-increment ids.
- Bulk writes, reads, updates, and deletes.
- Indexed equality, range, prefix, unique, hash, case-insensitive, word-token,
  composite, and primitive-list queries.
- Filter builders, sorting, pagination, distinct, property projections, and
  property aggregates.
- Explicit read and write transactions.
- Document, collection, object, query, and lazy watchers.
- Embedded objects and embedded object lists.
- In-memory databases for tests.
- Schema metadata and compatible additive schema version bumps.

## Quickstart

### 1. Add dependencies

For Flutter apps, add Cindel plus the native library package:

```yaml
dependencies:
  cindel: ^0.5.2
  cindel_flutter_libs: ^0.5.2

dev_dependencies:
  build_runner: ^2.15.0
  cindel_generator: ^0.5.2
```

Pure Dart projects can depend on `cindel` directly and provide a native library
path with `CINDEL_NATIVE_LIBRARY` when needed.

### 2. Create a collection

```dart
import 'package:cindel/cindel.dart';

part 'user.g.dart';

@Collection(name: 'users')
class User {
  Id id = autoIncrement;

  @Index(unique: true)
  late String email;

  @index
  late String name;

  bool active = true;

  DateTime createdAt = DateTime.now().toUtc();
}
```

### 3. Generate code

```sh
dart run build_runner build --delete-conflicting-outputs
```

### 4. Open a database

```dart
final db = await Cindel.open(
  directory: directory.path,
  schemas: [UserSchema],
);
```

MDBX is the default backend. SQLite is available only when requested
explicitly:

```dart
final db = await Cindel.open(
  directory: directory.path,
  schemas: [UserSchema],
  backend: CindelStorageBackend.sqlite,
);
```

For tests and short-lived work:

```dart
final db = await Cindel.openInMemory(schemas: [UserSchema]);
```

## CRUD

Generated collections are available directly from the database handle:

```dart
final jhon = User()
  ..name = 'Jhon Doe'
  ..email = 'jhon@example.com'
  ..active = true;

await db.users.put(jhon);

final saved = await db.users.get(jhon.id);

await db.users.delete(jhon.id);
```

Bulk operations use native batch paths:

```dart
final maria = User()
  ..name = 'Maria Cruz'
  ..email = 'maria@example.com';

final taylor = User()
  ..name = 'Taylor Reed'
  ..email = 'taylor@example.com';

await db.users.putMany([jhon, maria, taylor]);

final users = await db.users.getAll([jhon.id, maria.id, 404]);

await db.users.deleteAll([jhon.id, maria.id]);
```

Use transactions when multiple operations must commit together:

```dart
await db.writeTxn(() async {
  await db.users.put(jhon);
  await db.users.put(maria);
});

final activeUsers = await db.readTxn(() {
  return db.users.filter().activeEqualTo(true).findAll();
});
```

## Queries

Generated query builders start from indexed `where` clauses or collection
filters:

```dart
final jhon = await db.users
    .where()
    .emailEqualTo('jhon@example.com')
    .findFirst();

final activeUsers = await db.users
    .filter()
    .activeEqualTo(true)
    .sortByName()
    .findAll();
```

String indexes get prefix helpers:

```dart
final people = await db.users.where().nameStartsWith('Jh').findAll();
```

Queries support counts, deletes, pagination, distinct values, property
projections, and aggregates:

```dart
final count = await db.users.filter().activeEqualTo(true).count();

final names = await db.users
    .filter()
    .activeEqualTo(true)
    .sortByName()
    .distinctByEmail()
    .nameProperty()
    .findAll();

final maxId = await db.users.all().idProperty().max();
```

The lower-level manual document API remains available:

```dart
await db.put('users', 1, {
  'name': 'Jhon Doe',
  'email': 'jhon@example.com',
  'active': true,
});

final document = await db.get('users', 1);
```

## Watchers

Cindel watchers expose Dart streams for objects, collections, queries, and
manual documents:

```dart
final sub = db.users
    .filter()
    .activeEqualTo(true)
    .sortByName()
    .watch()
    .listen((users) {
      // Rebuild visible state.
    });
```

Lazy watchers emit only an invalidation signal:

```dart
final sub = db.users.watchCollectionLazy().listen((_) {
  // Refresh cached state.
});
```

## Embedded Objects

Use `@Embedded` for value objects stored inside a parent collection document:

```dart
@Collection(name: 'emails')
class Email {
  Id id = autoIncrement;

  String? subject;

  Recipient? sender;
}

@Embedded()
class Recipient {
  String? name;
  String? address;
}
```

## Supported Platforms

The current package line ships prebuilt Flutter libraries for Android, Windows,
and Linux through `cindel_flutter_libs`.

iOS and macOS are planned but are not advertised as supported until their
native binaries are generated and validated.

## Native Binaries

Flutter apps should depend on `cindel_flutter_libs` so the native runtime is
bundled automatically.

When testing a custom local build, set `CINDEL_NATIVE_LIBRARY` to an absolute
path before running Dart tests or tools:

```powershell
$env:CINDEL_NATIVE_LIBRARY = 'D:\path\to\cindel_native.dll'
```

## Unit Tests

Use in-memory databases for fast tests:

```dart
final db = await Cindel.openInMemory(schemas: [UserSchema]);
addTearDown(db.close);
```

## License

Cindel is licensed under the Apache License, Version 2.0. See the repository
license file for details.
