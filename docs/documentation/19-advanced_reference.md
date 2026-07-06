# Advanced Reference

The public Cindel library exports a few advanced helpers because generated code
and tooling need them. Most application code should not call these APIs
directly.

Application code should normally prefer:

- generated typed collections,
- generated queries,
- generated schemas,
- backup APIs,
- migration APIs.

Import advanced helpers from the public package entrypoint:

```dart
import 'package:cindel/cindel.dart';
```

Do not import files from `package:cindel/src/...`. Those files are
implementation details and can change without being part of the application
contract.

## Generator-Oriented Exports

Generator-oriented exports are public because generated code needs stable
access to them.

Examples include:

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

These APIs are useful for generated code and specialized tooling. They are not
the normal persistence API for application features.

## Binary Helpers

Binary helpers encode and decode document-shaped data used by generated code.

Examples:

- `cindelEncodeBinaryObject`
- `cindelDecodeBinaryObject`
- `cindelEncodeBinaryList`
- `cindelDecodeBinaryList`
- `cindelEncodeSchemaBinaryDocument`
- `cindelDecodeSchemaBinaryDocument`

Use them only when building tooling that intentionally works with Cindel's
binary document representation.

For normal application code, use typed objects:

```dart
await db.todos.put(todo);

final saved = await db.todos.get(todo.dbId);
```

For full database archive flows, use `CindelBackup` instead of manually
encoding documents.

## Exposed Internal APIs

Some low-level reader and writer types are exported so generated code can read
and write typed data efficiently.

Examples:

- `CindelNativeDocumentWriter`
- `CindelNativeDocumentReader`
- `CindelSchemaBinaryDocumentReader`

Application code should not need these for normal persistence. If app code is
manually constructing native readers or writers, it is usually bypassing the
typed API and should be reviewed carefully.

Use higher-level APIs where possible:

```dart
final db = await Cindel.open(
  directory: directory.path,
  schemas: [UserSchema],
);

await db.users.put(user);
```

## When Not To Use Them

Do not use generator-oriented exports for:

- normal CRUD,
- normal queries,
- app UI state,
- routine imports and exports,
- replacing generated schemas,
- manually writing persisted documents without a clear tooling need.

Use generated collections:

```dart
await db.users.put(user);
```

Use generated queries:

```dart
final active = await db.users
    .filter()
    .activeEqualTo(true)
    .findAll();
```

Use backups for archive import/export:

```dart
await CindelBackup.exportDatabase(
  database: db,
  collections: [CindelBackupCollection(UserSchema)],
  output: output,
);
```

Use schema metadata for inspection:

```dart
for (final field in UserSchema.fields) {
  print(field.name);
}
```

Only reach for advanced reference APIs when you are building generator-adjacent
tools, diagnostics, or controlled integrations that cannot be implemented with
the higher-level public APIs.
