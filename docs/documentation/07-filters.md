# Filters

Filters describe conditions that stored objects must satisfy. In normal app
code, the easiest and safest option is to use generated `filter()` helpers
because they follow your Dart model fields.

Use the lower-level `CindelFilter` builder when you need to build filters
dynamically from runtime data, such as saved searches, configurable admin
screens, or user-selected fields.

This page covers field predicates, embedded paths, boolean composition, and
practical guidance for choosing generated helpers or dynamic filters.

## Generated Filters

Generated filters start from a typed collection:

```dart
final open = await db.todos
    .filter()
    .completedEqualTo(false)
    .findAll();
```

For a model like this:

```dart
@Collection(name: 'todos')
class Todo {
  Id dbId = autoIncrement;

  late String title;
  bool completed = false;
  List<String> tags = const [];
}
```

the generated filter API can expose helpers based on persisted fields:

```dart
final docs = await db.todos
    .filter()
    .titleContains('docs')
    .findAll();

final open = await db.todos
    .filter()
    .completedEqualTo(false)
    .findAll();
```

Prefer generated helpers when the field and predicate are known at compile
time. They are easier to read, follow Dart names, and use the generated
conversions for your model.

## Dynamic Filters

`CindelFilter` builds predicates from persisted field names.

```dart
final predicate = CindelFilter.field('completed').equalTo(false);

final open = await db.todos
    .all()
    .whereMatches(predicate)
    .findAll();
```

Use `CindelFilter.field(...)` when the field name or predicate is selected at
runtime:

```dart
CindelFilter buildTodoPredicate(String field, Object? value) {
  return CindelFilter.field(field).equalTo(value);
}
```

When using `CindelFilter`, pass persisted field names. If a model uses `@Name`,
the persisted field name may be different from the Dart field name. Generated
helpers avoid that problem in normal app code.

## Field Predicates

Available dynamic field predicates include:

- `equalTo`
- `greaterThan`
- `greaterThanOrEqualTo`
- `lessThan`
- `lessThanOrEqualTo`
- `between`
- `contains`
- `startsWith`
- `endsWith`
- `isEmpty`
- `isNotEmpty`
- `lengthEqualTo`
- `lengthLessThan`
- `lengthGreaterThan`
- `lengthBetween`

Examples:

```dart
final highPriority = await db.tasks
    .all()
    .whereMatches(CindelFilter.field('priority').greaterThan(5))
    .findAll();

final titledDocs = await db.todos
    .all()
    .whereMatches(CindelFilter.field('title').contains('docs'))
    .findAll();

final tagged = await db.todos
    .all()
    .whereMatches(CindelFilter.field('tags').isNotEmpty())
    .findAll();
```

If you do not need runtime field selection, use the generated version:

```dart
final titledDocs = await db.todos
    .filter()
    .titleContains('docs')
    .findAll();
```

## Embedded Paths

Use nested generated filters when data is stored inside embedded objects.

```dart
final messages = await db.emails
    .filter()
    .sender((sender) {
      return sender.addressEqualTo('ada@example.com');
    })
    .findAll();
```

For dynamic embedded paths, use `CindelFilter.path`.

```dart
final matches = await db.emails
    .all()
    .whereMatches(
      CindelFilter.path(['sender', 'address']).equalTo('ada@example.com'),
    )
    .findAll();
```

When a path reaches a list, Cindel evaluates the remaining path against each
element and matches when any element satisfies the predicate.

```dart
final matches = await db.emails
    .all()
    .whereMatches(
      CindelFilter.path(['recipients', 'address']).equalTo('mary@example.com'),
    )
    .findAll();
```

Use generated embedded filters when the path is part of the model API:

```dart
final sentToMary = await db.emails
    .filter()
    .recipientsElement((recipient) {
      return recipient.addressEqualTo('mary@example.com');
    })
    .findAll();
```

Use `CindelFilter.path(...)` when a path must be assembled dynamically.

## Boolean Composition

Use `CindelFilter.all` for AND-style composition. Every predicate must match.

```dart
final predicate = CindelFilter.all([
  CindelFilter.field('completed').equalTo(false),
  CindelFilter.field('title').contains('docs'),
]);

final matches = await db.todos
    .all()
    .whereMatches(predicate)
    .findAll();
```

Use `CindelFilter.any` for OR-style composition. At least one predicate must
match.

```dart
final predicate = CindelFilter.any([
  CindelFilter.field('title').contains('release'),
  CindelFilter.field('title').contains('docs'),
]);

final matches = await db.todos
    .all()
    .whereMatches(predicate)
    .findAll();
```

Use `CindelFilter.not` to invert a predicate.

```dart
final notDone = CindelFilter.not(
  CindelFilter.field('completed').equalTo(true),
);

final open = await db.todos
    .all()
    .whereMatches(notDone)
    .findAll();
```

For repeated generated conditions, query modifiers such as `anyOf` and `allOf`
are often easier when the field helpers are known:

```dart
final matches = await db.todos
    .filter()
    .anyOf(words, (q, word) => q.titleContains(word))
    .findAll();
```

Use boolean `CindelFilter` composition when you need to build a predicate tree
directly.

## Generated Filters Vs `CindelFilter`

Use generated filters for normal application code:

```dart
final open = await db.todos
    .filter()
    .completedEqualTo(false)
    .findAll();
```

Use `where()` for indexed lookups and `filter()` for additional predicates:

```dart
final urgentOpen = await db.todos
    .where()
    .tagsContains('urgent')
    .filter()
    .completedEqualTo(false)
    .findAll();
```

Use `CindelFilter` when the app needs dynamic filter construction:

- saved search definitions,
- configurable admin screens,
- user-selected fields,
- advanced tooling,
- filter builders that are not known at compile time.

When using dynamic filters, keep values compatible with the persisted field
shape. For converted types such as enums, `DateTime`, or `Duration`, generated
helpers are usually safer because they use the model's generated conversions.

Avoid using filters as a substitute for indexes when lookup performance
matters. Add indexes to fields that frequently narrow large collections, then
start the query with `where()` and add filters for the remaining conditions.
