# Filters

Filters describe predicates that a document must satisfy. In most application
code, you should use generated `filter()` helpers because they are typed and
follow the Dart model fields. When you need dynamic filter construction, use
the public `CindelFilter` builder.

This page covers field predicates, nested paths, boolean composition, and
practical guidelines for choosing between generated filters and dynamic
filters.

## Field Predicates

Generated filter helpers are available from a typed collection:

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

the generated filter API can expose helpers based on the persisted fields:

```dart
final docs = await db.todos
    .filter()
    .titleContains('docs')
    .findAll();
```

The lower-level `CindelFilter` API uses persisted field names:

```dart
final predicate = CindelFilter.field('completed').equalTo(false);

final open = await db.todos
    .all()
    .whereMatches(predicate)
    .findAll();
```

Available field predicates include:

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

Prefer generated helpers when the filter is known at compile time:

```dart
final titledDocs = await db.todos
    .filter()
    .titleContains('docs')
    .findAll();
```

Use `CindelFilter.field(...)` when the field name or predicate is selected at
runtime.

## Nested Paths

Use nested filters when data is stored inside embedded objects.

Generated helpers are the easiest option:

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

Use `CindelFilter.path(...)` when a path must be assembled dynamically, such as
from search configuration or a user-selected field.

## Boolean Composition

Use `CindelFilter.all` for AND-style composition:

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

Use `CindelFilter.any` for OR-style composition:

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

Use `CindelFilter.not` to invert a predicate:

```dart
final notDone = CindelFilter.not(
  CindelFilter.field('completed').equalTo(true),
);

final open = await db.todos
    .all()
    .whereMatches(notDone)
    .findAll();
```

For repeated dynamic conditions, generated query modifiers such as `anyOf` and
`allOf` are often easier when the field helpers are known:

```dart
final matches = await db.todos
    .filter()
    .anyOf(words, (q, word) => q.titleContains(word))
    .findAll();
```

Use boolean `CindelFilter` composition when you need to build a predicate tree
directly.

## Best Practices

Prefer generated filter helpers for normal application code:

```dart
final open = await db.todos
    .filter()
    .completedEqualTo(false)
    .findAll();
```

Use `where()` for indexed lookups and `filter()` for general predicates:

```dart
final urgentOpen = await db.todos
    .where()
    .tagsContains('urgent')
    .filter()
    .completedEqualTo(false)
    .findAll();
```

Use `CindelFilter` for dynamic builders, saved search definitions, configurable
admin screens, or advanced tooling where field names and predicates are not
known until runtime.

When using `CindelFilter`, pass persisted field names. If your model uses
`@Name`, the persisted field name may be different from the Dart field name.
Generated helpers avoid that problem in normal app code.

Keep filter values compatible with the persisted field shape. For converted
types such as enums, `DateTime`, or `Duration`, generated helpers are usually
the safer choice because they use the model's generated conversions.

Avoid using filters as a substitute for indexes when lookup performance
matters. Add indexes to fields that are frequently used to narrow large
collections, then start the query with `where()` and add filters for the
remaining conditions.
