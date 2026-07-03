# Introduction

Cindel is a local database for Dart and Flutter applications. It is designed
around generated, typed APIs: you define regular Dart model classes, generate
the Cindel schema and collection helpers, open a database, and then work with
typed collections such as `db.users` or `db.products`.

This page introduces the shape of the API and the basic workflow. Later pages
can expand each topic in detail, but this first guide should give you enough
context to understand what Cindel is for and how an application normally uses
it.

## What Cindel Is

Cindel stores application data locally and exposes that data through generated
Dart APIs. Instead of writing raw table statements or passing untyped maps
through most of your application, you model your data with Dart classes and let
the generator create the database-facing code.

A typical Cindel model looks like this:

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
}
```

After code generation, application code can use the generated collection API:

```dart
final user = User()
  ..email = 'ada@example.com'
  ..name = 'Ada Lovelace';

await db.users.put(user);

final saved = await db.users.get(user.dbId);
final activeUsers = await db.users.filter().activeEqualTo(true).findAll();
```

The important idea is that Cindel is used from your application as a typed
database API:

- models describe the data you want to persist,
- generated schemas describe those models to Cindel,
- generated collection getters expose CRUD operations,
- generated query helpers make reads type-aware,
- transactions group related reads and writes,
- watchers let UI code react to local database changes,
- migrations let you move stored data between schema versions,
- sync can connect local writes to an application-provided backend adapter.

Cindel can be used for app data such as users, projects, tasks, products,
orders, settings, cached records, offline-first workflows, and other data that
belongs close to the user interface.

## Current API Status

Cindel is currently pre-1.0. The public direction is the generated typed API:
application code opens a database, registers generated schemas, and works
through typed collections.

That means new application code should normally follow this shape:

```dart
final db = await Cindel.open(
  directory: directory.path,
  schemas: [UserSchema, ProjectSchema],
);

await db.users.put(user);
final projects = await db.projects.all().findAll();
```

The same application-level API is used across supported platforms. Native
Flutter apps can use the default native backend or explicitly select SQLite.
Flutter Web uses the same `Cindel.open` and generated collection APIs, with a
browser-compatible storage runtime.

Because the package is pre-1.0, treat the API as actively evolving. Prefer the
documented generated APIs over low-level helpers unless you are building
tooling, migrations, backups, or other advanced flows that specifically need
them.

## Core Concepts

### Database

A Cindel database is opened with `Cindel.open` for persistent data or
`Cindel.openInMemory` for tests and temporary work.

```dart
final db = await Cindel.open(
  directory: directory.path,
  schemas: [UserSchema],
);
```

The `directory` value identifies where the database lives. On native platforms
it is a filesystem directory. On Web it is the logical browser database name.

Always close the database when the owner of the database is done with it:

```dart
await db.close();
```

Closing is safe to call more than once.

### Models

Models are regular Dart classes annotated with Cindel annotations. A root
persisted type uses `@Collection` or the shorthand `@collection`.

```dart
@collection
class Project {
  Id dbId = autoIncrement;
  late String title;
  bool archived = false;
}
```

Cindel supports common scalar fields such as `bool`, `int`, `double`, `String`,
`DateTime`, and `Duration`, as well as enums, nullable values, embedded
objects, and supported lists.

### Schemas

The generated schema tells Cindel how to store and read a model. For a `User`
collection, the generator creates a schema constant such as `UserSchema`.

You pass schemas when opening the database:

```dart
final db = await Cindel.open(
  directory: directory.path,
  schemas: [UserSchema],
);
```

Register every collection your application needs to use in that database
handle.

### Typed Collections

Generated collection getters are the normal entry point for reads and writes.
For a collection named `users`, application code uses `db.users`.

```dart
await db.users.put(user);

final sameUser = await db.users.get(user.dbId);
final allUsers = await db.users.all().findAll();

await db.users.delete(user.dbId);
```

Collections also support bulk writes and reads:

```dart
await db.users.putAll([ada, grace, linus]);

final users = await db.users.getAll([ada.dbId, grace.dbId]);
```

### Indexes

Indexes are declared on model fields with `@Index`. They allow Cindel to
generate `where()` helpers for common lookup patterns.

```dart
@Collection(name: 'users')
class User {
  Id dbId = autoIncrement;

  @Index(unique: true)
  late String email;

  @Index()
  late String name;
}
```

Generated indexed queries look like this:

```dart
final user = await db.users
    .where()
    .emailEqualTo('ada@example.com')
    .findFirst();
```

Use indexes for fields that are frequently used to find records, enforce
uniqueness, or support ordered/range queries.

### Queries

Cindel queries normally start from `all()`, `where()`, or `filter()`.

Use `all()` when you want to query the whole collection:

```dart
final users = await db.users.all().findAll();
```

Use `where()` for indexed lookups:

```dart
final matches = await db.users
    .where()
    .nameEqualTo('Ada Lovelace')
    .findAll();
```

Use `filter()` for general predicates:

```dart
final activeUsers = await db.users
    .filter()
    .activeEqualTo(true)
    .findAll();
```

Queries can also sort, paginate, return distinct values, project properties,
aggregate values, update matching objects, or delete matching objects.

### Transactions

Transactions group related database work. Use a write transaction when several
writes must succeed or fail together.

```dart
await db.writeTxn(() async {
  await db.users.put(user);
  await db.projects.put(project);
});
```

Use a read transaction when you need a consistent read operation across
multiple queries.

```dart
final result = await db.readTxn(() async {
  final user = await db.users.get(userId);
  final projects = await db.projects.filter().ownerIdEqualTo(userId).findAll();
  return (user: user, projects: projects);
});
```

### Watchers

Watchers let application code listen for database changes. They are useful for
UI screens that should update when local data changes.

```dart
final subscription = db.users.watchCollection().listen((users) {
  // Rebuild UI state from the latest users.
});
```

When a matching write commits, the watcher emits updated data. Application code
should cancel subscriptions when the owner is disposed:

```dart
await subscription.cancel();
```

### Migrations

Migrations move existing stored data from one version of your application data
model to another. A migration plan is passed when opening the database.

```dart
final db = await Cindel.open(
  directory: directory.path,
  schemas: [UserSchema],
  migrationPlan: migrations,
);
```

Use migrations when a stored model changes in a way that needs controlled data
conversion, verification, or import/export logic.

### Sync

Sync is configured when the database opens. It is local-first: application
writes are committed locally, and Cindel can then pass supported local changes
to an application-provided sync adapter.

```dart
final db = await Cindel.open(
  directory: directory.path,
  schemas: [OrderSchema, OrderLineSchema],
  sync: CindelSyncConfig(
    adapter: AppSyncAdapter(serverBaseUri),
    interval: const Duration(seconds: 5),
  ),
);
```

Cindel does not require a specific HTTP API. Your adapter decides how to talk
to your backend and returns Cindel sync result objects.

## Installation And Import

Flutter applications should depend on `cindel` and `cindel_flutter_libs`, and
use `cindel_generator` with `build_runner` to generate schemas and typed APIs.

```yaml
dependencies:
  cindel: ^0.9.1
  cindel_flutter_libs: ^0.9.1

dev_dependencies:
  build_runner: ^2.15.0
  cindel_generator: ^0.9.1
```

Use the public Cindel import in model and application code:

```dart
import 'package:cindel/cindel.dart';
```

This import exposes the public API most applications need:

- database opening helpers such as `Cindel.open` and `Cindel.openInMemory`,
- schema annotations such as `@Collection`, `@collection`, `@Index`, and
  `@Name`,
- generated typed collection and query APIs,
- query and filter helpers,
- transaction helpers,
- watcher helpers,
- migration APIs,
- sync configuration and adapter contracts,
- schema metadata types,
- public Cindel error types.

After defining annotated models, run code generation:

```sh
dart run build_runner build --delete-conflicting-outputs
```

The generator creates the `*.g.dart` files that contain schemas, serializers,
typed collection getters, and generated query helpers.

## First Complete Example

This example defines a `User` model, generates the Cindel API, opens a
database, writes data, reads it back, queries it, watches the collection, and
closes the database.

### 1. Add dependencies

```yaml
dependencies:
  cindel: ^0.9.1
  cindel_flutter_libs: ^0.9.1

dev_dependencies:
  build_runner: ^2.15.0
  cindel_generator: ^0.9.1
```

### 2. Define a model

Create a Dart file such as `user.dart`:

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

The model describes one persisted collection:

- `@Collection(name: 'users')` stores `User` objects in the `users`
  collection.
- `dbId` is the persisted id field.
- `autoIncrement` asks Cindel to assign an id when a new object is inserted.
- `email` is a unique indexed field.
- `name` is indexed for lookup queries.
- `active` and `createdAt` are regular persisted fields.

### 3. Generate the Cindel API

```sh
dart run build_runner build --delete-conflicting-outputs
```

After generation, the project has a `user.g.dart` file with the generated
schema and helpers. Application code can now pass `UserSchema` to
`Cindel.open` and use the generated `db.users` collection.

### 4. Open the database

```dart
final db = await Cindel.open(
  directory: directory.path,
  schemas: [UserSchema],
);
```

Use a stable directory for persistent app data. For tests, use
`Cindel.openInMemory` instead:

```dart
final db = await Cindel.openInMemory(schemas: [UserSchema]);
```

### 5. Write and read objects

```dart
final user = User()
  ..email = 'ada@example.com'
  ..name = 'Ada Lovelace';

await db.users.put(user);

final saved = await db.users.get(user.dbId);
```

After `put`, an auto-increment id is written back to `user.dbId`.

### 6. Query the collection

Use an indexed `where()` query when searching by `email` or `name`:

```dart
final ada = await db.users
    .where()
    .emailEqualTo('ada@example.com')
    .findFirst();
```

Use a `filter()` query for regular persisted fields:

```dart
final activeUsers = await db.users
    .filter()
    .activeEqualTo(true)
    .findAll();
```

Sort and limit results when building UI lists:

```dart
final newestUsers = await db.users
    .all()
    .sortByCreatedAt(order: CindelSortOrder.descending)
    .limit(20)
    .findAll();
```

### 7. Listen for changes

```dart
final subscription = db.users.watchCollection().listen((users) {
  // Update app state from the latest collection snapshot.
});

await db.users.put(
  User()
    ..email = 'grace@example.com'
    ..name = 'Grace Hopper',
);

await subscription.cancel();
```

Watchers are optional, but they are useful when a screen should react to local
database writes.

### 8. Close the database

```dart
await db.close();
```

Close the database when its owner is disposed, when a test finishes, or when a
short-lived command has completed its work.

## Where To Go Next

After this introduction, the documentation can expand each area separately:

- Getting Started explains opening databases, selecting backends, and handling
  startup errors.
- Data Modeling covers annotations, supported fields, embedded objects, enums,
  and Freezed models.
- Indexes explains how to design lookup, uniqueness, word, multi-entry, and
  composite indexes.
- Generated Typed API documents collection methods and generated helpers.
- Queries covers `where`, `filter`, sorting, pagination, projections,
  aggregates, updates, and deletes.
- Transactions, Watchers, Migrations, Sync, Web, Backup, Errors, and Testing
  each have their own deeper guides.
