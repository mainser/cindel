# Errors

Cindel-specific errors extend `StateError`. Catch specific Cindel errors when
the application can recover or show a targeted message. Let unexpected errors
surface to your normal logging and error-reporting path.

All Cindel-specific runtime errors also share the `CindelError` base class.
Use that base class only when you intentionally want to handle every Cindel
runtime failure the same way.

## Error Overview

Public Cindel errors include:

- `CindelError`
- `CindelOpenError`
- `CindelDatabaseClosedError`
- `CindelTransactionError`
- `CindelSchemaError`
- `CindelQueryError`
- `CindelUniqueIndexError`
- `CindelNativeError`

Example:

```dart
try {
  await db.accounts.put(account);
} on CindelUniqueIndexError catch (error) {
  // Show a duplicate username message.
}
```

Cindel can also throw normal Dart errors such as `ArgumentError` when a caller
passes an invalid value, for example an empty directory, an empty collection
name, a negative id, or an invalid page limit.

## `CindelOpenError`

`CindelOpenError` means the database backend could not be opened.

```dart
try {
  final db = await Cindel.open(
    directory: directory.path,
    schemas: [UserSchema],
  );
} on CindelOpenError catch (error) {
  // Report that local storage is unavailable.
}
```

Common checks:

- the directory is valid,
- the app can write to the directory,
- required platform dependencies are present,
- the browser supports required Web storage features.

## `CindelDatabaseClosedError`

`CindelDatabaseClosedError` means code tried to use a database after `close`.

```dart
await db.close();

await db.users.all().findAll(); // Throws.
```

Avoid sharing a closed database handle. Make ownership clear: the component
that opens the database should decide when it is closed.

## `CindelTransactionError`

`CindelTransactionError` means an invalid transaction operation was attempted.

Examples include:

- writing inside `readTxn`,
- starting nested explicit transactions,
- using a transaction in an invalid state.

```dart
await db.readTxn(() async {
  await db.todos.put(todo); // Throws.
});
```

Use `readTxn` for reads and `writeTxn` for writes.

## `CindelSchemaError`

`CindelSchemaError` means a schema is missing or incompatible with stored
metadata.

```dart
try {
  final db = await Cindel.open(
    directory: directory.path,
    schemas: [UserSchema],
  );
} on CindelSchemaError catch (error) {
  // Handle schema registration or compatibility failure.
}
```

Common causes:

- opening a database without all required generated schemas,
- opening existing data with an incompatible model change,
- missing a migration plan for a stored schema change.

Open the database with the current generated schemas and provide migrations
when stored data must be rewritten.

## `CindelQueryError`

`CindelQueryError` means a query shape is invalid or unsupported.

Examples include:

- invalid aggregate use,
- unsupported query update shape,
- property aggregate against incompatible values.

```dart
try {
  final average = await db.todos
      .all()
      .titleProperty()
      .average();
} on CindelQueryError catch (error) {
  // The aggregate requires numeric values.
}
```

Use generated helpers where possible and make sure property aggregates match
the field type.

## `CindelUniqueIndexError`

`CindelUniqueIndexError` means a write would violate a unique index.

```dart
try {
  await db.accounts.put(account);
} on CindelUniqueIndexError catch (error) {
  // Show a duplicate username or email message.
}
```

Use this error to show user-friendly messages for natural keys such as email,
username, SKU, or slug.

If duplicate writes should update the existing object instead of failing, model
that field as a unique replace index and use the generated `putBy...` helper.

## `CindelNativeError`

`CindelNativeError` means Cindel received invalid or unsafe native data, or a
native-facing operation returned an unexpected value.

This is usually not a normal user-recovery path. Log it with enough context to
understand which operation was running.

```dart
try {
  final count = await db.todos.all().count();
} on CindelNativeError catch (error, stackTrace) {
  // Log and report the unexpected native data problem.
}
```

## Handling Strategy

Catch specific errors when the app can respond directly:

```dart
try {
  await db.accounts.put(account);
} on CindelUniqueIndexError {
  showDuplicateUsernameMessage();
}
```

Catch open/schema errors during startup:

```dart
try {
  return await Cindel.open(
    directory: directory.path,
    schemas: [UserSchema],
  );
} on CindelOpenError {
  showStorageUnavailableMessage();
} on CindelSchemaError {
  showDataUpgradeFailedMessage();
}
```

Avoid broad catches that hide programming errors. For unexpected failures, log
the error and stack trace so the app can be fixed.
