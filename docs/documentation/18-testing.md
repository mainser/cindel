# Testing

Use `Cindel.openInMemory` for package tests, widget tests, and small examples.
It gives each test a temporary database while keeping the same generated typed
API used by application code.

On native platforms this is a temporary runtime database. On Web, Cindel uses a
unique browser database name for temporary work, so tests should still close the
database when they finish.

## Tests With `openInMemory`

Open an in-memory database with the schemas needed by the test:

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

Use `addTearDown(db.close)` so the test closes the database even if an
expectation fails.

Register every schema the test uses:

```dart
final db = await Cindel.openInMemory(
  schemas: [UserSchema, ProjectSchema, TaskSchema],
);
```

Use one database per test unless the test intentionally checks shared state.

## Collection Tests

Test typed CRUD through generated collections.

```dart
test('puts and gets a todo', () async {
  final db = await Cindel.openInMemory(schemas: [TodoSchema]);
  addTearDown(db.close);

  final todo = Todo()
    ..title = 'Write docs';

  await db.todos.put(todo);

  final saved = await db.todos.get(todo.dbId);

  expect(saved, isNotNull);
  expect(saved!.title, 'Write docs');
});
```

Test bulk writes:

```dart
test('stores todos in a batch', () async {
  final db = await Cindel.openInMemory(schemas: [TodoSchema]);
  addTearDown(db.close);

  final first = Todo()..title = 'One';
  final second = Todo()..title = 'Two';

  await db.todos.putAll([first, second]);

  final saved = await db.todos.getAll([first.dbId, second.dbId]);

  expect(saved.whereType<Todo>(), hasLength(2));
});
```

Test deletes:

```dart
test('deletes a todo', () async {
  final db = await Cindel.openInMemory(schemas: [TodoSchema]);
  addTearDown(db.close);

  final todo = Todo()..title = 'Remove me';
  await db.todos.put(todo);

  await db.todos.delete(todo.dbId);

  expect(await db.todos.get(todo.dbId), isNull);
});
```

## Query Tests

Test generated `where()` helpers for indexed fields:

```dart
test('finds todo by title', () async {
  final db = await Cindel.openInMemory(schemas: [TodoSchema]);
  addTearDown(db.close);

  await db.todos.put(Todo()..title = 'Ship docs');

  final found = await db.todos
      .where()
      .titleEqualTo('Ship docs')
      .findFirst();

  expect(found, isNotNull);
});
```

Test filters:

```dart
test('filters open todos', () async {
  final db = await Cindel.openInMemory(schemas: [TodoSchema]);
  addTearDown(db.close);

  await db.todos.putAll([
    Todo()
      ..title = 'Open'
      ..completed = false,
    Todo()
      ..title = 'Done'
      ..completed = true,
  ]);

  final open = await db.todos
      .filter()
      .completedEqualTo(false)
      .findAll();

  expect(open, hasLength(1));
  expect(open.single.title, 'Open');
});
```

Test counts, sorting, and pagination when they affect UI behavior:

```dart
final count = await db.todos
    .filter()
    .completedEqualTo(false)
    .count();

expect(count, 1);
```

## Sync Tests

For sync tests, use a small fake adapter. The fake should let the test control
online/offline state and returned remote changes.

```dart
final adapter = FakeSyncAdapter()..online = false;
final statuses = <CindelSyncStatus>[];

final db = await Cindel.open(
  directory: directory.path,
  schemas: [UserSchema],
  sync: CindelSyncConfig(
    adapter: adapter,
    interval: const Duration(milliseconds: 10),
    onStatusChanged: statuses.add,
  ),
);
```

Test that local data is visible even while offline:

```dart
await db.users.put(user);

expect(await db.users.get(user.dbId), isNotNull);
```

Useful sync cases:

- local write is visible immediately,
- pending write survives close and reopen,
- backend correction applies locally,
- another client can pull the change,
- delete replicates,
- remote apply does not create another local pending mutation,
- unsupported operations fail clearly.

Use short intervals in tests, but avoid relying on arbitrary sleeps when the
fake adapter can expose deterministic hooks.

## Flutter Tests

For Flutter apps, keep `cindel_flutter_libs` in dependencies even when tests
mostly use in-memory databases.

```yaml
dependencies:
  cindel: ^x.y.z
  cindel_flutter_libs: ^x.y.z
```

This keeps integration tests and platform builds on the same package graph as
the app.

Widget tests can use `openInMemory`:

```dart
testWidgets('shows todos', (tester) async {
  final db = await Cindel.openInMemory(schemas: [TodoSchema]);
  addTearDown(db.close);

  await db.todos.put(Todo()..title = 'Write docs');

  await tester.pumpWidget(
    TodoApp(database: db),
  );

  expect(find.text('Write docs'), findsOneWidget);
});
```

Keep database setup close to the test so each test controls its own data.

## Practical Guidance

Use `openInMemory` for fast package and widget tests.

Use persistent temporary directories only when the test specifically needs
close/reopen behavior, file persistence, backup files, or sync restart checks.

Register only the schemas the test needs, unless the test is intentionally
checking app-wide setup.

Prefer generated typed APIs in tests. Tests that use the same public API as the
application are easier to trust.
