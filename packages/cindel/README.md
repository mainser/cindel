<h1 align="center">Cindel</h1>

<p align="center">
  <a href="https://pub.dev/packages/cindel">
    <img src="https://img.shields.io/pub/v/cindel?label=pub.dev&labelColor=333940&color=0175C2&logo=dart">
  </a>
  <a href="https://github.com/mainser/cindel/actions/workflows/ci.yml">
    <img src="https://img.shields.io/github/actions/workflow/status/mainser/cindel/ci.yml?branch=main&label=tests&labelColor=333940&logo=github">
  </a>
  <a href="https://app.codecov.io/gh/mainser/cindel">
    <img src="https://img.shields.io/codecov/c/github/mainser/cindel/main?logo=codecov&logoColor=fff&labelColor=333940">
  </a>
</p>

<p align="center">
  <strong>Extremely fast, easy to use, and fully async NoSQL database, built as a Flutter-first local database with generated Dart APIs and a compact Rust native core.</strong>
</p>

<p align="center">
  Typed collections &middot; MDBX by default &middot; SQLite optional &middot; Native binaries for Flutter
</p>

<p align="center">
  <a href="#quickstart">Quickstart</a> &middot;
  <a href="#features">Features</a> &middot;
  <a href="#crud">CRUD</a> &middot;
  <a href="#queries">Queries</a> &middot;
  <a href="#watchers">Watchers</a> &middot;
  <a href="#embedded-objects">Embedded Objects</a> &middot;
  <a href="#native-binaries">Native Binaries</a>
</p>

## Status

Cindel is in active pre-1.0 development. APIs and storage format may still
change before a stable release, so preview database files should be treated as
disposable while the optimized native format settles.

## Features

### Generated Dart API

- Typed collections from regular Dart model classes.
- Freezed classic class and primary factory model support.
- Schema metadata and compatible additive schema version bumps.

### Storage and Runtime

- Rust native core behind Dart FFI.
- MDBX default backend with SQLite as an explicit secondary backend.
- Native auto-increment ids and in-memory databases for tests.
- Bulk writes, reads, updates, and deletes.
- Explicit read and write transactions.

### Querying

- Equality, range, prefix, unique, unique replace, hash, case-insensitive,
  word-token, composite, and primitive-list indexes.
- Filter builders, sorting, pagination, distinct, property projections, and
  property aggregates.

### Reactivity and Models

- Document, collection, object, query, and lazy watchers.
- Embedded objects and embedded object lists.

## Quickstart

### 1. Add dependencies

For Flutter apps, add Cindel plus the native library package:

```yaml
dependencies:
  cindel: ^0.6.3
  cindel_flutter_libs: ^0.6.0

dev_dependencies:
  build_runner: ^2.15.0
  cindel_generator: ^0.6.1
```

Pure Dart projects can depend on `cindel` directly and provide a native library
path with `CINDEL_NATIVE_LIBRARY` when needed.

### 2. Create a collection

```dart
import 'package:cindel/cindel.dart';

part 'user.g.dart';

@Collection(name: 'users')
class User {
  Id dbId = autoIncrement;

  @Index(unique: true)
  late String email;

  @index
  late String name;

  bool active = true;

  DateTime createdAt = DateTime.now().toUtc();
}
```

Use `@Name` when the persisted collection or field name should differ from
the Dart identifier:

```dart
@Name('accounts')
@collection
class Account {
  Id dbId = autoIncrement;

  @Name('user_name')
  @Index(unique: true)
  late String username;
}
```

`replace: true` is optional and defaults to `false`. Use it only when a unique
index should behave as a natural-key upsert and replace an existing conflicting
document:

```dart
@collection
class Account {
  Id dbId = autoIncrement;

  @Index(unique: true, replace: true)
  late String username;
}
```

#### Freezed classic classes

Cindel can also generate schemas for Freezed classic classes. This lets you keep
immutable models while Freezed provides `copyWith`, equality, and hashCode:

Freezed models also need `freezed_annotation` as an app dependency and
`freezed` as a development dependency.

```dart
import 'package:cindel/cindel.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'user.freezed.dart';
part 'user.g.dart';

@freezed
@Collection(name: 'users')
class User with _$User {
  const User({
    required this.dbId,
    required this.email,
    required this.name,
    this.active = true,
  });

  @override
  final Id dbId;

  @override
  @Index(unique: true)
  final String email;

  @override
  final String name;

  @override
  final bool active;
}
```

Cindel also supports the common Freezed primary factory style:

```dart
@freezed
@Collection(name: 'users')
abstract class User with _$User {
  const factory User({
    required Id dbId,
    required String email,
    required String name,
    @Default(true) bool active,
  }) = _User;
}
```

IMPORTANT: Freezed union/sealed multi-constructor models are not supported.

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

final saved = await db.users.get(jhon.dbId);

await db.users.delete(jhon.dbId);
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

final users = await db.users.getAll([jhon.dbId, maria.dbId, 404]);

await db.users.deleteAll([jhon.dbId, maria.dbId]);
```

Only unique indexes with `replace: true` generate natural-key upsert helpers.
The generated `putBy...` method reuses an existing id for the indexed value
instead of requiring a manual query first:

```dart
final updated = User()
  ..email = 'jhon@example.com'
  ..name = 'Jhon Updated';

await db.users.putByEmail(updated);
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

final maxId = await db.users.all().dbIdProperty().max();
```

List fields expose Isar-style element and length helpers:

```dart
final flutterUsers = await db.users
    .filter()
    .tagsElementEqualTo('flutter')
    .findAll();

final usersWithoutTags = await db.users.filter().tagsIsEmpty().findAll();

final usersWithOneOrTwoTags = await db.users
    .filter()
    .tagsLengthBetween(1, 2)
    .findAll();
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

Use `@Embedded` or `@embedded` for value objects stored inside a parent
collection document. Embedded objects are not root collections; they are
serialized as part of the parent object.

```dart
@Collection(name: 'emails')
class Email {
  Id dbId = autoIncrement;

  String? subject;

  Recipient? sender;

  List<Recipient>? recipients;
}

@Embedded()
class Recipient {
  String? name;
  String? address;
  RecipientMetadata? metadata;
}

@embedded
class RecipientMetadata {
  String? label;
}
```

Generated filters can query fields inside a single embedded object, including
nested embedded objects:

```dart
final messages = await db.emails
    .filter()
    .sender((recipient) => recipient.addressEqualTo('ada@example.com'))
    .findAll();

final leadMessages = await db.emails
    .filter()
    .sender((recipient) {
      return recipient.metadata((metadata) {
        return metadata.labelEqualTo('lead');
      });
    })
    .findAll();

final maryMessages = await db.emails
    .filter()
    .recipientsElement((recipient) {
      return recipient.addressEqualTo('mary@example.com');
    })
    .findAll();

final secondaryMessages = await db.emails
    .filter()
    .recipientsElement((recipient) {
      return recipient.metadata((metadata) {
        return metadata.labelEqualTo('secondary');
      });
    })
    .findAll();
```

Embedded object fields and embedded object lists can be stored through the
native typed document path. The generated writer uses native object/list hooks,
and the generated reader hydrates embedded objects without requiring a manual
JSON round-trip.

Generated helpers support equality for the whole embedded value and element
equality for embedded lists. Nested field filter helpers are generated for
single embedded object fields and for elements inside embedded object lists.

Embedded indexes are not supported. Put `@Index` on root collection fields, not
inside `@Embedded` classes.

## Supported Platforms

The current package line ships prebuilt Flutter libraries for Android, iOS,
Linux, macOS, and Windows through `cindel_flutter_libs`.

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

## Benchmarks

Benchmarks are a rough signal rather than an absolute performance guarantee,
but they are useful for tracking whether changes move Cindel in the right
direction. The charts below compare the current app-style benchmark in both
small and larger payload modes.

### Small Payloads

`big=false`

<img src="https://raw.githubusercontent.com/mainser/cindel/main/.github/assets/benchmarks.png" alt="Cindel benchmark chart for small payloads"/>

### Larger Payloads

`big=true`

<img src="https://raw.githubusercontent.com/mainser/cindel/main/.github/assets/benchmarks-big.png" alt="Cindel benchmark chart for larger payloads"/>

If you want to inspect more benchmark cases or check how Cindel performs on
your device, you can run the
[benchmarks](https://github.com/mainser/cindel_benchmark) yourself.

## License

Cindel is licensed under the Apache License, Version 2.0. See the repository
license file for details.
