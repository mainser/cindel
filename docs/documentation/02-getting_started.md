# Getting Started

This guide covers the first operational steps after you have a Cindel model and
generated code available: opening a database, registering schemas, using the
generated collection API, and recognizing the most common startup errors.

It does not cover data modeling, advanced queries, migrations, sync, or backup
flows in depth. Those topics should live in their own documentation pages.

## Opening A Database

Cindel databases are opened through the `Cindel` entry point. Most applications
use `Cindel.open` for persistent data. Tests, examples, and short-lived tasks
can use `Cindel.openInMemory`.

The database handle returned by either method is what you use to access
generated collections:

```dart
final db = await Cindel.open(
  directory: directory.path,
  schemas: [UserSchema],
);

final users = await db.users.all().findAll();
```

The important requirement is that every collection you want to use must have
its generated schema registered when the database opens.

### `Cindel.open`

Use `Cindel.open` when the data should persist between app launches.

```dart
final db = await Cindel.open(
  directory: directory.path,
  schemas: [UserSchema, ProjectSchema],
);
```

`Cindel.open` receives:

- `directory`: where the database is stored. On native platforms this is a
  filesystem directory. On Web this is the logical browser database name.
- `schemas`: the generated collection schemas that this database handle should
  register and use.
- `backend`: an optional native backend selector.
- `migrationPlan`: an optional migration plan for controlled schema/data
  changes.
- `sync`: an optional sync configuration enabled when the database opens.

A minimal native app usually opens the database with a real app-data directory:

```dart
final db = await Cindel.open(
  directory: appDataDirectory.path,
  schemas: [UserSchema],
);
```

A database handle should generally be owned by a clear part of your app, such
as an application service, repository container, or test fixture. Open it once
for that owner, pass it to the code that needs it, and close it when the owner
is disposed.

### `Cindel.openInMemory`

Use `Cindel.openInMemory` for tests, examples, and temporary work where the
data does not need to persist.

```dart
final db = await Cindel.openInMemory(
  schemas: [UserSchema],
);
```

This is the usual choice for unit tests:

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

On native platforms, this opens a temporary runtime database. On Web, it uses a
unique browser database name for temporary use.

### Available Backends

Cindel exposes the native backend selector through `CindelStorageBackend`:

```dart
enum CindelStorageBackend {
  sqlite,
  mdbx,
}
```

MDBX is the default native backend:

```dart
const defaultCindelStorageBackend = CindelStorageBackend.mdbx;
```

Most native applications can omit the `backend` parameter:

```dart
final db = await Cindel.open(
  directory: directory.path,
  schemas: [UserSchema],
);
```

Select SQLite explicitly when your application should use the native SQLite
backend:

```dart
final db = await Cindel.open(
  directory: directory.path,
  schemas: [UserSchema],
  backend: CindelStorageBackend.sqlite,
);
```

Backend selection is only needed when opening a persistent native database.
The generated model, schema, collection, and query APIs remain the same.

### Web Usage

Flutter Web uses the same `Cindel.open` shape as native applications:

```dart
final db = await Cindel.open(
  directory: 'app-data',
  schemas: [UserSchema],
);
```

On Web, `directory` is a logical browser database name, not a filesystem path.
Use a stable name for persistent app data:

```dart
final db = await Cindel.open(
  directory: 'shop-lite',
  schemas: [ProductSchema, CartItemSchema],
);
```

Web applications should depend on both `cindel` and `cindel_flutter_libs`:

```yaml
dependencies:
  cindel: ^0.9.1
  cindel_flutter_libs: ^0.9.1
```

The browser context must support Workers, Wasm, and OPFS. MDBX is not a browser
backend, so the native `backend` selector is not used for Web storage.

### Closing A Database

Close the database when the owner of the handle is done with it:

```dart
await db.close();
```

Closing more than once is safe:

```dart
await db.close();
await db.close();
```

Closing also rolls back an active transaction and closes active watcher
streams. In tests, register close as teardown so each test cleans up its own
database handle:

```dart
final db = await Cindel.openInMemory(schemas: [UserSchema]);
addTearDown(db.close);
```

## Registering Schemas

Generated schemas are passed to `Cindel.open` or `Cindel.openInMemory` through
the `schemas` list.

```dart
final db = await Cindel.open(
  directory: directory.path,
  schemas: [UserSchema, AccountSchema, ProjectSchema],
);
```

Each schema corresponds to a generated Cindel collection. For example, this
model:

```dart
@Collection(name: 'users')
class User {
  Id dbId = autoIncrement;
  late String email;
}
```

generates a schema constant such as `UserSchema`. Registering that schema makes
the `users` collection available to the database handle:

```dart
final db = await Cindel.open(
  directory: directory.path,
  schemas: [UserSchema],
);

await db.users.put(user);
```

Register all collections that the opened database needs to read or write:

```dart
final db = await Cindel.open(
  directory: directory.path,
  schemas: [
    UserSchema,
    ProjectSchema,
    TaskSchema,
  ],
);
```

If a feature uses several collections together, open the database with all of
those schemas. For example, a project screen that writes projects and tasks
should register both:

```dart
final db = await Cindel.open(
  directory: directory.path,
  schemas: [ProjectSchema, TaskSchema],
);
```

The `schemas` list should describe the collections expected by the current
application version. If stored metadata and registered schemas are
incompatible, opening the database fails with a schema error instead of letting
the app continue with an unsafe database handle.

## Using Generated Collections

Typed collections are usually accessed through generated extension getters on
the database handle. A collection named `users` is used as `db.users`; a
collection named `projects` is used as `db.projects`.

```dart
final user = User()
  ..email = 'ada@example.com'
  ..name = 'Ada Lovelace';

await db.users.put(user);
```

Generated collections expose common CRUD operations.

Write one object:

```dart
await db.users.put(user);
```

Write several objects:

```dart
await db.users.putAll([ada, grace, linus]);
```

Read one object by id:

```dart
final user = await db.users.get(userId);
```

Read several objects by id:

```dart
final users = await db.users.getAll([firstUserId, secondUserId]);
```

Read the full collection:

```dart
final users = await db.users.all().findAll();
```

Delete one object:

```dart
await db.users.delete(userId);
```

Delete several objects:

```dart
await db.users.deleteAll([firstUserId, secondUserId]);
```

If the model id is `autoIncrement`, `put` allocates an id and writes it back to
the object:

```dart
final user = User()
  ..email = 'ada@example.com'
  ..name = 'Ada Lovelace';

await db.users.put(user);

print(user.dbId);
```

Generated collections also expose query entry points. Use `where()` for
indexed fields:

```dart
final user = await db.users
    .where()
    .emailEqualTo('ada@example.com')
    .findFirst();
```

Use `filter()` for general persisted fields:

```dart
final activeUsers = await db.users
    .filter()
    .activeEqualTo(true)
    .findAll();
```

The exact generated method names depend on your model fields and indexes.

## Common Startup Errors

Startup errors usually happen while opening the database, before application
code starts reading and writing collections.

### Empty `directory`

`Cindel.open` requires a non-empty `directory`.

```dart
await Cindel.open(
  directory: '',
  schemas: [UserSchema],
);
```

This fails with `ArgumentError`. Use a real filesystem directory on native
platforms or a stable logical database name on Web.

### Backend Open Failure

If the selected backend cannot be opened, Cindel throws `CindelOpenError`.

Common things to check:

- the native app is using a valid writable directory,
- the app has permission to access that directory,
- the selected native backend is available for the target platform,
- the Web app is served from a browser context that supports Workers, Wasm, and
  OPFS.

Example:

```dart
try {
  final db = await Cindel.open(
    directory: directory.path,
    schemas: [UserSchema],
  );
  // Use db.
} on CindelOpenError catch (error) {
  // Report or log that the database could not be opened.
}
```

### Missing Or Incompatible Schemas

If registered schemas are missing or incompatible with stored metadata,
opening the database fails with `CindelSchemaError`.

This can happen when:

- the database is opened without a schema for a collection the app expects,
- the app uses a changed model against existing stored metadata without the
  required migration path,
- the app opens the same persisted database with a different schema set than
  the one expected for that data.

Example:

```dart
try {
  final db = await Cindel.open(
    directory: directory.path,
    schemas: [UserSchema],
  );
  // Use db.users.
} on CindelSchemaError catch (error) {
  // Handle schema registration or compatibility failure.
}
```

The fix is to open the database with the generated schemas for the current app
version, and to provide a migration plan when stored data needs to move between
incompatible schema versions.

### Generated Code Is Missing

If your Dart code references generated symbols such as `UserSchema` or
`db.users` and they do not exist, the Cindel generator has not produced the
needed `*.g.dart` file yet, or the source file is missing the correct `part`
directive.

The model file should include:

```dart
part 'user.g.dart';
```

After defining or changing models, run code generation:

```sh
dart run build_runner build --delete-conflicting-outputs
```

Generated-code errors happen at Dart analysis or compile time, before the
database opens. Startup errors such as `CindelOpenError` and
`CindelSchemaError` happen at runtime while opening the database.
