# Schema Metadata

Cindel generated schemas contain public metadata about collections, fields, and
composite indexes. Most applications only pass generated schemas to
`Cindel.open`, but metadata can be useful for tooling, diagnostics, migrations,
backup flows, and advanced integrations.

## Generated Schemas

Generated schemas are passed to `Cindel.open`.

```dart
final db = await Cindel.open(
  directory: directory.path,
  schemas: [UserSchema],
);
```

For a model such as:

```dart
@Collection(name: 'users')
class User {
  Id dbId = autoIncrement;
  late String email;
}
```

the generator creates a schema constant such as `UserSchema`.

Most application code should use generated collection getters:

```dart
await db.users.put(user);
```

Use schema metadata when code needs to inspect the generated shape of a
collection rather than read or write normal application objects.

## `CindelCollectionSchema<T>`

`CindelCollectionSchema<T>` describes one generated collection.

Important fields include:

- `name`
- `dartName`
- `idField`
- `fields`
- `links`
- `compositeIndexes`
- `toDocument`
- `fromDocument`
- `getId`
- `setId`

Example:

```dart
final schema = UserSchema;

print(schema.name);
print(schema.dartName);
print(schema.idField);
```

`name` is the persisted collection name. `dartName` is the Dart model name.

Use `fields` to inspect generated field metadata:

```dart
for (final field in UserSchema.fields) {
  print('${field.name}: ${field.dartType}');
}
```

Use `links` to inspect relationship metadata:

```dart
for (final link in UserSchema.links) {
  print('${link.dartName} -> ${link.targetCollection}');
}
```

Use `toDocument` and `fromDocument` only when you intentionally need the
map-shaped stored representation:

```dart
final document = UserSchema.toDocument(user);
final restored = UserSchema.fromDocument(document);
```

Most application code should prefer typed collection methods over direct schema
conversion.

## `CindelFieldSchema`

`CindelFieldSchema` describes one persisted field.

Important fields include:

- `name`
- `dartType`
- `binaryType`
- `isId`
- `isIndexed`
- `isIndexUnique`
- `isIndexReplace`
- `indexCaseSensitive`
- `indexType`

Example:

```dart
final indexedFields = UserSchema.fields.where((field) {
  return field.isIndexed;
});
```

Use field metadata for tooling such as:

- schema inspection screens,
- validation reports,
- export mapping,
- migration diagnostics,
- admin tooling.

Remember that `name` is the persisted field name. If a model uses `@Name`, the
persisted field name can differ from the Dart property name.

`binaryType` is the generated storage type used by Cindel's binary document
path. Most application code does not need it, but diagnostics or schema
inspection tools can display it.

## `CindelLinkSchema`

`CindelLinkSchema` describes one generated link or backlink field.

Important fields include:

- `name`
- `dartName`
- `targetCollection`
- `isToMany`
- `isBacklink`
- `backlinkTo`

Example:

```dart
for (final link in AlbumSchema.links) {
  print('${link.dartName}: ${link.targetCollection}');
}
```

`name` is the persisted relation name. `dartName` is the Dart field name.
`targetCollection` is the collection loaded by the link.

For backlinks, `isBacklink` is `true` and `backlinkTo` names the forward link
field that owns the stored relationship. This metadata is useful for schema
inspection tools, but normal application code should load links through the
generated `CindelLink` and `CindelLinks` fields on the model.

## `CindelCompositeIndexSchema`

`CindelCompositeIndexSchema` describes one generated composite index.

Important fields include:

- `name`
- `fields`
- `isUnique`
- `isReplace`
- `caseSensitive`

Example:

```dart
for (final index in EventSchema.compositeIndexes) {
  print(index.name);
  print(index.fields);
}
```

Use composite index metadata when tooling needs to understand multi-field
lookup definitions or natural-key constraints.

Most application code should use generated query helpers instead of reading
composite index metadata directly.

## `schemaVersion`

`schemaVersion` returns the registered schema version for a collection, or
`null` when no schema is registered.

```dart
final version = await db.schemaVersion('todos');
```

Use the persisted collection name:

```dart
final userVersion = await db.schemaVersion('users');
```

This is useful in diagnostics and controlled tooling:

```dart
final version = await db.schemaVersion('users');

if (version == null) {
  throw StateError('Users schema is not registered.');
}
```

Migration verification can also use `schemaVersion` after registering target
schemas:

```dart
verifyAfter: (context) async {
  final version = await context.database.schemaVersion('users');
  if (version == null) {
    throw StateError('Users schema was not registered.');
  }
},
```

## Practical Guidance

Pass generated schemas to `Cindel.open` in normal application startup.

Use generated typed collections for normal reads and writes.

Use metadata APIs only when code needs to inspect schema structure, convert to
documents intentionally, or verify registered schema state.

Do not hand-write schemas for normal application models. Let the generator
produce schema metadata from annotated Dart classes.
