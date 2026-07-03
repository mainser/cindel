# Watchers

Cindel watchers emit after committed changes. They are useful when application
state or UI should react to database writes without manually reloading every
screen.

Local writes notify watchers directly. External changes can still be detected
through polling.

```dart
const defaultCindelWatchPollInterval = Duration(milliseconds: 50);
```

## Watcher Overview

Watchers are streams. Subscribe with `listen`, update application state from
the emitted value, and cancel the subscription when the owner is disposed.

```dart
final sub = db.todos.watchCollection().listen((todos) {
  // Update application state from the latest todos.
});

await sub.cancel();
```

Most application code should prefer typed watchers:

- object watchers when one object is displayed,
- collection watchers when a whole collection is displayed,
- query watchers when a filtered or sorted result is displayed,
- lazy watchers when the caller only needs to know that something changed.

Watcher options commonly include:

- `pollInterval`: how often polling checks for changes that were not delivered
  directly,
- `fireImmediately`: whether the stream should emit the current value when the
  watcher starts.

## Object Watchers

Use `watchObject` to watch one typed object by id.

```dart
final sub = db.todos.watchObject(1).listen((todo) {
  // todo is Todo?
});
```

The emitted value is nullable. It is `null` when the object does not exist:

```dart
final sub = db.todos.watchObject(todoId).listen((todo) {
  if (todo == null) {
    // The object was deleted or does not exist.
    return;
  }

  print(todo.title);
});
```

Use object watchers for detail screens, edit screens, or small components that
care about one object.

```dart
final sub = db.todos.watchObject(
  todoId,
  fireImmediately: true,
).listen((todo) {
  currentTodo = todo;
});
```

## Lazy Object Watchers

Use `watchObjectLazy` when you only need to know that an object may have
changed.

```dart
final sub = db.todos.watchObjectLazy(1).listen((_) {
  // Object may have changed.
});
```

Lazy watchers do not emit the object itself. They are useful for invalidating a
cache, triggering a reload, or marking a view as stale.

```dart
final sub = db.todos.watchObjectLazy(todoId).listen((_) {
  cache.remove(todoId);
});
```

Use `watchObject` when you need the latest object value. Use `watchObjectLazy`
when another layer will decide whether and when to reload the object.

## Collection Watchers

Use `watchCollection` to watch the full typed collection.

```dart
final sub = db.todos.watchCollection().listen((todos) {
  // todos is List<Todo>
});
```

This is useful for small collections or screens that intentionally show every
object in a collection:

```dart
final sub = db.settings.watchCollection().listen((settings) {
  settingsState = settings;
});
```

For large collections, prefer query watchers with sorting, filtering, and
pagination so the UI observes only the result it needs.

## Lazy Collection Watchers

Use `watchCollectionLazy` when the caller only needs to know that the
collection may have changed.

```dart
final sub = db.todos.watchCollectionLazy().listen((_) {
  // Collection may have changed.
});
```

Lazy collection watchers are useful for cache invalidation:

```dart
final sub = db.todos.watchCollectionLazy().listen((_) {
  todoListCache.clear();
});
```

Use the typed collection watcher when you want the latest list emitted by the
stream. Use the lazy watcher when you only need a signal.

## Query Watchers

Use query `watch()` to observe a typed query result.

```dart
final sub = db.todos
    .filter()
    .completedEqualTo(false)
    .watch()
    .listen((todos) {
      // Matching typed snapshot.
    });
```

Query watchers are the best fit for UI lists that already have filters,
sorting, or limits:

```dart
final sub = db.todos
    .filter()
    .completedEqualTo(false)
    .sortByCreatedAt(order: CindelSortOrder.descending)
    .limit(20)
    .watch()
    .listen((todos) {
      openTodos = todos;
    });
```

Use query watchers instead of watching the whole collection when a screen only
shows one subset of the data.

## Lazy Query Watchers

Use query `watchLazy()` when a matching query may have changed but the caller
does not need the typed result from the stream.

```dart
final sub = db.todos
    .filter()
    .completedEqualTo(false)
    .watchLazy()
    .listen((_) {
      // Matching query may have changed.
    });
```

This is useful when the app has its own cache or state management layer:

```dart
final sub = db.todos
    .filter()
    .completedEqualTo(false)
    .watchLazy()
    .listen((_) {
      openTodoCache.invalidate();
    });
```

Use `watch()` for direct UI snapshots. Use `watchLazy()` for invalidation
signals.

## Change-Set Watcher

`watchCollectionChanges` emits lower-level change sets for a collection name.
It is useful for advanced cache invalidation and tooling.

```dart
final sub = db.watchCollectionChanges('todos').listen((change) {
  print(change.documentIds);
});
```

`CindelChangeSet` exposes:

- `collection`
- `documentIds`
- `documents`
- `hasUnknownDocuments`
- `isExternal`
- `revision`
- `mayAffectDocument(id)`

Example:

```dart
final sub = db.watchCollectionChanges('todos').listen((change) {
  if (change.hasUnknownDocuments) {
    todoCache.clear();
    return;
  }

  for (final id in change.documentIds) {
    todoCache.remove(id);
  }
});
```

Most applications should prefer typed object, collection, and query watchers.
Use change-set watchers when you need to integrate with a custom cache or
debugging tool.

## UI Usage Patterns

Create watchers at the same lifecycle level as the UI state they update.
Cancel them when that state is disposed.

```dart
late final StreamSubscription<List<Todo>> sub;

void start() {
  sub = db.todos.watchCollection().listen((todos) {
    state = todos;
  });
}

Future<void> dispose() async {
  await sub.cancel();
}
```

Prefer query watchers for screens:

```dart
final sub = db.todos
    .filter()
    .completedEqualTo(false)
    .sortByCreatedAt(order: CindelSortOrder.descending)
    .watch()
    .listen((todos) {
      screenState = todos;
    });
```

Prefer object watchers for details:

```dart
final sub = db.todos.watchObject(todoId).listen((todo) {
  detailState = todo;
});
```

Prefer lazy watchers for cache invalidation:

```dart
final sub = db.todos.watchCollectionLazy().listen((_) {
  cache.clear();
});
```

Keep watcher callbacks small. Derive UI state from the emitted data, and avoid
long-running work inside the listener. If a listener starts asynchronous work,
make sure the owning UI state can ignore stale results after disposal.
