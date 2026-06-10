# Cindel Public API

This document describes the public Dart API exported by
`package:cindel/cindel.dart`, plus the experimental Web entrypoint exported by
`package:cindel/cindel_web.dart`.

Cindel is still pre-1.0. The API is usable, but some names and advanced
storage behavior can still change before the stable line.

## Import

```dart
import 'package:cindel/cindel.dart';
```

This single import exposes:

- database opening and manual document APIs,
- schema annotations re-exported from `cindel_annotations`,
- generated typed collection/query APIs,
- query/filter helpers,
- watcher helpers,
- transaction helpers,
- generated binary and native typed document helpers used by the generator.

Web worker code can import the experimental Web entrypoint separately:

```dart
import 'package:cindel/cindel_web.dart';
```

It exposes the Web worker bridge and schema manifest encoder without changing
the native `package:cindel/cindel.dart` API.

## Opening Databases

### `Cindel.open`

Opens a persistent database in a directory.

```dart
final db = await Cindel.open(
  directory: directory.path,
  schemas: [TodoModelSchema],
);
```

Parameters:

- `directory`: filesystem directory for the database.
- `schemas`: generated collection schemas to register.
- `backend`: storage backend. Defaults to `CindelStorageBackend.mdbx`.

Throws:

- `ArgumentError` when `directory` is empty.
- `StateError` when the native engine cannot be opened.
- schema errors when registered schemas are incompatible with stored metadata.

### `Cindel.openInMemory`

Opens a short-lived in-memory database.

```dart
final db = await Cindel.openInMemory(schemas: [TodoModelSchema]);
```

This is intended for tests and temporary work. Data is discarded when the
database is closed.

### `CindelStorageBackend`

```dart
enum CindelStorageBackend {
  sqlite,
  mdbx,
}
```

- `mdbx`: default backend for new databases.
- `sqlite`: explicit compatibility backend.

```dart
final db = await Cindel.open(
  directory: directory.path,
  schemas: [TodoModelSchema],
  backend: CindelStorageBackend.sqlite,
);
```

The default backend is exposed as:

```dart
const defaultCindelStorageBackend = CindelStorageBackend.mdbx;
```

## Experimental Web Runtime

The Web runtime uses SQLite in a Worker with OPFS persistence. MDBX remains the
default for native and Flutter apps; Web forces SQLite because MDBX is not the
browser storage backend.

### `cindelEncodeWebSchemaManifest`

Encodes generated schemas for the Web worker/Wasm opener.

```dart
final manifestBytes = cindelEncodeWebSchemaManifest([TodoModelSchema]);
```

The bytes match the native schema manifest wire format used by `Cindel.open`.
The Web Wasm opener registers schema metadata and storage metadata
persistently, then rejects incompatible schema changes with the same schema
compatibility checks used by native storage.

Persisted Web SQLite opens also keep the runtime collection schemas registered
after metadata validation. This keeps SQLite native document cursors available
for the typed CRUD fast path after closing and reopening OPFS-backed storage.

### Web CRUD Worker Surface

The experimental package worker at `packages/cindel/web/cindel_worker.js`
routes typed CRUD operations to `CindelWebEngine`:

- `open`: opens SQLite/OPFS with encoded schemas.
- `allocateId` and `allocateIds`: return encoded id-list payloads.
- `put` and `putAll`: accept encoded indexed document batches.
- `putNativeAll`: accepts encoded SQLite-native generated document batches.
- `get` and `getAll`: return encoded optional document batches.
- `getStored` and `getAllStored`: read stored generated documents when a
  SQLite-native schema table is available.
- `delete`, `deleteAll`, and `deleteNativeAll`: delete generic or native rows.
- `documentIds`: returns an encoded id-list payload.

The exported Web wire helpers include `encodeIdList`, `decodeIdList`,
`encodeIndexedDocumentWriteBatch`, `decodeOptionalDocumentBatch`,
`encodeNativeDocumentWriteBatch`, and `decodeNativeDocumentWriteBatch`. These
helpers keep Worker payloads binary; structured objects are only used as the
small request envelope around operation names, collection names, and buffers.

## Closing Databases

### `CindelDatabase.close`

```dart
await db.close();
```

Closing more than once is safe. Closing rolls back an active transaction and
closes active watchers.

## Manual Document API

The manual API works with `CindelDocument`:

```dart
typedef CindelDocument = Map<String, Object?>;
```

Supported values:

- `null`
- `String`
- `bool`
- `int`
- finite `double`
- `List<Object?>`
- `Map<String, Object?>`

Unsupported values throw `ArgumentError`.

Embedded generated models are stored as `Map<String, Object?>` values inside
their parent document. Lists of embedded objects are stored as `List<Object?>`
containing those maps.

### `put`

Stores one document by collection and id.

```dart
await db.put('todos', 1, {
  'title': 'Ship docs',
  'completed': false,
});
```

### `putAll` / `putMany`

Stores many documents atomically.

```dart
await db.putAll('todos', {
  1: {'title': 'A'},
  2: {'title': 'B'},
});
```

`putMany` is an alias for `putAll`.

### `get`

Returns one document or `null`.

```dart
final todo = await db.get('todos', 1);
```

### `getAll`

Returns documents in the same order as the requested ids. Missing documents are
returned as `null`.

```dart
final todos = await db.getAll('todos', [2, 1, 404]);
```

### `documentsByIds`

Returns existing documents for ids, preserving input order for documents that
exist.

```dart
final todos = await db.documentsByIds('todos', [1, 2]);
```

### `documentIds`

Returns every id in a collection, ordered ascending.

```dart
final ids = await db.documentIds('todos');
```

### `queryAll`

Returns every document in a collection, ordered by id.

```dart
final allTodos = await db.queryAll('todos');
```

### `delete`

Deletes one document if it exists.

```dart
await db.delete('todos', 1);
```

### `deleteAll`

Deletes many documents atomically.

```dart
await db.deleteAll('todos', [1, 2, 3]);
```

## Native Id Allocation

### `allocateId`

Allocates the next native id for a collection.

```dart
final id = await db.allocateId('todos');
```

Generated typed APIs use this when an object id is `autoIncrement`.

## Transactions

### `readTxn`

Runs reads inside a native read transaction.

```dart
final todos = await db.readTxn(() async {
  return db.queryAll('todos');
});
```

Write operations inside `readTxn` throw `StateError`.

### `writeTxn`

Runs writes inside a native write transaction.

```dart
await db.writeTxn(() async {
  await db.put('todos', 1, {'title': 'A'});
  await db.put('todos', 2, {'title': 'B'});
});
```

If the callback throws, native changes are rolled back and watchers are not
notified.

Nested explicit transactions are rejected.

## Schema Annotations

Cindel annotations are re-exported by `package:cindel/cindel.dart`.

### `@Collection` and `@collection`

Marks a class as a persisted root collection.

```dart
@Collection(name: 'todos')
class TodoModel {
  Id dbId = autoIncrement;

  @index
  late String title;
}
```

Use `@Collection(...)` when you need options such as `name` or `indexes`. Use
the lowercase `@collection` constant when defaults are enough. When `name` is
omitted, the generator derives a lower-camel-case collection name from the
class name.

### `@Name`

Overrides the persisted name for a collection or field while keeping generated
Dart APIs based on Dart identifiers.

```dart
@Name('accounts')
@collection
class Account {
  Id dbId = autoIncrement;

  @Name('user_name')
  @Index(unique: true)
  late String username;
}
```

In this example generated Dart APIs use names such as `AccountSchema`,
`db.accounts`, `usernameEqualTo`, and `putByUsername`, while the stored schema
uses the `accounts` collection and `user_name` field.

### `@Embedded` and `@embedded`

Marks a class as an embedded value object stored inside a parent document.

```dart
@Embedded()
class Address {
  late String city;
}
```

Embedded classes are not opened as standalone collections. The generator uses
them when a root `@Collection` contains an embedded field or a list of embedded
objects.

### `@Index` and `@index`

Marks a field as indexed.

```dart
@index
late String title;

@Index(unique: true)
late String email;

@Index(caseSensitive: false)
late String normalizedName;

@Index(type: CindelIndexType.words, caseSensitive: false)
late String titleWords;

@Index(type: CindelIndexType.multiEntry)
late List<String> tags;
```

`replace` is optional and defaults to `false`. Use
`@Index(unique: true)` for a normal unique index. Add `replace: true` only when
a write with the same indexed value should replace the existing conflicting
document instead of throwing a duplicate-index error:

```dart
@Index(unique: true, replace: true)
late String username;
```

Generated typed collections expose `putBy...` and `putAllBy...` helpers only
for unique replace indexes.

### `@Collection(indexes: [...])` and `CompositeIndex`

Declares collection-level composite indexes.

```dart
@Collection(
  name: 'todos',
  indexes: [
    CompositeIndex(['completed', 'createdAt']),
    CompositeIndex(['tenantId', 'slug'], unique: true),
  ],
)
class TodoModel {
  Id dbId = autoIncrement;
  late int tenantId;
  late String slug;
  late bool completed;
  late DateTime createdAt;
}
```

The fields listed in a `CompositeIndex` do not need their own `@Index`
annotation. The composite index is generated from the collection-level
declaration above. Add `@Index` to `completed` or `createdAt` only if you also
want to query either field independently.

Composite `replace` also defaults to `false`. Add `replace: true` only for a
unique composite index that should replace conflicting documents:

```dart
CompositeIndex(['tenantId', 'slug'], unique: true, replace: true)
```

### `@Enumerated`

Controls enum persistence.

```dart
@Enumerated(CindelEnumType.name)
late TodoStatus status;
```

Strategies:

- `CindelEnumType.name`
- `CindelEnumType.ordinal`
- `CindelEnumType.value`

### `@ignore`

Excludes a field from persistence.

```dart
@ignore
String transientText = '';
```

### `Id` and `autoIncrement`

```dart
Id dbId = autoIncrement;
```

`Id` is an alias for `int`. `autoIncrement` is a sentinel used by generated
typed writes to request a native id.

## Freezed Models

Cindel supports Freezed classic classes and Freezed primary factory models.

Classic classes expose concrete final fields:

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

Primary factory models read persisted properties from the unnamed factory
constructor. Cindel annotations can be placed on factory parameters:

```dart
@freezed
@Collection(name: 'users')
abstract class User with _$User {
  const factory User({
    required Id dbId,
    @Index(unique: true) required String email,
    @Default(true) bool active,
    @ignore String? transientNote,
  }) = _User;
}
```

Ignored factory parameters must be optional so generated hydration can rebuild
the object.

IMPORTANT: Freezed union/sealed multi-constructor models are not supported.

## Generated Typed API

Generated code creates:

- a `CindelCollectionSchema<T>` constant,
- a database extension getter,
- typed collection helpers,
- typed where/filter helpers,
- sort/distinct/property helpers,
- serializers and binary document readers/writers,
- native typed document readers/writers when the field layout supports it,
- embedded conversion and nested filter helpers when collection fields or list
  elements use `@Embedded` value objects.
- `putBy...` and `putAllBy...` helpers for unique replace indexes.

Example:

```dart
@Collection(name: 'todos')
class TodoModel {
  Id dbId = autoIncrement;

  @index
  late String title;

  late bool completed;

  @index
  DateTime createdAt = DateTime.now().toUtc();

  @Index(type: CindelIndexType.multiEntry)
  List<String> tags = const [];
}
```

Generated usage:

```dart
final db = await Cindel.open(
  directory: directory.path,
  schemas: [TodoModelSchema],
);

await db.todos.put(todo);
final saved = await db.todos.get(todo.dbId);
final matches = await db.todos.where().titleEqualTo('Ship docs').findAll();
```

## `CindelTypedCollection<T>`

Typed collections are usually accessed through generated extension getters such
as `db.todos`.

### `all`

Starts a query over the whole collection.

```dart
final todos = await db.todos.all().findAll();
```

### `put`

Stores one typed object.

```dart
await db.todos.put(todo);
```

If the id field is `autoIncrement`, Cindel allocates and assigns a native id
before writing.

### `putAll` / `putMany`

Stores many typed objects atomically.

```dart
await db.todos.putAll(todos);
```

`putMany` is an alias for `putAll`.

### Generated `putBy...` / `putAllBy...`

Generated only for unique indexes where `replace: true` is explicitly set.
These helpers reuse an existing id for the indexed value before writing, which
gives natural-key upsert behavior without a manual query.

```dart
@collection
class Account {
  Id dbId = autoIncrement;

  @Index(unique: true, replace: true)
  late String username;
}

await db.accounts.putByUsername(account);
await db.accounts.putAllByUsername(accounts);
```

If the indexed value is already stored under a different id, the object being
written receives that existing id and replaces that stored document. Normal
`put` also respects `replace: true`: a conflicting document with a different id
is deleted and the new id remains.

### `get`

Returns one typed object or `null`.

```dart
final todo = await db.todos.get(1);
```

### `getAll`

Returns typed objects in requested id order. Missing objects are `null`.

```dart
final todos = await db.todos.getAll([1, 2, 404]);
```

### `delete`

Deletes one object by id.

```dart
await db.todos.delete(1);
```

### `deleteAll`

Deletes many objects atomically.

```dart
await db.todos.deleteAll([1, 2, 3]);
```

## Queries

### Starting Queries

Generated where helpers create indexed queries:

```dart
final byTitle = await db.todos.where().titleEqualTo('Ship docs').findAll();
final byCreatedAt = await db.todos.where().createdAtBetween(a, b).findAll();
final tagged = await db.todos.where().tagsContains('urgent').findAll();
```

Fields that are not indexed are queried through `filter()`:

```dart
final done = await db.todos.filter().completedEqualTo(true).findAll();
```

Manual query factories are also public:

```dart
final query = CindelQuery.equal(
  database: db,
  schema: TodoModelSchema,
  field: 'title',
  value: 'Ship docs',
);
```

Available factories:

- `CindelQuery.all`
- `CindelQuery.equal`
- `CindelQuery.compositeEqual`
- `CindelQuery.range`
- `CindelQuery.stringStartsWith`
- `CindelQuery.wordsContain`
- `CindelQuery.wordsStartWith`

### Filters

Filters are applied with `whereMatches`.

```dart
final matches = await db.todos
    .all()
    .whereMatches(CindelFilter.field('title').contains('ship'))
    .findAll();
```

Nested object paths can be addressed with `CindelFilter.path`:

```dart
final matches = await db.messages
    .all()
    .whereMatches(
      CindelFilter.path(['sender', 'address']).equalTo('ada@example.com'),
    )
    .findAll();
```

When a path reaches a list, Cindel evaluates the remaining path against each
element and matches when any element satisfies the predicate:

```dart
final matches = await db.messages
    .all()
    .whereMatches(
      CindelFilter.path(['recipients', 'address']).equalTo('mary@example.com'),
    )
    .findAll();
```

Field predicates:

- `equalTo`
- `greaterThan`
- `greaterThanOrEqualTo`
- `lessThan`
- `lessThanOrEqualTo`
- `between`
- `contains`
- `isEmpty`
- `isNotEmpty`
- `lengthEqualTo`
- `lengthLessThan`
- `lengthGreaterThan`
- `lengthBetween`
- `startsWith`
- `endsWith`

List fields also get generated Isar-style helpers:

```dart
final tagged = await db.todos
    .filter()
    .tagsElementEqualTo('urgent')
    .findAll();

final empty = await db.todos.filter().tagsIsEmpty().findAll();

final sized = await db.todos
    .filter()
    .tagsLengthBetween(1, 3, includeUpper: false)
    .findAll();
```

Boolean composition:

```dart
final predicate = CindelFilter.all([
  CindelFilter.field('completed').equalTo(false),
  CindelFilter.field('title').contains('ship'),
]);

final any = CindelFilter.any([
  CindelFilter.field('title').contains('ship'),
  CindelFilter.field('title').contains('release'),
]);

final notDone = CindelFilter.not(
  CindelFilter.field('completed').equalTo(true),
);
```

### Dynamic Query Modifiers

`CindelQuery` supports dynamic modifiers for building conditional filters
without branching the whole query chain:

```dart
final matches = await db.todos
    .all()
    .optional(searchText.isNotEmpty, (query) {
      return query.filter().titleContains(searchText);
    })
    .anyOf(selectedTags, (query, tag) {
      return query.filter().tagsElementEqualTo(tag);
    })
    .allOf(requiredWords, (query, word) {
      return query.filter().titleContains(word);
    })
    .findAll();
```

Generated filter wrappers expose the same modifiers directly:

```dart
final matches = await db.todos
    .filter()
    .optional(showOpenOnly, (query) => query.completedEqualTo(false))
    .anyOf(selectedTags, (query, tag) => query.tagsElementEqualTo(tag))
    .findAll();
```

Empty `anyOf` matches nothing. Empty `allOf` is a no-op.

### Sorting

```dart
final sorted = await db.todos
    .all()
    .sortBy('createdAt', order: CindelSortOrder.descending)
    .thenBy('title')
    .findAll();
```

Generated helpers normally expose typed wrappers such as `sortByTitle()`.

### Distinct

```dart
final distinctTitles = await db.todos.all().distinctBy('title').findAll();

final distinctPairs = await db.todos
    .all()
    .distinctByFields(['completed', 'title'])
    .findAll();
```

### Offset and Limit

```dart
final page = await db.todos.all().offset(20).limit(10).findAll();
```

### Query Results

```dart
final all = await query.findAll();
final first = await query.findFirst();
final count = await query.count();
```

### Query Deletes

```dart
final deletedOne = await query.deleteFirst();
final deletedCount = await query.deleteAll();
```

`deleteFirst` returns `true` when an object was deleted.
`deleteAll` returns the number of deleted objects.

### Query Updates

Generated and manual queries can update matching documents with a map of field
changes:

```dart
final updatedOne = await db.todos
    .where()
    .titleEqualTo('Ship docs')
    .updateFirst({'completed': true});

final updatedCount = await db.todos
    .all()
    .whereMatches(CindelFilter.field('completed').equalTo(false))
    .updateAll({'completed': true});
```

`updateFirst` returns `true` when an object was updated. `updateAll` returns the
number of updated objects.

## Property Queries

### Single Property

```dart
final titles = await db.todos.all().property<String>('title').findAll();
final firstTitle = await db.todos.all().property<String>('title').findFirst();
```

Generated code normally exposes helpers such as:

```dart
final titles = await db.todos.all().titleProperty().findAll();
```

### Aggregates

```dart
final count = await db.todos.all().createdAtProperty().count();
final min = await db.todos.all().createdAtProperty().min();
final max = await db.todos.all().createdAtProperty().max();
final sum = await db.todos.all().createdAtProperty().sum();
final average = await db.todos.all().createdAtProperty().average();
```

Aggregates are supported for property queries. Unsupported values throw when an
operation requires comparable or numeric values.

### Multiple Properties

```dart
final rows = await db.todos
    .all()
    .properties(['dbId', 'title'])
    .findAll();
```

Rows are returned as `CindelDocument` maps.

## Embedded Objects

Embedded objects are modeled with `@Embedded()` or `@embedded` and stored inside
a parent collection document:

```dart
@Collection(name: 'messages')
class Message {
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

Generated document serializers represent embedded values as nested maps:

```dart
final document = MessageSchema.toDocument(message);
final sender = document['sender'] as Map<String, Object?>?;
```

Generated filters support whole-object equality, embedded-list equality,
embedded-list element equality, nested field filters for single embedded object
fields, and nested field filters for elements inside embedded object lists:

```dart
final bySender = await db.messages
    .filter()
    .sender((recipient) => recipient.addressEqualTo('ada@example.com'))
    .findAll();

final byNestedMetadata = await db.messages
    .filter()
    .sender((recipient) {
      return recipient.metadata((metadata) {
        return metadata.labelEqualTo('lead');
      });
    })
    .findAll();

final byRecipient = await db.messages
    .filter()
    .recipientsElement((recipient) {
      return recipient.addressEqualTo('mary@example.com');
    })
    .findAll();

final byRecipientMetadata = await db.messages
    .filter()
    .recipientsElement((recipient) {
      return recipient.metadata((metadata) {
        return metadata.labelEqualTo('secondary');
      });
    })
    .findAll();
```

Whole embedded object equality and embedded-list element equality compare the
stored map/list value deeply, so equivalent embedded values match even though
the Dart map instances are different.

Property queries can project embedded values back to typed embedded objects:

```dart
final senders = await db.messages.all().senderProperty().findAll();
final recipientLists = await db.messages.all().recipientsProperty().findAll();
```

Generated native writers and readers support embedded object fields and
embedded object list fields through `writeObject`, `writeObjectList`,
`readObject`, and `readObjectList` hooks when the schema supports native typed
documents.

Current embedded limits:

- Embedded classes are not standalone collections.
- `@Index` inside an embedded class is not supported. Index root collection
  fields instead.

## Watchers

Cindel watchers emit after committed changes. Local writes notify watchers
directly, while polling remains as the fallback for changes from another
database handle.

The default polling interval is:

```dart
const defaultCindelWatchPollInterval = Duration(milliseconds: 50);
```

### Manual Document Watchers

```dart
final sub = db.watchDocument('todos', 1).listen((document) {
  // document is CindelDocument? 
});
```

Options:

- `pollInterval`
- `fireImmediately`

### Manual Lazy Document Watchers

```dart
final sub = db.watchDocumentLazy('todos', 1).listen((_) {
  // document may have changed
});
```

### Manual Collection Watchers

```dart
final sub = db.watchCollection('todos').listen((documents) {
  // documents is List<CindelDocument>
});
```

### Manual Lazy Collection Watchers

```dart
final sub = db.watchCollectionLazy('todos').listen((_) {
  // collection may have changed
});
```

### Native Change-Set Watcher

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

### Typed Object Watchers

```dart
final sub = db.todos.watchObject(1).listen((todo) {
  // todo is TodoModel?
});
```

### Typed Lazy Object Watchers

```dart
final sub = db.todos.watchObjectLazy(1).listen((_) {});
```

### Typed Collection Watchers

```dart
final sub = db.todos.watchCollection().listen((todos) {});
```

### Typed Lazy Collection Watchers

```dart
final sub = db.todos.watchCollectionLazy().listen((_) {});
```

### Query Watchers

```dart
final sub = db.todos
    .where()
    .completedEqualTo(false)
    .watch()
    .listen((todos) {});
```

### Lazy Query Watchers

```dart
final sub = db.todos
    .where()
    .completedEqualTo(false)
    .watchLazy()
    .listen((_) {});
```

## Text Helpers

### `Cindel.splitWords`

Splits text the same way Cindel word indexes do.

```dart
final tokens = Cindel.splitWords('Ship the docs!', caseSensitive: false);
```

This is useful when debugging `CindelIndexType.words` behavior.

## Schema Metadata API

### `CindelCollectionSchema<T>`

Generated metadata for a collection.

Important fields:

- `name`
- `dartName`
- `idField`
- `fields`
- `compositeIndexes`
- `toDocument`
- `fromDocument`
- `toBinaryDocument`
- `fromBinaryDocument`
- `getId`
- `writeNativeDocument`
- `readNativeDocument`
- `setId`

Most applications do not construct schemas manually. They pass generated
schemas to `Cindel.open`.

### `CindelFieldSchema`

Generated metadata for one persisted field.

Important fields:

- `name`
- `dartType`
- `binaryType`
- `isId`
- `isIndexed`
- `isIndexUnique`
- `isIndexReplace`
- `indexCaseSensitive`
- `indexType`

### `CindelCompositeIndexSchema`

Generated metadata for one composite index.

Important fields:

- `name`
- `fields`
- `isUnique`
- `isReplace`
- `caseSensitive`

### `schemaVersion`

Returns the registered schema version for a collection, or `null` when the
collection has no registered schema.

```dart
final version = await db.schemaVersion('todos');
```

## Generated Binary Document Helpers

These helpers are exported because generated code uses them. Most application
code should not call them directly.

### Types

```dart
typedef CindelBinaryDocumentBytes = Uint8List;

enum CindelBinaryFieldType {
  boolValue,
  intValue,
  doubleValue,
  stringValue,
  listValue,
  objectValue,
}
```

Native typed document hooks used by generated schemas:

```dart
typedef CindelWriteNativeDocument<T> =
    void Function(CindelNativeDocumentWriter writer, T object);

typedef CindelReadNativeDocument<T> =
    T Function(CindelNativeDocumentReader reader, int documentIndex);
```

`CindelNativeDocumentWriter` supports:

- `writeNull`
- `writeBool`
- `writeInt`
- `writeDouble`
- `writeString`
- `writeObject`
- `writeObjectList`
- `beginList`
- `endList`

`CindelNativeStringListDocumentWriter` is an optional writer fast path for
generated non-null `List<String>` fields. Generated serializers should call
`cindelWriteNativeStringList(writer, fieldIndex, value)` so writers that do not
implement the fast path still fall back to `beginList` / `endList`.

`CindelNativeDocumentReader` supports:

- `length`
- `isPresent`
- `readId`
- `readBool`
- `readInt`
- `readDouble`
- `readString`
- `readStringList`
- `readObject`
- `readObjectList`
- `readList`
- `release`

### Generic object/list binary payloads

```dart
final objectBytes = cindelEncodeBinaryObject({'title': 'Ship docs'});
final object = cindelDecodeBinaryObject(objectBytes);

final listBytes = cindelEncodeBinaryList(['urgent', null, 'docs']);
final list = cindelDecodeBinaryList(listBytes);
```

### Schema-specific compact binary format

```dart
final bytes = cindelEncodeSchemaBinaryDocument(fields, fieldTypes);
final fields = cindelDecodeSchemaBinaryDocument(bytes, fieldTypes);
```

### `CindelSchemaBinaryDocumentReader`

Reader used by generated direct binary hydration.

Applications normally interact with typed objects instead of this reader.

## Public But Generator-Oriented Native Query Plan Types

The following types are exported through the public library but are primarily
used by generated query helpers and internal typed query plumbing:

- `CindelNativeQuerySource`
- `CindelNativeAllQuerySource`
- `CindelNativeIndexEqualQuerySource`
- `CindelNativeCompositeEqualQuerySource`
- `CindelNativeIndexRangeQuerySource`
- `CindelNativeQuerySort`
- `CindelNativeQueryPlan`

Application code should prefer generated query helpers.

## Current Limits

The current public API does not yet include:

- `exists()` query result helper,
- embedded-field indexes,
- public migration/export tooling,
- the complete high-level Dart Web database API.

SQLite remains selectable, but MDBX is the default optimized backend.
