# Generated Typed API

Cindel applications usually do not work with raw documents directly. Instead,
you define annotated Dart models, run the generator, and use the generated
schemas, collection getters, CRUD helpers, and query entry points.

This guide covers the generated API surface for collections: what Cindel
generates, how typed collections are used, and a complete CRUD example.

## What Cindel Generates

For each root collection model, generated code creates the pieces needed to use
that model with a `CindelDatabase`.

Given this model:

```dart
import 'package:cindel/cindel.dart';

part 'todo.g.dart';

@Collection(name: 'todos')
class Todo {
  Id dbId = autoIncrement;

  @Index()
  late String title;

  bool completed = false;

  @Index()
  DateTime createdAt = DateTime.now().toUtc();
}
```

Cindel generates the public API that application code uses:

- a `CindelCollectionSchema<T>` constant, such as `TodoSchema`,
- a typed collection getter, such as `db.todos`,
- typed CRUD helpers,
- generated `where()` helpers for indexed fields,
- generated `filter()` helpers for persisted fields,
- sort, distinct, property, projection, and aggregate helpers,
- embedded object conversion and nested filter helpers when the model uses
  embedded objects,
- unique replace helpers for indexes declared with `replace: true`.

The generated schema is registered when the database opens:

```dart
final db = await Cindel.open(
  directory: directory.path,
  schemas: [TodoSchema],
);
```

The generated collection getter is then used for normal operations:

```dart
final todo = Todo()
  ..title = 'Ship docs';

await db.todos.put(todo);

final saved = await db.todos.get(todo.dbId);
```

The generated API keeps application code typed. `db.todos.put` receives a
`Todo`, `db.todos.get` returns a `Todo?`, and generated query helpers are based
on the model fields.

## Typed Collections

Typed collections are usually accessed through generated extension getters on
the database handle.

```dart
final todos = db.todos;
```

Most application code should use these generated getters instead of constructing
collections manually. The collection getter is named from the collection model
and persisted collection name generated for that model.

### `all`

`all()` starts a query over the whole collection.

```dart
final todos = await db.todos.all().findAll();
```

Use `all()` when the operation should consider every object in the collection.
It is commonly combined with result methods and collection-level query helpers:

```dart
final count = await db.todos.all().count();

final newest = await db.todos
    .all()
    .sortByCreatedAt(order: CindelSortOrder.descending)
    .findAll();
```

Use pagination when a collection can be large:

```dart
final page = await db.todos
    .all()
    .sortByCreatedAt(order: CindelSortOrder.descending)
    .offset(20)
    .limit(10)
    .findAll();
```

### `put`

`put` stores one typed object.

```dart
final todo = Todo()
  ..title = 'Ship docs';

await db.todos.put(todo);
```

If the id field is `autoIncrement`, Cindel assigns an id and writes it back to
the object:

```dart
final todo = Todo()
  ..title = 'Ship docs';

await db.todos.put(todo);

print(todo.dbId);
```

If the object already has an explicit id, `put` writes that id:

```dart
final todo = Todo()
  ..dbId = 42
  ..title = 'Import data';

await db.todos.put(todo);
```

Use `put` for creating a single object or replacing the stored value for an
existing id.

### `putAll` / `putMany`

`putAll` and `putMany` store multiple typed objects atomically.

```dart
await db.todos.putAll([first, second, third]);
await db.todos.putMany(moreTodos);
```

Use batch writes when several objects should be stored together:

```dart
final todos = [
  Todo()..title = 'Write guide',
  Todo()..title = 'Review examples',
  Todo()..title = 'Publish docs',
];

await db.todos.putAll(todos);
```

Empty batches are no-ops:

```dart
await db.todos.putAll([]);
```

Duplicate ids inside the same batch are rejected. Make sure each object in the
batch has a distinct explicit id, or let Cindel allocate ids for
`autoIncrement` objects.

### `putBy...`

Generated `putBy...` and `putAllBy...` helpers are created for unique replace
indexes.

For example:

```dart
@collection
class Account {
  Id dbId = autoIncrement;

  @Index(unique: true, replace: true)
  late String username;
}
```

The generated collection can expose helpers such as:

```dart
await db.accounts.putByUsername(account);
await db.accounts.putAllByUsername(accounts);
```

Use these helpers when a field acts as a natural key and a write should reuse
the existing row for that key instead of appending a duplicate.

```dart
final account = Account()
  ..username = 'ada'
  ..displayName = 'Ada Lovelace';

await db.accounts.putByUsername(account);
```

If an account with username `ada` already exists, the generated helper writes
to that existing id. If it does not exist, it inserts a new object.

The exact helper name depends on the indexed field name.

### `get`

`get` reads one object by id.

```dart
final todo = await db.todos.get(1);
```

The result is nullable:

```dart
final todo = await db.todos.get(todoId);

if (todo == null) {
  // No object exists for this id.
  return;
}

print(todo.title);
```

Use `get` when you already know the id of the object you want.

### `getAll`

`getAll` reads several objects by id.

```dart
final todos = await db.todos.getAll([3, 404, 1, 3]);
```

Results are returned in the same order as the requested ids. Missing ids return
`null`, and duplicate requested ids produce duplicate result positions.

```dart
final todos = await db.todos.getAll([firstId, missingId, firstId]);

final first = todos[0];
final missing = todos[1];
final firstAgain = todos[2];
```

Use `getAll` when you need to hydrate a known list of ids while preserving
their order.

### `delete`

`delete` removes one object by id.

```dart
await db.todos.delete(todoId);
```

Use `delete` when the caller knows exactly which object should be removed.

```dart
final todo = await db.todos.get(todoId);

if (todo != null) {
  await db.todos.delete(todo.dbId);
}
```

After deletion, `get` returns `null` for that id:

```dart
await db.todos.delete(todoId);

final deleted = await db.todos.get(todoId);
```

### `deleteAll`

`deleteAll` removes several objects by id.

```dart
await db.todos.deleteAll([1, 2, 3]);
```

Use `deleteAll` when the application already has the ids to remove:

```dart
final selectedIds = [firstTodoId, secondTodoId, thirdTodoId];

await db.todos.deleteAll(selectedIds);
```

For deleting by a query condition, use query delete APIs in the query
documentation. For direct id-based removal, prefer `delete` or `deleteAll`.

### `typedCollection`

Generated extension getters call `typedCollection` internally. Most
applications do not need to call it directly.

```dart
final todos = db.typedCollection(TodoSchema);
await todos.put(todo);
```

Use the generated getter when it is available:

```dart
await db.todos.put(todo);
```

`typedCollection` is useful for advanced wiring where code receives a schema
directly and needs to obtain the matching typed collection from a database
handle.

```dart
Future<void> seedTodos(CindelDatabase db) async {
  final todos = db.typedCollection(TodoSchema);

  await todos.putAll([
    Todo()..title = 'Create project',
    Todo()..title = 'Write documentation',
  ]);
}
```

## Complete CRUD Example

This example shows a complete collection workflow: define a model, open the
database with its schema, create objects, read them, update one, list objects,
and delete them.

### 1. Define the model

```dart
import 'package:cindel/cindel.dart';

part 'todo.g.dart';

@Collection(name: 'todos')
class Todo {
  Id dbId = autoIncrement;

  @Index()
  late String title;

  bool completed = false;

  @Index()
  DateTime createdAt = DateTime.now().toUtc();
}
```

### 2. Open the database

```dart
final db = await Cindel.open(
  directory: directory.path,
  schemas: [TodoSchema],
);
```

### 3. Create objects

```dart
final first = Todo()
  ..title = 'Write API docs';

final second = Todo()
  ..title = 'Review examples';

await db.todos.putAll([first, second]);
```

After the write, both objects have assigned ids:

```dart
print(first.dbId);
print(second.dbId);
```

### 4. Read one object

```dart
final saved = await db.todos.get(first.dbId);

if (saved == null) {
  throw StateError('Todo was not found');
}
```

### 5. Update an object

To update an object, change the Dart object and write it again.

```dart
saved.completed = true;

await db.todos.put(saved);
```

The stored object for `saved.dbId` now has the updated field values.

### 6. Read several objects

```dart
final selected = await db.todos.getAll([first.dbId, second.dbId]);
```

The result positions match the requested ids:

```dart
final selectedFirst = selected[0];
final selectedSecond = selected[1];
```

### 7. List the collection

```dart
final allTodos = await db.todos.all().findAll();
```

Use generated query helpers when you need a specific subset:

```dart
final matching = await db.todos
    .where()
    .titleEqualTo('Write API docs')
    .findAll();
```

### 8. Delete objects

Delete one object:

```dart
await db.todos.delete(first.dbId);
```

Delete several objects:

```dart
await db.todos.deleteAll([second.dbId]);
```

### 9. Close the database

```dart
await db.close();
```

At this point the typed collection workflow has covered the core CRUD path:
open with a schema, use the generated collection getter, write typed objects,
read typed objects, update by writing again, and delete by id.
