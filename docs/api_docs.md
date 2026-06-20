# Cindel Public API

This document is the expanded user guide for the Dart API exported by
`package:cindel/cindel.dart`.

Cindel is still pre-1.0. The current public direction is generated and typed:
application code opens a database, registers generated schemas, and works
through typed collections such as `db.users`.

## Import

```dart
import 'package:cindel/cindel.dart';
```

This single import exposes:

- `Cindel.open` and `Cindel.openInMemory`,
- schema annotations re-exported from `cindel_annotations`,
- generated typed collection/query APIs,
- query and filter helpers,
- transaction helpers,
- typed watcher helpers,
- migration plan and migration context helpers,
- schema metadata types,
- public Cindel error types,
- binary helpers used by generated code.

Application code uses the same import on native platforms and Web.

## Opening Databases

### `Cindel.open`

Opens a persistent database.

```dart
final db = await Cindel.open(
  directory: directory.path,
  schemas: [UserSchema, AccountSchema],
);
```

Parameters:

- `directory`: filesystem directory on native platforms, or the logical
  browser database name on Web.
- `schemas`: generated collection schemas to register.
- `backend`: optional native backend selector.
- `migrationPlan`: optional database migration plan. Pass the same plan on each
  app start so completed steps are skipped and the final handle opens with the
  target schemas.

MDBX is the default native backend:

```dart
const defaultCindelStorageBackend = CindelStorageBackend.mdbx;
```

Select SQLite explicitly on native platforms:

```dart
final db = await Cindel.open(
  directory: directory.path,
  schemas: [UserSchema],
  backend: CindelStorageBackend.sqlite,
);
```

### `CindelStorageBackend`

```dart
enum CindelStorageBackend {
  sqlite,
  mdbx,
}
```

- `mdbx`: default native backend.
- `sqlite`: explicit native SQLite backend.

Web keeps the same call:

```dart
final db = await Cindel.open(
  directory: 'shop-lite',
  schemas: [ProductSchema],
);
```

On Web, Cindel uses the packaged SQLite Web/OPFS Worker/Wasm runtime. MDBX is
not a browser backend.

Common failures:

- `ArgumentError`: `directory` is empty.
- `CindelOpenError`: the selected backend cannot be opened.
- `CindelSchemaError`: registered schemas are missing or incompatible with
  stored metadata.

### `Cindel.openInMemory`

Opens a temporary database for tests or short-lived work.

```dart
final db = await Cindel.openInMemory(schemas: [UserSchema]);
```

On native platforms this uses a temporary runtime database. On Web it creates a
unique browser database name for temporary use.

### `close`

```dart
await db.close();
```

Closing more than once is safe. Closing rolls back an active transaction and
closes active watcher streams.

## Data Migrations

Cindel stores a database-level data migration version inside the database.
`CindelMigrationPlan` compares that stored version with `targetVersion`, runs
the missing ordered steps, persists each successful `toVersion`, and returns a
database opened with the target schemas.

```dart
final migrations = CindelMigrationPlan(
  targetVersion: 2,
  baselineVersion: 1,
  steps: [
    CindelMigrationStep(
      fromVersion: 1,
      toVersion: 2,
      openSchemas: [OldUserSchema],
      targetSchemas: [UserSchema],
      verifyBefore: (context) async {
        final ids = await context.database.documentIds('users');
        if (ids.isEmpty) {
          return;
        }
      },
      migrate: (context) async {
        final oldUsers = await context.exportObjects(OldUserSchema);
        await context.registerTargetSchemas();
        await context.importObjects(
          UserSchema,
          oldUsers.map(User.fromLegacy),
        );
      },
      verifyAfter: (context) async {
        await context.database.schemaVersion('users');
      },
    ),
  ],
);

final db = await Cindel.open(
  directory: directory.path,
  schemas: [UserSchema],
  migrationPlan: migrations,
);
```

Migration APIs:

- `CindelMigrationPlan`: declares the final `targetVersion`, the legacy
  `baselineVersion`, ordered steps, and whether to compact after successful
  steps.
- `CindelMigrationStep`: declares `fromVersion`, `toVersion`, schemas used to
  open legacy data, target schemas, and optional before/after verification
  callbacks.
- `CindelMigrationContext.exportObjects` and `exportDocuments`: read existing
  data in id order with bounded batches.
- `CindelMigrationContext.registerTargetSchemas`: registers the target schemas
  in migrated mode. Incompatible schema changes are accepted only here, and
  target collection storage is cleared before imports.
- `CindelMigrationContext.importObjects` and `importDocuments`: write rewritten
  target data in batches.
- `CindelDatabase.migrationVersion`, `setMigrationVersion`,
  `registerMigratedSchemas`, and `compact`: lower-level primitives used by the
  migration plan and available for controlled tooling.

SQLite native, MDBX, and Web SQLite/OPFS expose the same migration contract.
For SQLite native, migrated schema registration rebuilds the target collection
table before import so removed, renamed, or type-changed fields cannot leave
stale columns behind.

## Schema Annotations

Cindel annotations are available from `package:cindel/cindel.dart`.

### `@Collection` and `@collection`

Marks a class as a persisted root collection.

```dart
@Collection(name: 'users')
class User {
  Id dbId = autoIncrement;

  @Index(unique: true)
  late String email;

  @Index()
  late String name;

  bool active = true;
}
```

Use `@Collection(...)` when you need options. Use lowercase `@collection` when
defaults are enough:

```dart
@collection
class Project {
  Id dbId = autoIncrement;
  late String title;
}
```

When `name` is omitted, the generator derives the collection name from the Dart
class name.

### `@Name`

Overrides the persisted collection or field name while generated Dart APIs keep
using Dart identifiers.

```dart
@Name('accounts')
@collection
class Account {
  Id dbId = autoIncrement;

  @Name('user_name')
  @Index(unique: true, replace: true)
  late String username;
}
```

Generated code still exposes `AccountSchema`, `db.accounts`,
`usernameEqualTo(...)`, and `putByUsername(...)`.

### `Id` and `autoIncrement`

```dart
Id dbId = autoIncrement;
```

`Id` is the id type used by generated schemas. `autoIncrement` asks Cindel to
assign the next id when the object is inserted.

Explicit ids are also supported:

```dart
@collection
class Category {
  Category({required this.dbId, required this.name});

  final Id dbId;
  final String name;
}

final category = Category(dbId: 42, name: 'Books');
await db.categories.put(category);
```

### `@ignore`

Excludes a field from persistence.

```dart
@ignore
String runtimeOnlyLabel = '';
```

### `@Enumerated`

Controls how enum values are stored.

```dart
enum Plan {
  free('free'),
  pro('pro');

  const Plan(this.code);
  final String code;
}

@collection
class Subscription {
  Id dbId = autoIncrement;

  @Enumerated(CindelEnumType.value, valueField: 'code')
  Plan plan = Plan.free;
}
```

Available strategies:

- `CindelEnumType.name`
- `CindelEnumType.ordinal`
- `CindelEnumType.value`

### Supported Field Shapes

Cindel persists:

- `bool`
- `int`
- `double`
- `String`
- `DateTime`
- `Duration`
- enums
- embedded objects
- nullable supported values
- lists of supported non-list values
- lists of embedded objects

Nested lists are not supported.

## Indexes

Indexes define which fields can use generated `where()` helpers and optimized
backend lookup paths.

### Value Indexes

```dart
@Index()
late String name;
```

The shorthand constant is also available:

```dart
@index
late DateTime createdAt;
```

Value indexes support equality helpers and range-style helpers when the field
type supports ordering.

### Unique Indexes

```dart
@Index(unique: true)
late String email;
```

Unique indexes reject duplicate values.

### Unique Replace Indexes

Use `replace: true` only when writes should reuse the existing row id for the
same natural key.

```dart
@collection
class Account {
  Id dbId = autoIncrement;

  @Index(unique: true, replace: true)
  late String username;
}
```

The generator exposes helpers:

```dart
await db.accounts.putByUsername(account);
await db.accounts.putAllByUsername(accounts);
```

If an object with the same username already exists, Cindel writes to that
existing id instead of appending a duplicate.

### Case-Insensitive String Indexes

```dart
@Index(caseSensitive: false)
late String displayName;
```

### Hash Indexes

```dart
@Index(type: CindelIndexType.hash)
late String accessToken;
```

Hash indexes support equality lookup.

### Word Indexes

```dart
@Index(type: CindelIndexType.words, caseSensitive: false)
late String searchText;
```

Word indexes split strings into tokens for word-based lookup.

```dart
final products = await db.products
    .where()
    .searchTextWordsContain('laptop')
    .findAll();
```

Generated method names depend on the field name.

### Multi-Entry Indexes

```dart
@Index(type: CindelIndexType.multiEntry, caseSensitive: false)
List<String> tags = const [];
```

Multi-entry indexes add one index entry for each list item.

```dart
final tagged = await db.products
    .where()
    .tagsContains('featured')
    .findAll();
```

### Composite Indexes

Composite indexes are declared on the collection.

```dart
@Collection(
  name: 'events',
  indexes: [
    CompositeIndex(['accountId', 'createdAt']),
    CompositeIndex(['accountId', 'slug'], unique: true, replace: true),
  ],
)
class Event {
  Id dbId = autoIncrement;
  late int accountId;
  late DateTime createdAt;
  late String slug;
}
```

The field order defines the composite key order. A composite index does not
require each field to also have its own `@Index`; add individual indexes only
when you also need independent field queries.

Unique replace composite indexes generate natural-key helpers for the composite
key.

## Freezed Models

Cindel supports Freezed classic classes and single primary-factory models.

### Primary Factory

```dart
import 'package:cindel/cindel.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'product.freezed.dart';
part 'product.g.dart';

@freezed
@Collection(name: 'products')
abstract class Product with _$Product {
  const factory Product({
    required Id dbId,
    @Index(unique: true) required String sku,
    @Index() required String name,
    @Default(true) bool active,
    @ignore String? runtimeLabel,
  }) = _Product;
}
```

Annotations such as `@Index`, `@Enumerated`, and `@ignore` can be placed on
factory parameters.

### Classic Class

```dart
@freezed
@Collection(name: 'users')
class User with _$User {
  const User({
    required this.dbId,
    required this.email,
  });

  @override
  final Id dbId;

  @override
  @Index(unique: true)
  final String email;
}
```

Freezed union/sealed multi-constructor models are not supported.

## Embedded Objects

Embedded objects are stored inside a parent collection object.

```dart
@collection
class Email {
  Id dbId = autoIncrement;

  String? subject;
  Recipient? sender;
  List<Recipient>? recipients;
}

@embedded
class Recipient {
  String? name;
  String? address;
  RecipientMetadata? metadata;
}

@embedded
class RecipientMetadata {
  String? label;
}
```

Embedded classes are not standalone collections.

### Embedded Filters

Generated filters can query inside a single embedded object:

```dart
final messages = await db.emails
    .filter()
    .sender((recipient) => recipient.addressEqualTo('ada@example.com'))
    .findAll();
```

Nested embedded objects are supported:

```dart
final leads = await db.emails
    .filter()
    .sender((recipient) {
      return recipient.metadata((metadata) {
        return metadata.labelEqualTo('lead');
      });
    })
    .findAll();
```

Embedded object lists can be queried by element:

```dart
final sentToMary = await db.emails
    .filter()
    .recipientsElement((recipient) {
      return recipient.addressEqualTo('mary@example.com');
    })
    .findAll();
```

Whole embedded object equality and embedded-list element equality compare the
stored values structurally.

Current embedded limits:

- Embedded classes do not get their own collection API.
- `@Index` inside an embedded class is not supported.
- Put indexes on root collection fields.

## Generated Typed API

For each collection, generated code creates:

- a `CindelCollectionSchema<T>` constant, such as `UserSchema`,
- a typed collection getter, such as `db.users`,
- typed CRUD helpers,
- generated `where()` helpers for indexes,
- generated `filter()` helpers for persisted fields,
- sort, distinct, property, projection, and aggregate helpers,
- embedded object conversion and nested filter helpers,
- unique replace helpers for `replace: true` indexes.

Example model:

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

Generated usage:

```dart
final db = await Cindel.open(
  directory: directory.path,
  schemas: [TodoSchema],
);

final todo = Todo()
  ..title = 'Ship docs'
  ..tags = ['docs'];

await db.todos.put(todo);

final saved = await db.todos.get(todo.dbId);

final matches = await db.todos
    .where()
    .titleEqualTo('Ship docs')
    .findAll();
```

## Typed Collections

Typed collections are usually accessed through generated extension getters.

### `all`

Starts a query over the collection.

```dart
final todos = await db.todos.all().findAll();
```

### `put`

Stores one typed object.

```dart
await db.todos.put(todo);
```

If the id is `autoIncrement`, Cindel allocates an id and writes it back through
the generated id setter before storing the object.

### `putAll` and `putMany`

Stores many typed objects atomically.

```dart
await db.todos.putAll([first, second, third]);
await db.todos.putMany(moreTodos);
```

Empty batches are no-ops. Duplicate ids inside the same batch are rejected.

### Generated `putBy...` and `putAllBy...`

Generated for unique replace indexes.

```dart
await db.accounts.putByUsername(account);
await db.accounts.putAllByUsername(accounts);
```

### `get`

Returns one typed object or `null`.

```dart
final todo = await db.todos.get(1);
```

### `getAll`

Returns typed objects in requested id order. Missing ids return `null`.
Duplicate requested ids produce duplicate result positions.

```dart
final todos = await db.todos.getAll([3, 404, 1, 3]);
```

### `delete`

Deletes one object by id.

```dart
await db.todos.delete(1);
```

### `deleteAll`

Deletes many objects by id.

```dart
await db.todos.deleteAll([1, 2, 3]);
```

### `typedCollection`

Generated extension getters call this helper. Most apps do not need it, but it
is public for advanced wiring.

```dart
final todos = db.typedCollection(TodoSchema);
await todos.put(todo);
```

## Queries

Generated query builders are the normal way to read, update, delete, project,
and aggregate typed data.

### Starting From `where`

Use `where()` for indexed fields and composite indexes.

```dart
final exact = await db.todos
    .where()
    .titleEqualTo('Ship docs')
    .findFirst();

final range = await db.todos
    .where()
    .createdAtBetween(start, end)
    .findAll();

final tagged = await db.todos
    .where()
    .tagsContains('urgent')
    .findAll();
```

### Starting From `filter`

Use `filter()` for general predicates.

```dart
final open = await db.todos
    .filter()
    .completedEqualTo(false)
    .findAll();
```

Filters can be added after a `where()` query:

```dart
final urgentOpen = await db.todos
    .where()
    .tagsContains('urgent')
    .filter()
    .completedEqualTo(false)
    .findAll();
```

### Result Methods

```dart
final all = await query.findAll();
final first = await query.findFirst();
final count = await query.count();
```

`findFirst` returns `null` when no object matches.

### Sorting

Generated sort helpers are available for persisted fields.

```dart
final newest = await db.todos
    .all()
    .sortByCreatedAt(order: CindelSortOrder.descending)
    .thenByTitle()
    .findAll();
```

The lower-level query API also accepts field names:

```dart
final sorted = await db.todos
    .all()
    .sortBy('createdAt', order: CindelSortOrder.descending)
    .thenBy('title')
    .findAll();
```

### Offset And Limit

```dart
final page = await db.todos
    .all()
    .sortByCreatedAt(order: CindelSortOrder.descending)
    .offset(20)
    .limit(10)
    .findAll();
```

### Distinct

```dart
final distinctTitles = await db.todos
    .all()
    .distinctByTitle()
    .findAll();

final distinctPairs = await db.todos
    .all()
    .distinctByFields(['completed', 'title'])
    .findAll();
```

### Dynamic Query Modifiers

Use `optional` for conditional filters:

```dart
final filtered = await db.todos
    .filter()
    .optional(search.isNotEmpty, (q) => q.titleContains(search))
    .findAll();
```

Use `anyOf` for OR-style repeated filters:

```dart
final withAnyTag = await db.todos
    .filter()
    .anyOf(selectedTags, (q, tag) => q.tagsElementEqualTo(tag))
    .findAll();
```

Use `allOf` for AND-style repeated filters:

```dart
final withAllWords = await db.todos
    .filter()
    .allOf(requiredWords, (q, word) => q.titleContains(word))
    .findAll();
```

Empty `anyOf` matches nothing. Empty `allOf` is a no-op.

### Query Deletes

```dart
final deletedOne = await db.todos
    .filter()
    .completedEqualTo(true)
    .deleteFirst();

final deletedCount = await db.todos
    .filter()
    .completedEqualTo(true)
    .deleteAll();
```

`deleteFirst` returns `true` when an object was deleted. `deleteAll` returns the
number of deleted objects.

### Query Updates

```dart
final updatedOne = await db.todos
    .where()
    .titleEqualTo('Ship docs')
    .updateFirst({'completed': true});

final updatedCount = await db.todos
    .filter()
    .completedEqualTo(false)
    .updateAll({'completed': true});
```

`updateFirst` returns `true` when an object was updated. `updateAll` returns the
number of updated objects.

The update map uses persisted field names. Updating the id field is rejected.

Values in the update map must already use Cindel-compatible stored shapes:
`null`, `bool`, `int`, finite `double`, `String`, lists, and string-keyed maps.
For converted fields such as `DateTime`, `Duration`, or enums, prefer generated
typed writes (`get` + `copyWith`/mutation + `put`) unless you intentionally want
to write the stored scalar representation.

## Filter Predicates

Generated `filter()` helpers cover most app use cases. The lower-level
`CindelFilter` builder is also public and useful for dynamic query builders.
It uses persisted field names, so prefer generated helpers when a model uses
`@Name`.

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

### Field Predicates

Available field predicates:

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

### Nested Paths

Use `CindelFilter.path` for dynamic embedded-object paths:

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

### Boolean Composition

```dart
final any = CindelFilter.any([
  CindelFilter.field('title').contains('release'),
  CindelFilter.field('title').contains('docs'),
]);

final notDone = CindelFilter.not(
  CindelFilter.field('completed').equalTo(true),
);
```

## Property Queries

### Single Property

Generated helpers:

```dart
final titles = await db.todos
    .all()
    .titleProperty()
    .findAll();

final firstTitle = await db.todos
    .all()
    .titleProperty()
    .findFirst();
```

Lower-level field-name API:

```dart
final titles = await db.todos
    .all()
    .property<String>('title')
    .findAll();
```

### Aggregates

```dart
final count = await db.todos.all().createdAtProperty().count();
final min = await db.todos.all().createdAtProperty().min();
final max = await db.todos.all().createdAtProperty().max();
final sum = await db.orders.all().totalCentsProperty().sum();
final average = await db.orders.all().totalCentsProperty().average();
```

`min` and `max` require comparable values. `sum` and `average` require numeric
values.

### Multiple Properties

```dart
final rows = await db.todos
    .all()
    .properties(['dbId', 'title'])
    .findAll();
```

Rows are returned as `CindelDocument`, a map-shaped representation:

```dart
typedef CindelDocument = Map<String, Object?>;
```

`CindelDocument` is also used by generated schema conversion helpers and filter
predicates. It is not the application persistence API.

## Transactions

### `readTxn`

Runs a read block inside a native read transaction.

```dart
final openTodos = await db.readTxn(() {
  return db.todos.filter().completedEqualTo(false).findAll();
});
```

Writes inside `readTxn` throw.

### `writeTxn`

Runs writes atomically.

```dart
await db.writeTxn(() async {
  await db.todos.put(todo);
  await db.auditEvents.put(event);
});
```

If the callback throws, Cindel rolls back the transaction and watchers are not
notified.

Nested explicit transactions are rejected.

### Checkout-Style Example

```dart
await db.writeTxn(() async {
  final product = await db.products.get(productId);
  if (product == null || product.stock < quantity) {
    throw StateError('Not enough stock.');
  }

  await db.products.put(
    product.copyWith(stock: product.stock - quantity),
  );
});
```

## Watchers

Cindel watchers emit after committed changes. Local writes notify watchers
directly. External changes can still be detected through polling.

The default polling interval is:

```dart
const defaultCindelWatchPollInterval = Duration(milliseconds: 50);
```

### Typed Object Watchers

```dart
final sub = db.todos.watchObject(1).listen((todo) {
  // todo is Todo?
});
```

Options:

- `pollInterval`
- `fireImmediately`

### Typed Lazy Object Watchers

```dart
final sub = db.todos.watchObjectLazy(1).listen((_) {
  // Object may have changed.
});
```

### Typed Collection Watchers

```dart
final sub = db.todos.watchCollection().listen((todos) {
  // todos is List<Todo>
});
```

### Typed Lazy Collection Watchers

```dart
final sub = db.todos.watchCollectionLazy().listen((_) {
  // Collection may have changed.
});
```

### Query Watchers

```dart
final sub = db.todos
    .filter()
    .completedEqualTo(false)
    .watch()
    .listen((todos) {
      // Matching typed snapshot.
    });
```

### Lazy Query Watchers

```dart
final sub = db.todos
    .filter()
    .completedEqualTo(false)
    .watchLazy()
    .listen((_) {
      // Matching query may have changed.
    });
```

### Change-Set Watcher

`watchCollectionChanges` is useful for advanced cache invalidation.

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

Most applications should prefer typed object, collection, and query watchers.

## Web

Flutter Web uses the same typed API as native Flutter apps.

```dart
final db = await Cindel.open(
  directory: 'app-data',
  schemas: [UserSchema],
);
```

Requirements:

- depend on `cindel`,
- depend on `cindel_flutter_libs`,
- serve the Flutter Web app from a browser context that supports Workers, Wasm,
  and OPFS.

```yaml
dependencies:
  cindel: ^0.7.0
  cindel_flutter_libs: ^0.7.0
```

Supported Web app APIs:

- `Cindel.open`,
- `Cindel.openInMemory`,
- generated typed CRUD,
- typed unique replace helpers,
- generated queries,
- property projections and aggregates,
- query updates and deletes,
- read and write transactions,
- bounded `documentIdsPage` scans,
- uncompressed JSONL backup import/export streams,
- typed object, collection, query, and lazy watchers.

Current Web limits:

- Web support is experimental.
- MDBX is not used in browsers.
- Watcher delivery is single-tab.
- Multi-tab coordination is not part of the current preview.
- Browser storage quota and OPFS availability depend on the target browser.

## Text Helpers

### `Cindel.splitWords`

Splits text the same way Cindel word indexes do.

```dart
final tokens = Cindel.splitWords('Ship the docs!', caseSensitive: false);
```

This is useful when checking `CindelIndexType.words` behavior.

## Schema Metadata

Generated schemas are passed to `Cindel.open`.

```dart
final db = await Cindel.open(
  directory: directory.path,
  schemas: [UserSchema],
);
```

### `CindelCollectionSchema<T>`

Important fields:

- `name`
- `dartName`
- `idField`
- `fields`
- `compositeIndexes`
- `toDocument`
- `fromDocument`
- `getId`
- `setId`

Most applications do not construct schemas by hand.

### `CindelFieldSchema`

Important fields:

- `name`
- `dartType`
- `isId`
- `isIndexed`
- `isIndexUnique`
- `isIndexReplace`
- `indexCaseSensitive`
- `indexType`

### `CindelCompositeIndexSchema`

Important fields:

- `name`
- `fields`
- `isUnique`
- `isReplace`
- `caseSensitive`

### `schemaVersion`

Returns the registered schema version for a collection, or `null` when no
schema is registered.

```dart
final version = await db.schemaVersion('todos');
```

## Advanced Database Helpers

Most application code should use typed collections. These helpers are still
public for advanced tooling and generated code.

### `CindelBackup`

Exports and imports full typed database archives. The archive format is JSONL
after decompression and includes a header, schema records, document records,
and a footer with document count and checksum.

Native Dart uses gzip by default. Web-compatible callers can pass
`compression: CindelBackupCompression.none` and store or transport the same
JSONL bytes without gzip.

```dart
final report = await CindelBackup.exportDatabase(
  database: db,
  collections: [
    CindelBackupCollection(UserSchema),
    CindelBackupCollection(OrderSchema),
  ],
  output: File('backup.cindelbak').openWrite(),
);
```

Restore targets must be opened with matching schemas and must be empty:

```dart
await CindelBackup.importDatabase(
  database: restoredDb,
  collections: [
    CindelBackupCollection(UserSchema),
    CindelBackupCollection(OrderSchema),
  ],
  input: File('backup.cindelbak').openRead(),
);
```

Backup APIs:

- `CindelBackup.exportDatabase`: streams a backup archive to a
  `StreamConsumer<List<int>>`.
- `CindelBackup.importDatabase`: streams an archive into an empty database.
- `CindelBackupCollection`: keeps generated schema typing intact for backup.
- `CindelBackupProgress`: reports phase, collection, and document count.
- `CindelBackupReport`: reports document count, archive size, checksum, and
  compression.

### `allocateId`

Allocates the next id for a collection.

```dart
final id = await db.allocateId('todos');
```

Generated typed `put` and `putAll` use this automatically when an object id is
`autoIncrement`.

### `documentIds`

Returns every id in a collection, ordered ascending.

```dart
final ids = await db.documentIds('todos');
```

To hydrate objects from ids, use the typed collection:

```dart
final todos = await db.todos.getAll(ids);
```

### `documentIdsPage`

Returns a bounded page of ids in a collection, ordered ascending. The optional
`afterId` cursor is exclusive, and `limit` must be greater than zero.

```dart
int? afterId;
while (true) {
  final ids = await db.documentIdsPage(
    'todos',
    afterId: afterId,
    limit: 1000,
  );
  if (ids.isEmpty) break;

  final todos = await db.todos.getAll(ids);
  // Export, verify, or copy this page.

  afterId = ids.last;
}
```

Use this for maintenance flows such as backup/export tooling where reading the
full id list may be too large. SQLite native, MDBX, and Web SQLite expose the
same API.

## Errors

Cindel-specific errors extend `StateError`.

- `CindelOpenError`: database backend could not be opened.
- `CindelDatabaseClosedError`: operation after `close`.
- `CindelTransactionError`: invalid transaction operation.
- `CindelSchemaError`: missing or incompatible schema.
- `CindelQueryError`: invalid or unsupported query shape.
- `CindelUniqueIndexError`: duplicate unique index value.
- `CindelNativeError`: invalid or unsafe native data.

Example:

```dart
try {
  await db.accounts.put(account);
} on CindelUniqueIndexError catch (error) {
  // Show a duplicate username message.
}
```

## Testing

Use `openInMemory` for package and widget tests.

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

For Flutter apps, keep `cindel_flutter_libs` in dependencies even when tests
mostly use in-memory databases, so integration tests and platform builds use
the same package graph as the app.

## Generator-Oriented Exports

The public library also exports binary document helpers and native typed reader
types because generated code uses them. Most application code should not call
these directly.

Examples:

- `CindelSchemaBinaryDocumentReader`
- `CindelBinaryFieldType`
- `cindelEncodeBinaryObject`
- `cindelDecodeBinaryObject`
- `cindelEncodeBinaryList`
- `cindelDecodeBinaryList`
- `cindelEncodeSchemaBinaryDocument`
- `cindelDecodeSchemaBinaryDocument`
- `CindelNativeDocumentWriter`
- `CindelNativeDocumentReader`

Application code should prefer typed collections, generated queries, and
generated schemas.

## Current Limits

The current public API does not include:

- incremental backups or merge-restore into a non-empty database,
- embedded-field indexes,
- relationship links/backlinks,
- multi-tab Web coordination.

MDBX remains the default native backend. SQLite native and SQLite Web are
available through the same generated typed API.
