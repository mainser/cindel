# Generated Typed API

Cindel apps normally use generated Dart APIs instead of raw database documents.
You define annotated models, run code generation, register the generated
schemas when opening the database, and then work through typed collection
getters such as `db.todos`.

This guide explains the generated collection API: what gets generated, how to
use typed collections, and how the core CRUD methods behave. Query conditions,
sorting, projections, aggregates, transactions, and watchers are covered in
their own guides.

## What Cindel Generates

For each root collection model, Cindel generates the pieces your app needs to
store and read that model.

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

the generated code includes:

- a schema constant, such as `TodoSchema`,
- a typed collection getter, such as `db.todos`,
- CRUD helpers for `Todo` objects,
- generated `where()` helpers for indexed fields,
- generated `filter()` helpers for persisted fields,
- sort, distinct, property, projection, and aggregate helpers,
- embedded object conversion and nested filter helpers when the model uses
  embedded objects,
- natural-key write helpers for unique indexes declared with `replace: true`.

The generated schema is registered when the database opens:

```dart
final db = await Cindel.open(
  directory: appDataDirectory.path,
  schemas: [TodoSchema],
);
```

After that, the app uses the generated collection:

```dart
final todo = Todo()
  ..title = 'Ship docs';

await db.todos.put(todo);

final saved = await db.todos.get(todo.dbId);
```

The types stay visible in application code. `db.todos.put` receives a `Todo`,
`db.todos.get` returns a `Todo?`, and generated query helpers are based on the
fields declared on `Todo`.

## Typed Collections

A typed collection is the generated API for one model collection.

```dart
final todos = db.todos;
```

Most application code should use generated getters like `db.todos`,
`db.users`, or `db.orders`. They are easier to read and keep the code tied to
the model type.

Two separate steps are needed:

1. Generate and import the model library so the getter exists in Dart code.
2. Register its generated schema when opening the database so that handle can
   use the collection.

```dart
final db = await Cindel.open(
  directory: appDataDirectory.path,
  schemas: [TodoSchema],
);

await db.todos.put(Todo()..title = 'Create project');
```

If `TodoSchema` or `db.todos` is missing, check the model's `part` directive
and run code generation.

### Operation Results

| Method | Result |
| --- | --- |
| `put`, `putAll`, `putMany` | `Future<void>`; auto-assigned IDs are written into mutable objects. |
| `get(id)` | `Future<T?>`; null means the ID was not found. |
| `getAll(ids)` | `Future<List<T?>>`; input order and missing entries are preserved. |
| `delete(id)`, `deleteAll(ids)` | `Future<void>`, not a deleted-row count. |

Query deletion is a different API: query `deleteFirst()` returns `bool` and
query `deleteAll()` returns the number of deleted matches. For immutable
objects, [reserve IDs before construction](03-data_modeling.md#ids-in-immutable-models).

## Query Entry Point: `all`

`all()` starts a query over the whole collection.

```dart
final todos = await db.todos.all().findAll();
```

Use it when the operation should consider every object in the collection. It is
often combined with query result helpers:

```dart
final count = await db.todos.all().count();
```

It can also be combined with sorting and pagination:

```dart
final newest = await db.todos
    .all()
    .sortByCreatedAt(order: CindelSortOrder.descending)
    .limit(20)
    .findAll();
```

For large collections, avoid loading every object just to show a small screen.
Use sorting, offset, and limit when the UI only needs a page of results.

## Writing One Object: `put`

`put` stores one typed object.

```dart
final todo = Todo()
  ..title = 'Ship docs';

await db.todos.put(todo);
```

If the id field is `autoIncrement`, Cindel assigns an id and writes it back to
the object:

```dart
await db.todos.put(todo);

print(todo.dbId);
```

If the object already has an explicit id, `put` writes to that id:

```dart
final imported = Todo()
  ..dbId = 42
  ..title = 'Imported item';

await db.todos.put(imported);
```

Use `put` for both creates and updates. To update an object, read it, change
the Dart fields, and write it again:

```dart
final saved = await db.todos.get(todoId);

if (saved != null) {
  saved.completed = true;
  await db.todos.put(saved);
}
```

## Writing Many Objects: `putAll` And `putMany`

`putAll` stores multiple typed objects together.

```dart
await db.todos.putAll([first, second, third]);
```

`putMany` is an alias for `putAll` for code that prefers "many" naming.

```dart
await db.todos.putMany(moreTodos);
```

Use batch writes when several objects should be stored as one operation:

```dart
final todos = [
  Todo()..title = 'Write guide',
  Todo()..title = 'Review examples',
  Todo()..title = 'Publish docs',
];

await db.todos.putAll(todos);
```

Empty batches are safe no-ops:

```dart
await db.todos.putAll([]);
```

Duplicate ids inside the same batch are rejected before the batch is written.
Make sure objects with explicit ids are distinct, or let Cindel allocate ids
for objects that still use `autoIncrement`.

### Automatic IDs In Bulk Writes

`putAll` reserves the IDs needed by objects whose ID is `autoIncrement` in one
batch, then assigns them in input order. Explicit IDs remain unchanged. This
reduces allocation calls on MDBX, SQLite native, and Web without changing the
public API. An empty batch or a batch containing only explicit IDs does not
need an automatic-ID reservation.

Allocation uses transactional database state, including when separate native
handles write to the same database. IDs are unique reservations, not a promise
of gapless numbering. A reservation outside an explicit write transaction can
survive a later failed write. Inside `writeTxn`, the counter and stored data
roll back together; IDs already assigned to Dart objects do not roll back.
Account for that before retrying those objects.

Duplicate IDs in one batch are rejected. Mixing explicit and automatic IDs is
allowed, but an explicit ID can overlap the reserved range; the allocator does
not search around IDs supplied in the same input batch.

`putAll` processes a materialized input list. Split very large inputs into
application batches when memory matters. Use `writeTxn` around those batches
only if they must commit together, allowing for the backend's transaction
storage. See [transactions](09-transactions.md).

## Natural-Key Writes: `putBy...`

When a model has a unique index with `replace: true`, the generator creates
helpers that write by that unique value.

```dart
@collection
class Account {
  Id dbId = autoIncrement;

  @Index(unique: true, replace: true)
  late String username;

  late String displayName;
}
```

The generated collection can expose helpers such as:

```dart
await db.accounts.putByUsername(account);
await db.accounts.putAllByUsername(accounts);
```

Use these helpers when the indexed field acts like a natural key. If an object
with the same key already exists, Cindel writes to that existing id. If no
object exists for that key, Cindel inserts a new one.

```dart
final account = Account()
  ..username = 'ada'
  ..displayName = 'Ada Lovelace';

await db.accounts.putByUsername(account);
```

The exact helper name depends on the field name. A field named `username`
generates names such as `putByUsername` and `putAllByUsername`.

Natural-key helpers may need to assign an existing ID to the supplied object.
An immutable object must already carry that ID; the helper cannot rewrite a
final `dbId`. Read the existing row and construct its replacement with the same
ID when working with immutable natural-key models.

## Reading One Object: `get`

`get` reads one object by id.

```dart
final todo = await db.todos.get(todoId);
```

The result is nullable because the id may not exist:

```dart
final todo = await db.todos.get(todoId);

if (todo == null) {
  // Nothing is stored for this id.
  return;
}

print(todo.title);
```

Use `get` when the app already knows the id it wants to load. For lookup by a
field such as `email`, `username`, or `createdAt`, use generated query helpers
from `where()` or `filter()`.

## Reading Many Objects: `getAll`

`getAll` reads several ids in one call.

```dart
final todos = await db.todos.getAll([3, 404, 1, 3]);
```

The result list follows the requested id order:

- existing ids return the typed object,
- missing ids return `null`,
- repeated requested ids produce repeated result positions.

```dart
final todos = await db.todos.getAll([firstId, missingId, firstId]);

final first = todos[0];
final missing = todos[1];
final firstAgain = todos[2];
```

Use `getAll` when you already have a list of ids and need to preserve that
order, such as ids from a relationship, a search result, an import step, or a
selection list.

Inside `writeTxn`, `getAll` includes the handle's pending writes and returns
null for pending deletions, with the same ordering and duplicate-ID behavior.
This also applies to generated models with final IDs. See
[transactional reads](09-transactions.md#await-every-operation-and-control-handle-ownership).

Web readers calculate schema offsets and the expected static size once per
reader, while still validating each document's header, bounds and field types.
SQLite's binary result encoder also shares one immutable layout across the
batch, including batches split into multiple SQL statements. Dynamic payload
offsets remain specific to each row; this does not cache application objects
or change the order, missing entries or duplicate-ID behavior of `getAll`.

For generated Web `getAll` reads, Rust writes the response directly from the
retrieved rows in the requested ID order. It checks the final message size and
reserves its buffer once, without cloning document payloads into an intermediate
ordered list. Sizing uses the rows already read; it does not issue another query.
Missing IDs still produce `null`, and duplicate IDs still produce independently
decoded Dart objects. SQL chunking and transaction visibility are unchanged.
This reduces temporary allocation, but is not a streaming API: retrieved rows
and the final response coexist during encoding, and memory still grows with the
requested result size. MDBX and SQLite native retain their existing cursor reads.

The Dart collection and database layers share one private snapshot of `getAll`
IDs. Caller-owned lists and lazy iterables are captured before the operation
suspends; changing the original list while the read is pending cannot change
the requested IDs. Direct database reads also capture external inputs, including
unmodifiable views whose underlying list may still be mutable.

The collection returns the object list already built by the reader. Models
without relationships need no additional binding pass. Models with relationships
are bound on that same list after hydration, error checking and reader release,
in input order and skipping missing objects. Results remain independently
mutable, including duplicate IDs and empty batches. This removes temporary Dart
lists without changing the generated API, database snapshots or wire format.

Read preparation is also reused internally. MDBX point reads open only the
document table and retain the existing transaction's snapshot and pending-write
visibility. Its generated `getAll` already uses a document cursor. SQLite native
reuses its ordered field metadata and prepared ID lookup; Web reuses prepared
`IN` statements when the same batch shape is requested again. These are internal
optimizations: application code and the generated API are identical on all three
backends.

Each active SQLite reader exclusively owns its statement. Returning it resets
the cursor and clears the parameters, so the cache retains neither a read
snapshot nor application results. Schema registration, migration, restore and
transaction rollback invalidate preparation; closing releases cached statements.
An active native statement from an invalidated cache is discarded when returned.

The native cursor and binary batch paths each retain at most eight idle
statements. A statement is retained only when its SQLite-reported memory plus
SQL text is at most 64 KiB; larger requests execute normally without retaining
their statement. Thus these two caches together retain at most 1 MiB of measured
statement/SQL storage per connection, plus container overhead. Lazily constructed
field-order and SQL metadata are separate and proportional to the registered
schemas. This trades a small amount of retained preparation memory for less
repeated work; it does not change the number of rows returned or cache objects.

## Deleting One Object: `delete`

`delete` removes one object by id.

```dart
await db.todos.delete(todoId);
```

Use it when the caller knows exactly which object should be removed:

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

## Deleting Many Objects: `deleteAll`

`deleteAll` removes several objects by id.

```dart
await db.todos.deleteAll([1, 2, 3]);
```

Use it when the app already has the ids to remove:

```dart
final selectedIds = [firstTodoId, secondTodoId, thirdTodoId];

await db.todos.deleteAll(selectedIds);
```

For deleting by a condition, use query deletes from the Queries guide. For
direct id-based removal, use `delete` or `deleteAll`.

## Advanced Wiring: `typedCollection`

Generated getters call `typedCollection` internally. Most apps do not need to
call it directly.

```dart
await db.todos.put(todo);
```

Use `typedCollection` only when code receives a schema dynamically and still
needs a typed collection for that schema.

```dart
Future<void> seedTodos(CindelDatabase db) async {
  final todos = db.typedCollection(TodoSchema);

  await todos.putAll([
    Todo()..title = 'Create project',
    Todo()..title = 'Write documentation',
  ]);
}
```

When a generated getter is available, prefer the getter. It is clearer for app
code and easier for readers to connect back to the model.

## Complete CRUD Example

This example shows the basic collection workflow: define a model, open the
database with its schema, create objects, read them, update one, list objects,
and delete by id.

### 1. Define The Model

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

### 2. Open The Database

```dart
final db = await Cindel.open(
  directory: appDataDirectory.path,
  schemas: [TodoSchema],
);
```

### 3. Create Objects

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

### 4. Read One Object

```dart
final saved = await db.todos.get(first.dbId);

if (saved == null) {
  throw StateError('Todo was not found');
}
```

### 5. Update An Object

To update an object, change the Dart object and write it again.

```dart
saved.completed = true;

await db.todos.put(saved);
```

The stored object for `saved.dbId` now has the updated field values.

### 6. Read Several Objects

```dart
final selected = await db.todos.getAll([first.dbId, second.dbId]);
```

The result positions match the requested ids:

```dart
final selectedFirst = selected[0];
final selectedSecond = selected[1];
```

### 7. List The Collection

```dart
final allTodos = await db.todos.all().findAll();
```

Use generated query helpers when you need a subset:

```dart
final matching = await db.todos
    .where()
    .titleEqualTo('Write API docs')
    .findAll();
```

### 8. Delete Objects

Delete one object:

```dart
await db.todos.delete(first.dbId);
```

Delete several objects:

```dart
await db.todos.deleteAll([second.dbId]);
```

### 9. Close The Database

```dart
await db.close();
```

That is the core generated collection flow: open with a schema, use the
generated collection getter, write typed objects, read typed objects, update by
writing again, and delete by id.
