# Getting Started

This guide shows the first operational steps for using Cindel in an app:
opening a database, registering generated schemas, choosing the right backend
shape, using the generated collection API, and recognizing common startup
errors.

It assumes you already have at least one annotated model and generated code. If
you are still deciding how to model data, start with the Data Modeling guide
first.

## Before You Open A Database

A Cindel database is opened with generated schemas. That means these pieces
should already exist:

- a model annotated with `@Collection` or `@collection`,
- a `part` directive for the generated file,
- generated code from `build_runner`,
- a generated schema constant such as `UserSchema`.

For example:

```dart
import 'package:cindel/cindel.dart';

part 'user.g.dart';

@Collection(name: 'users')
class User {
  Id dbId = autoIncrement;

  @Index(unique: true)
  late String email;

  late String name;

  bool active = true;
}
```

After generation, the app can register `UserSchema` and use `db.users`.

If symbols such as `UserSchema` or `db.users` do not exist yet, run generation
before opening the database:

```sh
dart run build_runner build --delete-conflicting-outputs
```

## Opening Persistent Data

Use `Cindel.open` when the data should stay available after the app closes and
opens again.

```dart
final db = await Cindel.open(
  directory: appDataDirectory.path,
  schemas: [UserSchema],
);
```

The two required values are:

- `directory`: where this database is stored.
- `schemas`: the generated collection schemas this database handle can use.

On native platforms, `directory` is a filesystem directory. Use a stable
application-data directory, not a temporary path, for real user data.

On Web, `directory` is the logical browser database name:

```dart
final db = await Cindel.open(
  directory: 'shop-lite',
  schemas: [ProductSchema, CartItemSchema],
);
```

Use a stable name on Web as well. Changing the name means opening a different
browser database.

The database handle is what application code uses to reach generated
collections:

```dart
final users = await db.users.all().findAll();
```

Open the database once for the owner that needs it, such as an app service,
repository container, widget test fixture, or command. Pass that handle to the
code that needs database access.

## Temporary Databases

Use `Cindel.openInMemory` for tests, examples, and short-lived work where data
does not need to persist.

```dart
final db = await Cindel.openInMemory(
  schemas: [UserSchema],
);
```

This is the usual shape for a small test:

```dart
test('stores a user', () async {
  final db = await Cindel.openInMemory(schemas: [UserSchema]);
  addTearDown(db.close);

  final user = User()
    ..email = 'ada@example.com'
    ..name = 'Ada';

  await db.users.put(user);

  expect(await db.users.get(user.dbId), isNotNull);
});
```

On native platforms this opens a temporary runtime database. On Web it creates
a unique browser database name for temporary use.

## Choosing A Backend

Most native Flutter apps can omit the `backend` parameter. MDBX is the default
native backend:

```dart
final db = await Cindel.open(
  directory: appDataDirectory.path,
  schemas: [UserSchema],
);
```

Select SQLite explicitly only when your app should use the native SQLite
backend:

```dart
final db = await Cindel.open(
  directory: appDataDirectory.path,
  schemas: [UserSchema],
  backend: CindelStorageBackend.sqlite,
);
```

The backend choice should not change your application-level Cindel code.
Generated schemas, collection getters, CRUD operations, and queries keep the
same shape.

Flutter Web does not use MDBX. Web callers keep the same `Cindel.open` API,
and Cindel uses the packaged SQLite Web/OPFS Worker/Wasm runtime.

## Flutter Web Setup

Flutter Web apps should depend on both `cindel` and `cindel_flutter_libs`:

```yaml
dependencies:
  cindel: ^0.9.2
  cindel_flutter_libs: ^0.9.2
```

Open the database with a logical browser database name:

```dart
final db = await Cindel.open(
  directory: 'app-data',
  schemas: [UserSchema],
);
```

The browser context must support Workers, Wasm, and OPFS. Web support is still
experimental, so keep Web validation in your app focused on startup, asset
loading, persistence after reopen, queries, transactions, and watcher behavior.

## Closing A Database

Close the database when its owner is disposed or when a test finishes:

```dart
await db.close();
```

Closing more than once is safe:

```dart
await db.close();
await db.close();
```

Closing also rolls back an active transaction and closes active watcher
streams. In tests, register the close call as teardown:

```dart
final db = await Cindel.openInMemory(schemas: [UserSchema]);
addTearDown(db.close);
```

## Registering Schemas

Every collection you want to read or write through a database handle must be
registered when the database opens.

```dart
final db = await Cindel.open(
  directory: appDataDirectory.path,
  schemas: [
    UserSchema,
    ProjectSchema,
    TaskSchema,
  ],
);
```

Each schema comes from generated code. A model like this:

```dart
@Collection(name: 'users')
class User {
  Id dbId = autoIncrement;

  @Index(unique: true)
  late String email;

  late String name;

  bool active = true;
}
```

generates a schema constant such as `UserSchema`. Registering that schema makes
the generated collection available:

```dart
await db.users.put(user);
```

Register schemas by the data the opened app version expects to use. If a
screen or feature works with projects and tasks together, register both
schemas:

```dart
final db = await Cindel.open(
  directory: appDataDirectory.path,
  schemas: [ProjectSchema, TaskSchema],
);
```

If stored metadata and the registered schemas do not match safely, opening the
database fails with a schema error. That is intentional: the app should not
continue with a database handle whose stored data does not match the generated
API.

Use a migration plan when an existing persisted database needs to move through
an incompatible model change.

## Using Generated Collections

Generated collection getters are the normal way to read and write data. A
collection named `users` is used as `db.users`; a collection named `projects`
is used as `db.projects`.

Create and save an object:

```dart
final user = User()
  ..email = 'ada@example.com'
  ..name = 'Ada Lovelace';

await db.users.put(user);
```

If the id field uses `autoIncrement`, `put` assigns the id and writes it back
to the object:

```dart
print(user.dbId);
```

Read one object by id:

```dart
final saved = await db.users.get(user.dbId);
```

Read several ids in one call:

```dart
final users = await db.users.getAll([firstUserId, secondUserId]);
```

Read the whole collection:

```dart
final allUsers = await db.users.all().findAll();
```

Write or delete several objects:

```dart
await db.users.putAll([ada, grace, linus]);
await db.users.deleteAll([ada.dbId, grace.dbId]);
```

Delete one object:

```dart
await db.users.delete(userId);
```

For filtered reads, use generated query entry points:

```dart
final user = await db.users
    .where()
    .emailEqualTo('ada@example.com')
    .findFirst();

final activeUsers = await db.users
    .filter()
    .activeEqualTo(true)
    .findAll();
```

The exact generated method names depend on your model fields and indexes. The
Generated Typed API and Queries guides cover the full collection and query
surface.

## Common Startup Errors

Startup errors usually happen while opening the database, before normal reads
and writes begin.

### Empty `directory`

`Cindel.open` requires a non-empty `directory`.

```dart
await Cindel.open(
  directory: '',
  schemas: [UserSchema],
);
```

This fails with `ArgumentError`.

Use a real filesystem directory on native platforms or a stable logical
database name on Web.

### `CindelOpenError`

`CindelOpenError` means the selected backend could not be opened.

Check the practical causes first:

- the native directory exists or can be created,
- the app can write to that directory,
- the selected backend is available for the target platform,
- the Web app is served from a browser context with Workers, Wasm, and OPFS,
- Web runtime assets from `cindel_flutter_libs` are available to the app.

Example:

```dart
try {
  final db = await Cindel.open(
    directory: appDataDirectory.path,
    schemas: [UserSchema],
  );
  // Use db.
} on CindelOpenError catch (error) {
  // Log or show that local storage could not be opened.
}
```

### `CindelSchemaError`

`CindelSchemaError` means the generated schemas registered at open time are
missing or incompatible with stored metadata.

Common causes:

- a collection schema was left out of the `schemas` list,
- generated code is stale after a model change,
- existing stored data needs a migration plan,
- the same persisted database is opened by app versions with different schema
  expectations.

Example:

```dart
try {
  final db = await Cindel.open(
    directory: appDataDirectory.path,
    schemas: [UserSchema],
  );
  // Use db.users.
} on CindelSchemaError catch (error) {
  // Handle schema registration or compatibility failure.
}
```

The fix is usually to open with the current generated schemas and add a
migration plan when stored data must move between incompatible model versions.

### Generated Code Is Missing

Missing generated symbols are different from runtime startup errors. If Dart
cannot find `UserSchema`, `db.users`, or another generated helper, the database
has not opened yet. The source code is missing generated output or the model
file is missing the correct `part` directive.

The model file should include:

```dart
part 'user.g.dart';
```

Then run generation:

```sh
dart run build_runner build --delete-conflicting-outputs
```

Generated-code problems appear during analysis or compilation. `ArgumentError`,
`CindelOpenError`, and `CindelSchemaError` happen at runtime while opening the
database.
