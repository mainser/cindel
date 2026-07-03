# Queries

Cindel queries are the normal way to read, count, update, and delete groups of
typed objects. Generated query builders let application code start from a
collection, add indexed lookups or filters, optionally sort and page the result,
and then execute the query with a result method.

This guide covers the core query flow: `where`, `filter`, result methods,
sorting, pagination, distinct results, dynamic query modifiers, query deletes,
query updates, and common examples.

## Query Overview

Queries usually start from a typed collection:

```dart
final todos = await db.todos.all().findAll();
```

For a model like this:

```dart
@Collection(name: 'todos')
class Todo {
  Id dbId = autoIncrement;

  @Index()
  late String title;

  bool completed = false;

  @Index()
  DateTime createdAt = DateTime.now().toUtc();

  @Index(type: CindelIndexType.multiEntry, caseSensitive: false)
  List<String> tags = const [];
}
```

the generated API can expose queries such as:

```dart
final open = await db.todos
    .filter()
    .completedEqualTo(false)
    .findAll();

final exact = await db.todos
    .where()
    .titleEqualTo('Ship docs')
    .findFirst();

final recent = await db.todos
    .where()
    .createdAtBetween(start, end)
    .findAll();
```

The usual query shape is:

1. Start from `all()`, `where()`, or `filter()`.
2. Add conditions.
3. Add sorting, offset, limit, or distinct if needed.
4. Execute with `findAll()`, `findFirst()`, `count()`, `deleteFirst()`,
   `deleteAll()`, `updateFirst(...)`, or `updateAll(...)`.

## `where`

Use `where()` for indexed fields and composite indexes.

```dart
final todo = await db.todos
    .where()
    .titleEqualTo('Ship docs')
    .findFirst();
```

Generated `where()` helpers depend on the indexes declared in your model.

An indexed string field can support equality:

```dart
final docs = await db.todos
    .where()
    .titleEqualTo('Write docs')
    .findAll();
```

An indexed ordered field can support range-style helpers:

```dart
final createdThisWeek = await db.todos
    .where()
    .createdAtBetween(startOfWeek, endOfWeek)
    .findAll();
```

A multi-entry index can support list membership:

```dart
final urgent = await db.todos
    .where()
    .tagsContains('urgent')
    .findAll();
```

Use `where()` when the model has an index for the lookup you need. This keeps
the query aligned with the indexed access paths generated for the collection.

## `filter`

Use `filter()` for general predicates over persisted fields.

```dart
final open = await db.todos
    .filter()
    .completedEqualTo(false)
    .findAll();
```

Filters can be used without an indexed lookup:

```dart
final done = await db.todos
    .filter()
    .completedEqualTo(true)
    .findAll();
```

Filters can also be added after a `where()` query:

```dart
final urgentOpen = await db.todos
    .where()
    .tagsContains('urgent')
    .filter()
    .completedEqualTo(false)
    .findAll();
```

In that example, the indexed tag lookup narrows the candidate set first, and
the filter adds the non-indexed condition.

Use `filter()` when you need predicates that are not necessarily backed by a
field index, or when you want to combine additional conditions after `where()`.

## Result Methods

Result methods execute the query.

```dart
final all = await query.findAll();
final first = await query.findFirst();
final count = await query.count();
```

### `findAll`

`findAll()` returns every matching typed object.

```dart
final todos = await db.todos
    .filter()
    .completedEqualTo(false)
    .findAll();
```

Use `findAll()` when the application needs the actual objects:

```dart
for (final todo in todos) {
  print(todo.title);
}
```

For large collections, combine `findAll()` with sorting and pagination.

### `findFirst`

`findFirst()` returns the first matching object, or `null` when no object
matches.

```dart
final todo = await db.todos
    .where()
    .titleEqualTo('Ship docs')
    .findFirst();

if (todo == null) {
  // No matching todo exists.
}
```

Use `findFirst()` for single-result lookups or screens that only need one
matching object.

### `count`

`count()` returns the number of matching objects.

```dart
final openCount = await db.todos
    .filter()
    .completedEqualTo(false)
    .count();
```

Use `count()` when you need a number rather than the objects themselves:

```dart
final hasOpenWork = openCount > 0;
```

## Sorting

Generated sort helpers are available for persisted fields.

```dart
final newest = await db.todos
    .all()
    .sortByCreatedAt(order: CindelSortOrder.descending)
    .thenByTitle()
    .findAll();
```

Use `sortBy...` for the primary sort and `thenBy...` for secondary sorts.

```dart
final ordered = await db.todos
    .all()
    .sortByCompleted()
    .thenByCreatedAt(order: CindelSortOrder.descending)
    .findAll();
```

The lower-level query API also accepts persisted field names:

```dart
final sorted = await db.todos
    .all()
    .sortBy('createdAt', order: CindelSortOrder.descending)
    .thenBy('title')
    .findAll();
```

Use generated sort helpers when available because they are easier to rename
with Dart fields. Use field-name sorting for advanced or dynamic code that
already works with persisted field names.

## Offset And Limit

Use `offset` and `limit` for pagination.

```dart
final page = await db.todos
    .all()
    .sortByCreatedAt(order: CindelSortOrder.descending)
    .offset(20)
    .limit(10)
    .findAll();
```

`offset` skips matching results after filtering, sorting, and distinct.
`limit` caps the number of returned results after the offset.

Example helper:

```dart
Future<List<Todo>> loadTodoPage({
  required int page,
  required int pageSize,
}) {
  return db.todos
      .all()
      .sortByCreatedAt(order: CindelSortOrder.descending)
      .offset(page * pageSize)
      .limit(pageSize)
      .findAll();
}
```

Offsets and limits must not be negative.

## Distinct

Use `distinct` when a query should keep only the first result for each distinct
field value or field tuple.

Generated distinct helpers are available for persisted fields:

```dart
final distinctTitles = await db.todos
    .all()
    .distinctByTitle()
    .findAll();
```

Use `distinctByFields` when distinctness is based on multiple persisted fields:

```dart
final distinctPairs = await db.todos
    .all()
    .distinctByFields(['completed', 'title'])
    .findAll();
```

Distinct is applied before offset and limit. Combine it with sorting when you
care which object is kept for each distinct value:

```dart
final latestByTitle = await db.todos
    .all()
    .sortByCreatedAt(order: CindelSortOrder.descending)
    .distinctByTitle()
    .findAll();
```

## Dynamic Query Modifiers

Dynamic query modifiers help build queries from optional user input without
splitting code into many branches.

### `optional`

Use `optional` when a filter should only be applied when a condition is true.

```dart
final filtered = await db.todos
    .filter()
    .optional(search.isNotEmpty, (q) => q.titleContains(search))
    .findAll();
```

This is useful for search boxes:

```dart
Future<List<Todo>> searchTodos(String search) {
  return db.todos
      .filter()
      .optional(search.trim().isNotEmpty, (q) {
        return q.titleContains(search.trim());
      })
      .findAll();
}
```

When the first argument is `false`, `optional` returns the query unchanged.

### `anyOf`

Use `anyOf` for OR-style repeated filters.

```dart
final withAnyTag = await db.todos
    .filter()
    .anyOf(selectedTags, (q, tag) => q.tagsElementEqualTo(tag))
    .findAll();
```

This matches todos that have at least one of the selected tags.

```dart
final selectedTags = ['docs', 'urgent'];

final todos = await db.todos
    .filter()
    .anyOf(selectedTags, (q, tag) {
      return q.tagsElementEqualTo(tag);
    })
    .findAll();
```

Empty `anyOf` matches nothing.

### `allOf`

Use `allOf` for AND-style repeated filters.

```dart
final withAllWords = await db.todos
    .filter()
    .allOf(requiredWords, (q, word) => q.titleContains(word))
    .findAll();
```

This matches todos where every generated condition is true.

```dart
final requiredWords = ['api', 'docs'];

final todos = await db.todos
    .filter()
    .allOf(requiredWords, (q, word) {
      return q.titleContains(word);
    })
    .findAll();
```

Empty `allOf` is a no-op.

The callback passed to `anyOf` or `allOf` should add filters. Do not use it to
change sorting, distinct, pagination, projection, or the query source.

## Query Deletes

Use query deletes when objects should be removed by a query condition instead
of by known ids.

Delete the first matching object:

```dart
final deletedOne = await db.todos
    .filter()
    .completedEqualTo(true)
    .deleteFirst();
```

`deleteFirst()` returns `true` when an object was deleted and `false` when no
object matched.

Delete every matching object:

```dart
final deletedCount = await db.todos
    .filter()
    .completedEqualTo(true)
    .deleteAll();
```

`deleteAll()` returns the number of deleted objects.

Example cleanup:

```dart
final removed = await db.todos
    .where()
    .createdAtLessThan(cutoff)
    .filter()
    .completedEqualTo(true)
    .deleteAll();
```

Use collection `delete` or `deleteAll` when you already have ids. Use query
deletes when the removal condition is expressed as a query.

## Query Updates

Use query updates when matching objects should be updated by a persisted-field
map.

Update the first matching object:

```dart
final updatedOne = await db.todos
    .where()
    .titleEqualTo('Ship docs')
    .updateFirst({'completed': true});
```

`updateFirst()` returns `true` when an object was updated and `false` when no
object matched.

Update every matching object:

```dart
final updatedCount = await db.todos
    .filter()
    .completedEqualTo(false)
    .updateAll({'completed': true});
```

`updateAll()` returns the number of updated objects.

The update map uses persisted field names:

```dart
await db.todos
    .where()
    .titleEqualTo('Ship docs')
    .updateFirst({'completed': true});
```

Updating the id field is rejected.

Values in the update map must already use Cindel-compatible stored shapes:
`null`, `bool`, `int`, finite `double`, `String`, lists, and string-keyed maps.

For converted fields such as `DateTime`, `Duration`, or enums, prefer typed
object writes unless you intentionally want to write the stored scalar
representation:

```dart
final todos = await db.todos
    .filter()
    .completedEqualTo(false)
    .findAll();

for (final todo in todos) {
  todo.completed = true;
}

await db.todos.putAll(todos);
```

## Common Query Examples

### Find one object by indexed field

```dart
final todo = await db.todos
    .where()
    .titleEqualTo('Ship docs')
    .findFirst();
```

### Find open todos

```dart
final openTodos = await db.todos
    .filter()
    .completedEqualTo(false)
    .findAll();
```

### Find urgent open todos

```dart
final urgentOpen = await db.todos
    .where()
    .tagsContains('urgent')
    .filter()
    .completedEqualTo(false)
    .findAll();
```

### Load the newest page

```dart
final newest = await db.todos
    .all()
    .sortByCreatedAt(order: CindelSortOrder.descending)
    .limit(20)
    .findAll();
```

### Search only when input is present

```dart
final results = await db.todos
    .filter()
    .optional(search.isNotEmpty, (q) => q.titleContains(search))
    .findAll();
```

### Count completed todos

```dart
final completedCount = await db.todos
    .filter()
    .completedEqualTo(true)
    .count();
```

### Mark a matching todo as completed

```dart
final updated = await db.todos
    .where()
    .titleEqualTo('Ship docs')
    .updateFirst({'completed': true});
```

### Delete completed todos

```dart
final deleted = await db.todos
    .filter()
    .completedEqualTo(true)
    .deleteAll();
```
