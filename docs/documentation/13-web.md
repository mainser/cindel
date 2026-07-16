# Web

Flutter Web uses the same Cindel typed API as native Flutter apps. Application
code still opens a database, registers generated schemas, and works through
typed collections such as `db.users`.

## Flutter Web Usage

Open a Web database with `Cindel.open`:

```dart
final db = await Cindel.open(
  directory: 'app-data',
  schemas: [UserSchema],
);
```

On Web, `directory` is a logical browser database name. It is not a filesystem
path, and users will not see a folder with that name on their device.

Use a stable name for persistent app data:

```dart
final db = await Cindel.open(
  directory: 'shop-lite',
  schemas: [ProductSchema, CartItemSchema],
);
```

After opening, use generated collections normally:

```dart
await db.users.put(user);

final saved = await db.users.get(user.dbId);
final users = await db.users.all().findAll();
```

For tests or temporary work, use `Cindel.openInMemory`:

```dart
final db = await Cindel.openInMemory(
  schemas: [UserSchema],
);
```

## Required Dependencies

Flutter Web apps should depend on both `cindel` and `cindel_flutter_libs`.

```yaml
dependencies:
  cindel: ^x.y.z
  cindel_flutter_libs: ^x.y.z
```

The app also needs generated schemas, so normal projects should use
`cindel_generator` with `build_runner` in `dev_dependencies`:

```yaml
dev_dependencies:
  build_runner: ^2.15.0
  cindel_generator: ^x.y.z
```

`cindel` provides the Dart API. `cindel_flutter_libs` packages the Web worker,
JavaScript glue, and Wasm runtime that Cindel needs in the browser. A Web app
should include both dependencies even when your Dart code imports only
`package:cindel/cindel.dart`.

Serve the Flutter Web app from a browser context that supports:

- Workers,
- Wasm,
- OPFS.

OPFS is the browser storage area used by the Web SQLite runtime. If a browser,
privacy mode, or embedded WebView blocks those features, opening the database
can fail.

MDBX is not used in browsers. Do not select MDBX as a Web backend.

## Supported APIs

Supported Web app APIs include:

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
- open-time sync configuration,
- typed object, collection, query, and lazy watchers.

Example:

```dart
final newest = await db.todos
    .all()
    .sortByCreatedAt(order: CindelSortOrder.descending)
    .limit(20)
    .findAll();
```

Watchers are available:

```dart
final sub = db.todos.watchCollection().listen((todos) {
  // Update Web UI state.
});
```

Backup import/export can use uncompressed JSONL streams on Web:

```dart
await CindelBackup.exportDatabase(
  database: db,
  collections: [CindelBackupCollection(UserSchema)],
  compression: CindelBackupCompression.none,
  output: output,
);
```

## Current Limitations

Current Web limits:

- MDBX is not used in browsers.
- Watcher delivery is single-tab.
- Sync watcher delivery is also single-tab.
- Multi-tab coordination is not supported.
- Browser storage quota and OPFS availability depend on the target browser.

If the browser does not provide the required runtime features, opening the
database can fail. Handle database open errors and provide an app-level message
when Web storage is unavailable.

## Browser Considerations

Use a stable database name for real application data:

```dart
final db = await Cindel.open(
  directory: 'my-production-app',
  schemas: [UserSchema],
);
```

Use separate names for examples, demos, tests, or previews so they do not share
the same browser database:

```dart
final demoDb = await Cindel.open(
  directory: 'my-production-app-demo',
  schemas: [UserSchema],
);
```

Browser storage quota is controlled by the browser. Application behavior should
account for the possibility that storage is limited or unavailable.

Because watcher delivery is single-tab, do not rely on one browser tab
immediately updating another tab. If your application supports multi-tab usage,
design the UI so a tab can reload or re-open its local view when needed.
