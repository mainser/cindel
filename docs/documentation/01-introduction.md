# Introduction

Cindel is a local database for Dart and Flutter applications. It lets you model
your app data with Dart classes, generate a typed database API from those
classes, and then read or write local data through collection getters such as
`db.users`, `db.projects`, or `db.products`.

The main idea is simple: your application should work with Dart objects, not
with raw database rows, stringly typed maps, or backend-specific code paths.
Cindel handles the local storage layer behind a generated API that can run on
native Flutter platforms and on Flutter Web.

This page gives you the mental model for using Cindel. It intentionally stays
at the first-app level. The later guides explain setup, modeling, generated
collections, queries, transactions, watchers, migrations, sync, Web behavior,
backup, errors, and testing in more detail.

## When Cindel Fits

Cindel is useful when your app needs local structured data that should be
available quickly and typed throughout the Dart codebase.

Good examples include:

- offline-capable app data,
- local product, task, order, message, project, or settings records,
- cached records that should still be queryable,
- user-interface state that needs durable storage,
- local-first workflows where writes happen locally before they are synced.

Cindel is not a hosted backend and it does not replace your server. If your app
needs sync, you still provide the server and the adapter that talks to it.
Cindel stores the local data, records supported local changes, and calls your
adapter through the public sync contract.

## How A Cindel App Is Shaped

A typical Cindel app follows this flow:

1. Define a Dart model class.
2. Add Cindel annotations for the collection, id, indexes, and stored fields.
3. Run code generation.
4. Open the database with the generated schemas.
5. Use the generated collection API in application code.
6. Close the database when the owner is disposed.

The generated API is the normal public surface. Application code usually looks
like this:

```dart
final db = await Cindel.open(
  directory: appDataDirectory.path,
  schemas: [UserSchema],
);

final user = User()
  ..email = 'ada@example.com'
  ..name = 'Ada Lovelace';

await db.users.put(user);

final saved = await db.users.get(user.dbId);
final activeUsers = await db.users
    .filter()
    .activeEqualTo(true)
    .findAll();

await db.close();
```

The application code is typed end to end:

- `db.users.put(user)` accepts a `User`,
- `db.users.get(id)` returns a `User?`,
- generated query helpers are based on fields from the `User` model,
- invalid field names are not passed around as ordinary strings in everyday
  app code.

## A Minimal Model

Models are regular Dart classes annotated for persistence.

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

This model declares one persisted collection:

- `@Collection(name: 'users')` makes `User` a root collection.
- `dbId` is the stored id field.
- `autoIncrement` lets Cindel assign a new id when the object is first saved.
- `email` is unique, so duplicate emails are rejected.
- `name` is indexed, so generated indexed lookups can use it.
- `active` is stored as a normal field and can be used in filters.

After generation, Cindel creates the schema and typed helpers for this model.
For this example, application code registers `UserSchema` and uses `db.users`.

## Installation

Flutter apps normally depend on `cindel` and `cindel_flutter_libs`, and use
`cindel_generator` with `build_runner` for generated schemas and typed APIs.

```yaml
dependencies:
  cindel: ^0.9.2
  cindel_flutter_libs: ^0.9.2

dev_dependencies:
  build_runner: ^2.15.0
  cindel_generator: ^0.9.1
```

Use the public Cindel import in models and application code:

```dart
import 'package:cindel/cindel.dart';
```

Then run the generator:

```sh
dart run build_runner build --delete-conflicting-outputs
```

The generated `*.g.dart` files contain schemas, serializers, typed collection
getters, and query helpers. Do not hand-write those generated files.

## Opening A Database

Use `Cindel.open` for persistent app data:

```dart
final db = await Cindel.open(
  directory: appDataDirectory.path,
  schemas: [UserSchema],
);
```

The `schemas` list must include every generated collection schema that this
database handle will use.

Use `Cindel.openInMemory` for tests, examples, and short-lived work:

```dart
final db = await Cindel.openInMemory(
  schemas: [UserSchema],
);
```

On native platforms, `directory` is a filesystem directory. On Web, it is the
logical browser database name.

Close the database when its owner is done:

```dart
await db.close();
```

Closing more than once is safe.

## Working With Collections

Generated collection getters are the main way to use Cindel.

```dart
await db.users.put(user);

final sameUser = await db.users.get(user.dbId);
final users = await db.users.all().findAll();

await db.users.delete(user.dbId);
```

Collections also support batch operations:

```dart
await db.users.putAll([ada, grace]);

final results = await db.users.getAll([ada.dbId, grace.dbId]);
```

Use generated collections for normal application persistence. Lower-level
document helpers exist for generated code and advanced tooling, but they are
not the everyday app API.

## Reading Data

Cindel has three common query starting points:

- `all()` starts from the whole collection.
- `where()` uses generated helpers for indexed fields.
- `filter()` uses generated helpers for stored fields.

```dart
final everyone = await db.users.all().findAll();

final ada = await db.users
    .where()
    .emailEqualTo('ada@example.com')
    .findFirst();

final activeUsers = await db.users
    .filter()
    .activeEqualTo(true)
    .findAll();
```

Use indexes for fields that your app frequently searches by, sorts by, or needs
to keep unique. Use filters for ordinary predicates. The query guide explains
sorting, pagination, distinct values, projections, aggregates, query updates,
and query deletes.

## Platform Model

Cindel keeps the application API the same across supported platforms.

Native Flutter apps can use the default MDBX backend or explicitly select the
SQLite backend:

```dart
final db = await Cindel.open(
  directory: appDataDirectory.path,
  schemas: [UserSchema],
  backend: CindelStorageBackend.sqlite,
);
```

Flutter Web uses the same `Cindel.open` call and generated collection API. In
the browser, Cindel uses the packaged SQLite Web/OPFS Worker/Wasm runtime from
`cindel_flutter_libs`.

Web support is experimental, but it is still a typed Cindel backend path. App
code should not switch to a different public database API only because it is
running in the browser.

## Pre-1.0 Status

Cindel is currently pre-1.0. The public direction is the generated typed API:
open a database, register generated schemas, and work through generated typed
collections and queries.

Prefer these APIs in new application code:

- `Cindel.open` and `Cindel.openInMemory`,
- generated schemas such as `UserSchema`,
- generated collection getters such as `db.users`,
- generated `where()` and `filter()` helpers,
- `readTxn` and `writeTxn`,
- typed watchers,
- open-time migration and sync configuration.

Avoid building app code around raw, untyped collection-level persistence.
Advanced helpers remain available for tooling, migrations, backup, and
generated code, but they are not the main application model.

## What To Read Next

Use the rest of the documentation based on what you are trying to do:

- **Getting Started**: open databases, choose a backend, register schemas, and
  understand startup errors.
- **Data Modeling**: define collections, ids, field types, enums, embedded
  objects, ignored fields, and Freezed models.
- **Generated Typed API**: use generated collections for CRUD and batch work.
- **Relationships**: model links, backlinks, save operations, and explicit
  loading.
- **Queries** and **Filters**: read data with indexed queries, field filters,
  sorting, pagination, boolean composition, updates, and deletes.
- **Transactions**: group related reads and writes.
- **Watchers**: update UI state when local data changes.
- **Migrations**: move existing stored data between app schema versions.
- **Sync**: connect local-first writes to your own backend adapter.
- **Web**: use Cindel in Flutter Web and understand current browser limits.
- **Backup And Advanced Helpers**: export, import, scan ids, and run
  maintenance flows.
- **Errors** and **Testing**: handle common failures and write practical tests.
