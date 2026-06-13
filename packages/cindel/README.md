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
  <strong>A Flutter-first local database with generated typed Dart APIs, a Rust native core, MDBX by default, SQLite native, and SQLite Web/OPFS.</strong>
</p>

<p align="center">
  Typed collections &middot; Generated queries &middot; Transactions &middot; Watchers &middot; Flutter native and Web
</p>

<p align="center">
  <a href="#quickstart">Quickstart</a> &middot;
  <a href="#models">Models</a> &middot;
  <a href="#opening-a-database">Opening</a> &middot;
  <a href="#crud">CRUD</a> &middot;
  <a href="#queries">Queries</a> &middot;
  <a href="#transactions">Transactions</a> &middot;
  <a href="#watchers">Watchers</a> &middot;
  <a href="#web">Web</a> &middot;
  <a href="#testing">Testing</a>
</p>

## Status

Cindel is pre-1.0. The public direction is a generated typed API: application
code works with typed collections such as `db.users`, and each backend adapts
internally to that same app code.

## Features

- Generated typed collections from Dart model classes.
- MDBX as the default native backend.
- SQLite as an explicit native backend.
- Experimental SQLite Web/OPFS backend for Flutter Web.
- Auto-increment ids.
- Typed CRUD and bulk operations.
- Generated `where()` and `filter()` query helpers.
- Sorting, pagination, distinct, projections, and aggregates.
- Read and write transactions.
- Typed object, collection, query, and lazy watchers.
- Embedded objects and embedded object lists.
- Freezed classic class and primary factory support.

## Quickstart

### 1. Add Dependencies

Flutter apps should depend on `cindel` and `cindel_flutter_libs`:

```yaml
dependencies:
  cindel: ^0.6.4
  cindel_flutter_libs: ^0.6.4

dev_dependencies:
  build_runner: ^2.15.0
  cindel_generator: ^0.6.4
```

Pure Dart tools can depend on `cindel` directly and provide a native library
with `CINDEL_NATIVE_LIBRARY` when needed.

### 2. Define A Model

```dart
import 'package:cindel/cindel.dart';

part 'user.g.dart';

@Collection(name: 'users')
class User {
  Id dbId = autoIncrement;

  @Index(unique: true)
  late String email;

  @Index()
  late String name;

  bool active = true;

  DateTime createdAt = DateTime.now().toUtc();
}
```

### 3. Generate Code

```sh
dart run build_runner build --delete-conflicting-outputs
```

The generator creates the schema, serializers, typed collection getter, and
query helpers.

### 4. Open And Use

```dart
final db = await Cindel.open(
  directory: directory.path,
  schemas: [UserSchema],
);

final user = User()
  ..email = 'ada@example.com'
  ..name = 'Ada Lovelace';

await db.users.put(user);

final saved = await db.users.get(user.dbId);
final activeUsers = await db.users.filter().activeEqualTo(true).findAll();

await db.close();
```

## Models

### Collection Names

Use `@Collection` for root persisted objects:

```dart
@Collection(name: 'accounts')
class Account {
  Id dbId = autoIncrement;

  @Index(unique: true, replace: true)
  late String username;

  String? displayName;
}
```

Use `@Name` when the stored collection or field name should differ from the
Dart name:

```dart
@Name('products')
@collection
class Product {
  Id dbId = autoIncrement;

  @Name('sku_code')
  @Index(unique: true)
  late String sku;
}
```

### Supported Field Shapes

Cindel persists:

- `bool`, `int`, `double`, and `String`
- `DateTime` and `Duration`
- enums
- nullable supported values
- embedded objects
- lists of supported non-list values
- lists of embedded objects

Ignore transient fields with `@ignore`:

```dart
@ignore
String runtimeOnlyLabel = '';
```

### Enums

Enums can be stored by name, ordinal, or a value field:

```dart
enum Plan {
  free('free'),
  pro('pro');

  const Plan(this.code);

  final String code;
}

@collection
class Subscription {
  Id dbId = autoIncrement;

  @Enumerated(CindelEnumType.value, valueField: 'code')
  Plan plan = Plan.free;
}
```

### Freezed

Cindel supports Freezed classic classes and single primary factories:

```dart
import 'package:cindel/cindel.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'product.freezed.dart';
part 'product.g.dart';

@freezed
@Collection(name: 'products')
abstract class Product with _$Product {
  const factory Product({
    required Id dbId,
    @Index(unique: true) required String sku,
    @Index() required String name,
    @Default(true) bool active,
  }) = _Product;
}
```

Freezed union/sealed multi-constructor models are not supported.

## Opening A Database

MDBX is the default backend on native platforms:

```dart
final db = await Cindel.open(
  directory: directory.path,
  schemas: [UserSchema, AccountSchema],
);
```

Select SQLite explicitly when you want the native SQLite backend:

```dart
final db = await Cindel.open(
  directory: directory.path,
  schemas: [UserSchema],
  backend: CindelStorageBackend.sqlite,
);
```

Use an in-memory database for tests:

```dart
final db = await Cindel.openInMemory(schemas: [UserSchema]);
```

## CRUD

Generated collections are available from the database handle:

```dart
final ada = User()
  ..email = 'ada@example.com'
  ..name = 'Ada Lovelace';

await db.users.put(ada);

final saved = await db.users.get(ada.dbId);

await db.users.delete(ada.dbId);
```

Bulk operations preserve input order and return `null` for missing ids:

```dart
await db.users.putAll([ada, grace, linus]);

final users = await db.users.getAll([ada.dbId, 404, grace.dbId]);

await db.users.deleteAll([ada.dbId, grace.dbId]);
```

Unique indexes with `replace: true` generate natural-key upsert helpers:

```dart
@collection
class Account {
  Id dbId = autoIncrement;

  @Index(unique: true, replace: true)
  late String username;
}
```

```dart
final account = Account()..username = 'ada';

await db.accounts.putByUsername(account);
```

If another row already has `username == 'ada'`, the generated helper reuses that
id instead of inserting a duplicate.

## Queries

Use generated `where()` helpers for indexed lookups:

```dart
final ada = await db.users
    .where()
    .emailEqualTo('ada@example.com')
    .findFirst();

final recentUsers = await db.users
    .where()
    .createdAtBetween(start, end)
    .findAll();
```

Use generated `filter()` helpers for general filtering:

```dart
final activeUsers = await db.users
    .filter()
    .activeEqualTo(true)
    .sortByName()
    .findAll();
```

String fields support contains, prefix, and suffix filters:

```dart
final matches = await db.users
    .filter()
    .nameContains('Ada')
    .findAll();
```

List fields expose element and length helpers:

```dart
final flutterUsers = await db.users
    .filter()
    .tagsElementEqualTo('flutter')
    .findAll();

final taggedUsers = await db.users
    .filter()
    .tagsLengthGreaterThan(0)
    .findAll();
```

Compose dynamic filters with `optional`, `anyOf`, and `allOf`:

```dart
final bySearch = await db.users
    .filter()
    .optional(search.isNotEmpty, (q) => q.nameContains(search))
    .findAll();

final byTags = await db.users
    .filter()
    .anyOf(selectedTags, (q, tag) => q.tagsElementEqualTo(tag))
    .findAll();
```

Queries can count, delete, update, sort, paginate, deduplicate, project, and
aggregate:

```dart
final count = await db.users.filter().activeEqualTo(true).count();

final names = await db.users
    .filter()
    .activeEqualTo(true)
    .sortByName()
    .offset(20)
    .limit(10)
    .nameProperty()
    .findAll();

final maxId = await db.users.all().dbIdProperty().max();

final updated = await db.users
    .filter()
    .activeEqualTo(false)
    .updateAll({'active': true});

final deleted = await db.users
    .filter()
    .activeEqualTo(false)
    .deleteAll();
```

## Indexes

Add `@Index` to fields that should be queryable through generated `where()`
helpers or optimized by the backend:

```dart
@collection
class Article {
  Id dbId = autoIncrement;

  @Index()
  late String title;

  @Index(caseSensitive: false)
  late String normalizedTitle;

  @Index(type: CindelIndexType.words, caseSensitive: false)
  late String body;

  @Index(type: CindelIndexType.multiEntry, caseSensitive: false)
  List<String> tags = const [];
}
```

Composite indexes are declared on the collection:

```dart
@Collection(
  name: 'events',
  indexes: [
    CompositeIndex(['accountId', 'createdAt']),
  ],
)
class Event {
  Id dbId = autoIncrement;

  @Index()
  late int accountId;

  @Index()
  late DateTime createdAt;
}
```

## Transactions

Use `writeTxn` when several writes must commit or roll back together:

```dart
await db.writeTxn(() async {
  await db.users.put(ada);
  await db.accounts.put(account);
});
```

Use `readTxn` for a consistent read block:

```dart
final users = await db.readTxn(() {
  return db.users.filter().activeEqualTo(true).findAll();
});
```

If a write transaction throws, Cindel rolls back the pending writes.

## Watchers

Watch one object:

```dart
final sub = db.users.watchObject(ada.dbId).listen((user) {
  // user is null when the object does not exist.
});
```

Watch a collection:

```dart
final sub = db.users.watchCollection().listen((users) {
  // Full typed snapshot.
});
```

Watch a query:

```dart
final sub = db.users
    .filter()
    .activeEqualTo(true)
    .sortByName()
    .watch()
    .listen((users) {
      // Matching typed snapshot.
    });
```

Lazy watchers emit invalidation signals without returning objects:

```dart
final sub = db.users.watchCollectionLazy().listen((_) {
  // Refresh cached state.
});
```

## Embedded Objects

Use `@embedded` for values stored inside a parent collection object:

```dart
@collection
class Email {
  Id dbId = autoIncrement;

  String? subject;

  Recipient? sender;

  List<Recipient>? recipients;
}

@embedded
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

Generated filters can query inside embedded objects:

```dart
final messages = await db.emails
    .filter()
    .sender((recipient) => recipient.addressEqualTo('ada@example.com'))
    .findAll();

final secondary = await db.emails
    .filter()
    .recipientsElement((recipient) {
      return recipient.metadata((metadata) {
        return metadata.labelEqualTo('secondary');
      });
    })
    .findAll();
```

Embedded classes are not root collections. Add indexes to root collection
fields, not inside embedded classes.

## Web

Flutter Web uses the same typed app code:

```dart
final db = await Cindel.open(
  directory: 'app.db',
  schemas: [UserSchema],
);
```

Keep both packages in the app:

```yaml
dependencies:
  cindel: ^0.6.4
  cindel_flutter_libs: ^0.6.4
```

Current Web behavior:

- Web uses SQLite in a Worker with OPFS persistence.
- `Cindel.open(...)` loads the packaged Worker and Wasm assets.
- MDBX is not used in the browser.
- Generated typed CRUD, queries, transactions, and single-tab watchers are the
  supported Web path.
- Web support is experimental and should be validated in the target browser.
- Multi-tab coordination is not part of the current preview.

## Native Binaries

Flutter apps should include `cindel_flutter_libs` so native and Web runtime
assets are bundled automatically.

For custom local native builds, set `CINDEL_NATIVE_LIBRARY` before running Dart
tests or tools:

```powershell
$env:CINDEL_NATIVE_LIBRARY = 'D:\path\to\cindel_native.dll'
```

## Testing

Use `openInMemory` for fast unit tests:

```dart
test('stores users', () async {
  final db = await Cindel.openInMemory(schemas: [UserSchema]);
  addTearDown(db.close);

  final user = User()
    ..email = 'ada@example.com'
    ..name = 'Ada';

  await db.users.put(user);

  expect(await db.users.get(user.dbId), isNotNull);
});
```

## Benchmarks

Benchmarks are a rough signal rather than a performance guarantee. They are
useful for tracking whether changes move Cindel in the right direction.

### Small Payloads

`big=false`

<img src="https://raw.githubusercontent.com/mainser/cindel/main/.github/assets/benchmarks.png" alt="Cindel benchmark chart for small payloads"/>

### Larger Payloads

`big=true`

<img src="https://raw.githubusercontent.com/mainser/cindel/main/.github/assets/benchmarks-big.png" alt="Cindel benchmark chart for larger payloads"/>

## License

Cindel is licensed under the Apache License, Version 2.0. See the repository
license file for details.
