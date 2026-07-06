# Watchers

Cindel watchers are streams that emit after committed database changes. They
are useful when app state or UI should react to local database writes without
manually reloading every screen.

Local writes notify watchers directly. External changes can still be detected
through polling.

```dart
const defaultCindelWatchPollInterval = Duration(milliseconds: 50);
```

Most app code should use typed watchers:

- object watchers for detail screens,
- collection watchers for small full-collection screens,
- query watchers for filtered, sorted, or paginated lists,
- lazy watchers when the app only needs an invalidation signal.

## Watcher Basics

Watchers are Dart streams. Subscribe with `listen`, update app state from the
emitted value, and cancel the subscription when the owner is disposed.

```dart
final sub = db.todos.watchCollection().listen((todos) {
  // Update app state from the latest todos.
});

await sub.cancel();
```

Common options include:

- `pollInterval`: how often polling checks for changes that were not delivered
  directly,
- `fireImmediately`: whether the stream emits the current value when the
  watcher starts.

Create watchers at the same lifecycle level as the state they update. For
example, a screen-level watcher should be cancelled when that screen is
disposed.

## Object Watchers

Use `watchObject` to watch one typed object by id.

```dart
final sub = db.todos.watchObject(todoId).listen((todo) {
  // todo is Todo?
});
```

The emitted value is nullable. It is `null` when the object does not exist or
has been deleted:

```dart
final sub = db.todos.watchObject(todoId).listen((todo) {
  if (todo == null) {
    detailState = null;
    return;
  }

  detailState = todo;
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
final sub = db.todos.watchObjectLazy(todoId).listen((_) {
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

Use `watchObject` when the listener needs the latest object value. Use
`watchObjectLazy` when another layer will decide whether and when to reload.

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

For large collections, prefer query watchers with filtering, sorting, and
limits so the UI observes only the result it needs.

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

Use `watchCollection` when you want the latest list emitted by the stream. Use
`watchCollectionLazy` when you only need a signal.

## Query Watchers

Use query `watch()` to observe a typed query result.

```dart
final sub = db.todos
    .filter()
    .completedEqualTo(false)
    .watch()
    .listen((todos) {
      openTodos = todos;
    });
```

Query watchers are usually the best fit for UI lists because screens often
show a subset of data:

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
shows filtered, sorted, or paginated data.

## Lazy Query Watchers

Use query `watchLazy()` when a matching query may have changed but the listener
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

Most apps should prefer typed object, collection, and query watchers. Use
change-set watchers when you need to integrate with a custom cache, diagnostic
tool, or advanced invalidation layer.

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

Prefer query watchers for list screens:

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

Prefer object watchers for detail screens:

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

Keep watcher callbacks small. Derive state from the emitted data, and avoid
long-running work inside the listener. If a listener starts asynchronous work,
make sure the owning UI state can ignore stale results after disposal.
