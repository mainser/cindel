# Projections And Aggregates

Most queries return full typed objects. That is the right choice when the app
needs to display, edit, or write those objects back.

Projection queries are different: they read selected fields instead of
hydrating full objects. Aggregate queries calculate summary values such as
counts, minimums, maximums, sums, and averages.

Use projections when a screen only needs a small part of each object. Use
aggregates when the app needs a summary value rather than the matching records.

## Single-Property Projections

Generated property helpers project one persisted field.

```dart
final titles = await db.todos
    .all()
    .titleProperty()
    .findAll();
```

The result is a typed list of property values:

```dart
for (final title in titles) {
  print(title);
}
```

Use `findFirst()` when only the first projected value is needed:

```dart
final firstTitle = await db.todos
    .all()
    .titleProperty()
    .findFirst();
```

Property queries can be combined with normal query conditions:

```dart
final openTitles = await db.todos
    .filter()
    .completedEqualTo(false)
    .sortByCreatedAt(order: CindelSortOrder.descending)
    .titleProperty()
    .findAll();
```

The lower-level field-name API is also available:

```dart
final titles = await db.todos
    .all()
    .property<String>('title')
    .findAll();
```

Prefer generated property helpers when the field is known in code. Use
`property<T>('fieldName')` for dynamic code that already works with persisted
field names.

## Multi-Property Projections

Use `properties(...)` to project several persisted fields at once.

```dart
final rows = await db.todos
    .all()
    .properties(['dbId', 'title'])
    .findAll();
```

Rows are returned as `CindelDocument` values:

```dart
typedef CindelDocument = Map<String, Object?>;
```

That means each row is map-shaped:

```dart
for (final row in rows) {
  final id = row['dbId'] as int;
  final title = row['title'] as String;

  print('$id: $title');
}
```

Use multi-property projections when you need lightweight rows for a table,
autocomplete list, export preview, or summary screen.

The field names passed to `properties(...)` are persisted field names. If a
model uses `@Name`, the persisted name can differ from the Dart field name.
Generated single-property helpers avoid that naming issue when the field is
known at compile time.

## Aggregates

Aggregate helpers are available from property queries.

```dart
final count = await db.todos.all().createdAtProperty().count();
final min = await db.todos.all().createdAtProperty().min();
final max = await db.todos.all().createdAtProperty().max();
final sum = await db.orders.all().totalCentsProperty().sum();
final average = await db.orders.all().totalCentsProperty().average();
```

`count()` returns the number of non-null projected values:

```dart
final datedCount = await db.todos
    .all()
    .createdAtProperty()
    .count();
```

`min()` and `max()` require comparable values:

```dart
final firstCreatedAt = await db.todos
    .all()
    .createdAtProperty()
    .min();

final lastCreatedAt = await db.todos
    .all()
    .createdAtProperty()
    .max();
```

`sum()` and `average()` require numeric values:

```dart
final revenue = await db.orders
    .all()
    .totalCentsProperty()
    .sum();

final averageRevenue = await db.orders
    .all()
    .totalCentsProperty()
    .average();
```

Aggregates can be combined with filters:

```dart
final openEstimate = await db.todos
    .filter()
    .completedEqualTo(false)
    .estimateMinutesProperty()
    .sum();
```

Use property aggregates when you need a summary of matching data without
reading every full object into application code.

## Common Use Cases

### Lightweight Lists

Use a projection when a list only needs ids and labels:

```dart
final rows = await db.todos
    .all()
    .sortByTitle()
    .properties(['dbId', 'title'])
    .findAll();
```

### Autocomplete

Project one field for an autocomplete source:

```dart
final titles = await db.todos
    .filter()
    .titleContains(search)
    .titleProperty()
    .findAll();
```

### Dashboard Counts

Use query `count()` when you need to count matching objects:

```dart
final openTodos = await db.todos
    .filter()
    .completedEqualTo(false)
    .count();
```

Use property `count()` when you need to count non-null values for a projected
field:

```dart
final todosWithCreatedAt = await db.todos
    .all()
    .createdAtProperty()
    .count();
```

### Numeric Totals

Use numeric property aggregates for totals:

```dart
final totalCents = await db.orders
    .filter()
    .paidEqualTo(true)
    .totalCentsProperty()
    .sum();
```

### Date Ranges

Use min and max over date-like properties:

```dart
final oldest = await db.todos
    .all()
    .createdAtProperty()
    .min();

final newest = await db.todos
    .all()
    .createdAtProperty()
    .max();
```

## Choosing The Right Query

Use full object queries when the app needs to display, edit, or write the
object back:

```dart
final todos = await db.todos.all().findAll();
```

Use projections when the app only needs selected fields:

```dart
final titles = await db.todos.all().titleProperty().findAll();
```

Use aggregates when the app only needs a summary value:

```dart
final count = await db.todos.filter().completedEqualTo(false).count();
```

`CindelDocument` is a map-shaped representation used for multi-field
projections and generated conversion helpers. Most app code should prefer typed
objects and generated helpers unless a projection is intentionally being used.
