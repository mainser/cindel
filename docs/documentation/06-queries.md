# Queries

Cindel queries let an app read, count, update, or delete groups of typed
objects. A query starts from a generated collection, adds conditions or result
options, and then runs with a result method such as `findAll()`,
`findFirst()`, or `count()`.

This guide covers the core query flow: `all`, `where`, `filter`, result
methods, sorting, pagination, distinct results, dynamic query modifiers, query
deletes, query updates, and common examples. Detailed predicate behavior lives
in the Filters guide.

## Query Flow

Most queries follow the same shape:

1. Start from `all()`, `where()`, or `filter()`.
2. Add conditions.
3. Add sorting, offset, limit, or distinct if needed.
4. Execute the query.

For example:

```dart
final openTodos = await db.todos
    .filter()
    .completedEqualTo(false)
    .findAll();
```

Given this model:

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
final exact = await db.todos
    .where()
    .titleEqualTo('Ship docs')
    .findFirst();

final recent = await db.todos
    .where()
    .createdAtBetween(start, end)
    .findAll();

final urgentOpen = await db.todos
    .where()
    .tagsContains('urgent')
    .filter()
    .completedEqualTo(false)
    .findAll();
```

The method names come from your model fields and indexes. If a helper does not
exist, check whether the field is persisted, whether it is indexed when using
`where()`, and whether generated code is up to date.

## Starting From `all`

Use `all()` when the query should start with the whole collection.

```dart
final todos = await db.todos.all().findAll();
```

`all()` is useful for full lists, counts, sorted pages, maintenance screens,
and operations that should consider every object.

```dart
final total = await db.todos.all().count();

final newest = await db.todos
    .all()
    .sortByCreatedAt(order: CindelSortOrder.descending)
    .limit(20)
    .findAll();
```

For large collections, avoid loading everything unless that is really what the
screen or command needs. Add sorting and pagination when you only need a page.

## Starting From `where`

Use `where()` for indexed fields and composite indexes.

```dart
final todo = await db.todos
    .where()
    .titleEqualTo('Ship docs')
    .findFirst();
```

Generated `where()` helpers depend on indexes declared in the model.

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

Use `where()` when the lookup is part of how you expect to find records often:
by id-like fields, natural keys, dates, tags, categories, slugs, or other
indexed values.

## Starting From `filter`

Use `filter()` for predicates over persisted fields.

```dart
final open = await db.todos
    .filter()
    .completedEqualTo(false)
    .findAll();
```

Filters can be used on their own:

```dart
final done = await db.todos
    .filter()
    .completedEqualTo(true)
    .findAll();
```

Filters can also be added after `where()`:

```dart
final urgentOpen = await db.todos
    .where()
    .tagsContains('urgent')
    .filter()
    .completedEqualTo(false)
    .findAll();
```

In that example, the indexed tag lookup chooses the candidate set and the
filter adds another condition.

Use the Filters guide for field predicates, nested embedded paths, and boolean
composition.

## Result Methods

Result methods execute the query. Until you call one, you are still building
the query.

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

Use `findAll()` when the app needs the objects themselves:

```dart
for (final todo in todos) {
  print(todo.title);
}
```

For large result sets, combine it with sorting and pagination.

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

Use `findFirst()` for single-result lookups and screens that only need one
matching object. It requests at most one result, including for property and
multi-property projections. Existing offset and distinct are preserved;
`limit(0).findFirst()` returns null. A filter or sort may still require examining
many candidates before that first result is known.

### `count`

`count()` returns the number of matching objects **in the query window**:
filters, distinct, offset, and limit still apply. It is not the total count
before pagination. Remove the window modifiers when that is what you need.
Generated native plans use the backend count operation instead of hydrating
all returned objects; distinct and less direct execution paths can need
additional tracking or materialization. Property `count()` instead counts
non-null projected values.

```dart
final openCount = await db.todos
    .filter()
    .completedEqualTo(false)
    .count();
```

Use `count()` when the app needs a number, not the objects:

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

Prefer generated sort helpers when the field is known in code. Use field-name
sorting for dynamic code that already works with persisted field names.

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
`limit` caps how many results are returned after the offset.

Example:

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

### Stable Pages And Totals

Add the ID as a tie-breaker when the first sort field can repeat. Deriving a
page does not mutate its base query:

```dart
final base = db.todos
    .filter()
    .completedEqualTo(false)
    .sortByCreatedAt(order: CindelSortOrder.descending)
    .thenByDbId();

await db.readTxn(() async {
  final total = await base.count();
  final page = await base.offset(20).limit(10).findAll();
  // total and page describe the same database snapshot.
});
```

Count before adding the page window when you want the total number of matches;
`base.offset(20).limit(10).count()` counts only that window. A stable sort does
not freeze data between separate calls: inserts or deletes can shift later
offset pages. For a consistent maintenance scan, keep the loop inside a
`readTxn` and use [ID cursor pages](14-backup_and_advanced_helpers.md#documentidspage).

## Distinct

Use `distinct` when the query should keep only the first result for each
distinct field value or field tuple.

Generated distinct helpers are available for persisted fields:

```dart
final distinctTitles = await db.todos
    .all()
    .distinctByTitle()
    .findAll();
```

Use `distinctByFields` when distinctness depends on multiple persisted fields:

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

### Distinct Equality And Ordering

Distinct compares structured field values and tuples, including list contents.
Field boundaries and nulls are preserved; delimiter-like strings or a hash
collision do not make unrelated tuples equal. Case-insensitive modifiers still
apply where requested.

Sorting happens before distinct, then offset and limit. Add the ID as a final
sort key when ties need a deterministic representative or stable pagination:

```dart
final latestByTitle = await db.todos
    .all()
    .sortByCreatedAt(order: CindelSortOrder.descending)
    .thenByDbId()
    .distinctByTitle()
    .limit(20)
    .findAll();
```

### Execution And Memory

These are internal optimizations; applications keep using generated queries:

- MDBX can scan the ID cursor in either direction for limited `all()` queries
  ordered only by ID, including filters, without distinct. It stops after the
  requested matching window is complete or the cursor is exhausted.
- MDBX can stream a limited integer-index range ordered ascending by the
  indexed field and then ID, without distinct. This is not a general ordered
  scan for arbitrary indexes or descending composite orders.
- Eligible limited MDBX sorts that include the ID retain at most
  `offset + limit` candidates using top-k selection. They can still scan all
  candidates; a large offset increases retained memory.
- Unsorted MDBX distinct processes candidates progressively, retains distinct
  keys rather than discarded documents, and can stop at the limit. The key set
  still grows with the number of distinct values examined.
- MDBX ID-only result plans avoid copying full documents. Filters and ordering
  may still require reading document fields.

The selected path depends on the complete query. A limit bounds returned rows,
not necessarily scanned rows or total backend memory. Result lists, distinct
keys, and backend caches have costs beyond any bounded candidate buffer.

## Dynamic Query Modifiers

Dynamic query modifiers help build queries from optional user input without
duplicating the whole query in several branches.

### `optional`

Use `optional` when a condition should only be applied sometimes.

```dart
final filtered = await db.todos
    .filter()
    .optional(search.isNotEmpty, (q) => q.titleContains(search))
    .findAll();
```

This is useful for search boxes:

```dart
Future<List<Todo>> searchTodos(String search) {
  final text = search.trim();

  return db.todos
      .filter()
      .optional(text.isNotEmpty, (q) => q.titleContains(text))
      .findAll();
}
```

When the first argument is `false`, `optional` returns the query unchanged.

### `anyOf`

Use `anyOf` for OR-style repeated filters.

```dart
final selectedTags = ['docs', 'urgent'];

final todos = await db.todos
    .filter()
    .anyOf(selectedTags, (q, tag) {
      return q.tagsElementEqualTo(tag);
    })
    .findAll();
```

This matches todos that have at least one of the selected tags. Empty `anyOf`
matches nothing.

### `allOf`

Use `allOf` for AND-style repeated filters.

```dart
final requiredWords = ['api', 'docs'];

final todos = await db.todos
    .filter()
    .allOf(requiredWords, (q, word) {
      return q.titleContains(word);
    })
    .findAll();
```

This matches todos where every generated condition is true. Empty `allOf` is a
no-op.

The callback passed to `anyOf` or `allOf` should only add filters. Do not use
it to change sorting, distinct, pagination, projection, or the query source.

## Query Deletes

Use query deletes when objects should be removed by a condition instead of by
known ids.

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
deletes when the removal is based on a query condition.

## Query Updates

Use query updates when matching objects should be updated by persisted field
names.

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

Both operations respect the query's offset and limit. The offset skips matching
objects; `updateFirst()` then updates at most one object, while `updateAll()`
updates the selected window. A zero limit updates nothing. These rules are the
same in MDBX, SQLite native, and Web, including when a changed field is used by
the filter.

MDBX's direct scan for unsorted, non-distinct updates over the all-documents
source stops before reading another row once the window is complete, even if
later rows would not match. This path applies outside an explicit `writeTxn`
when the changed fields do not participate in indexes. A zero limit performs
no cursor reads on this path; field and filter validation still runs.

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

### Find One Object By Indexed Field

```dart
final todo = await db.todos
    .where()
    .titleEqualTo('Ship docs')
    .findFirst();
```

### Find Open Todos

```dart
final openTodos = await db.todos
    .filter()
    .completedEqualTo(false)
    .findAll();
```

### Find Urgent Open Todos

```dart
final urgentOpen = await db.todos
    .where()
    .tagsContains('urgent')
    .filter()
    .completedEqualTo(false)
    .findAll();
```

### Load The Newest Page

```dart
final newest = await db.todos
    .all()
    .sortByCreatedAt(order: CindelSortOrder.descending)
    .limit(20)
    .findAll();
```

### Search Only When Input Is Present

```dart
final text = search.trim();

final results = await db.todos
    .filter()
    .optional(text.isNotEmpty, (q) => q.titleContains(text))
    .findAll();
```

### Count Completed Todos

```dart
final completedCount = await db.todos
    .filter()
    .completedEqualTo(true)
    .count();
```

### Mark A Matching Todo As Completed

```dart
final updated = await db.todos
    .where()
    .titleEqualTo('Ship docs')
    .updateFirst({'completed': true});
```

### Delete Completed Todos

```dart
final deleted = await db.todos
    .filter()
    .completedEqualTo(true)
    .deleteAll();
```
