# Cindel

Cindel is an ultra-fast, lightweight NoSQL local database for Flutter and Dart
apps. It combines a generated Dart API, typed schemas, reactive queries,
prebuilt native binaries, and a compact Rust core behind a narrow FFI bridge.

Cindel is inspired by the developer experience of Isar, but it is built from
scratch with its own native core, storage model, code generator, and public API.

## Status

Cindel is in early pre-1.0 development. The current `0.2.15` line has the core
local database slice working end to end:

```text
Dart API -> generated schemas -> FFI -> Rust core -> MDBX storage -> Dart
```

The API is still experimental and can change before 1.0.

## Supported Platforms

| Platform | Android | iOS | Web | Linux | Windows | macOS |
| --- | --- | --- | --- | --- | --- | --- |
| Status | Yes | Planned | No | Yes | Yes | Planned |

## Features

- Flutter-first Dart API.
- Rust native core hidden behind Dart FFI.
- MDBX default storage backend with SQLite available as an explicit secondary
  option.
- Generated collection schemas and serializers.
- Generated conversion for `DateTime`, `Duration`, primitive lists, nullable
  fields, enum strategies, and ignored transient fields.
- Embedded value objects with generated nested JSON serialization.
- Manual document API with `put`, `get`, and `delete`.
- Generated typed collection accessors.
- Native auto-increment ids through `autoIncrement`.
- Atomic bulk writes and deletes.
- Simple indexed queries by equality and inclusive range.
- Generated typed query builders for indexed equality, string prefix, range,
  composite equality, and primitive list membership queries.
- Generated filter builders for non-indexed predicates.
- Sorting, pagination, distinct, and primitive property projections.
- Explicit read and write transactions.
- Document, collection, object, and query watchers with Dart streams.
- Lazy watchers and `fireImmediately` control for reactive UI flows.
- In-memory databases for tests and short-lived work.
- Schema metadata registration and compatible additive version bumps.
- Prebuilt native library package for Flutter consumers.
- CindelWireV1 binary id-list FFI payloads on common many-read, query,
  projection, aggregate, and delete paths.
- Manual backend benchmark harness for SQLite versus MDBX.

## Packages

- `packages/cindel`: public Dart API, FFI bridge, and native Rust core.
- `packages/cindel_annotations`: annotations and shared public types such as
  `@Collection`, `@Embedded`, `@index`, `Id`, and `autoIncrement`.
- `packages/cindel_flutter_libs`: prebuilt native libraries for Flutter apps.
- `packages/cindel_generator`: source generator for schemas and serializers.
- `examples/cindel_todo`: Flutter example app using Cindel like a normal
  application dependency.

## Quickstart

Add the runtime packages:

```yaml
dependencies:
  cindel: ^0.2.15
  cindel_flutter_libs: ^0.2.15

dev_dependencies:
  build_runner: ^2.15.0
  cindel_generator: ^0.2.3
```

For workspace development, use the local path packages instead:

```yaml
dependencies:
  cindel:
    path: packages/cindel
  cindel_flutter_libs:
    path: packages/cindel_flutter_libs

dev_dependencies:
  build_runner: ^2.15.0
  cindel_generator:
    path: packages/cindel_generator
```

`cindel_flutter_libs` is the Flutter-only binary package. App developers should
depend on it so Android and Windows builds can use bundled native libraries
without compiling Rust locally. Cindel maintainers can still build the
native asset directly with the `hooks.user_defines.cindel.build_native_assets`
flag in the workspace `pubspec.yaml` when they need to validate the native
assets path.

MDBX is the default backend for new databases. SQLite remains available through
`backend: CindelStorageBackend.sqlite` while it stays useful as a secondary
compatibility backend. Cindel is still pre-1.0, so storage migrations for old
preview databases are intentionally deferred.

Define a collection:

```dart
import 'package:cindel/cindel.dart';

part 'user.g.dart';

@Collection(name: 'users')
class User {
  Id id = autoIncrement;

  late String name;

  @index
  late String email;

  late DateTime createdAt;

  @Enumerated(CindelEnumType.name)
  late UserRole role;

  @ignore
  String transientNote = '';

  bool? active;
}

enum UserRole { admin, member }
```

Generate schema code:

```powershell
dart run build_runner build --delete-conflicting-outputs
```

## Opening Databases

Open a persistent database:

```dart
final db = await Cindel.open(
  directory: dir.path,
  schemas: [UserSchema],
);
```

Open an in-memory database for tests or short-lived work:

```dart
final db = await Cindel.openInMemory(
  schemas: [UserSchema],
);
```

In-memory databases are isolated per open handle and are discarded when closed.

## CRUD

The current MVP exposes a JSON-like manual document API:

```dart
await db.put('users', 1, {
  'id': 1,
  'name': 'Noel',
  'email': 'noel@example.com',
  'active': true,
});

final user = await db.get('users', 1);

await db.delete('users', 1);
```

Generated typed collection accessors are available for models with generated
schemas:

```dart
final user = User()
  ..name = 'Noel'
  ..email = 'noel@example.com'
  ..active = true;

await db.users.put(user);
final savedUser = await db.users.get(user.id);
await db.users.delete(user.id);
```

When a generated model keeps `id = autoIncrement`, `put` asks the native engine
for the next collection id and writes it back to the object before persistence.

## Schema Types

Generated schemas persist common Dart model shapes while keeping the native
document payload JSON-compatible:

- `int`, `double`, `String`, `bool`, and nullable variants are stored directly.
- `DateTime` is stored as `microsecondsSinceEpoch` and restored as UTC.
- `Duration` is stored as `inMicroseconds`.
- Primitive lists are stored as JSON arrays.
- Enum fields default to `CindelEnumType.name`.
- `@Enumerated(CindelEnumType.ordinal)` stores the enum index.
- `@Enumerated(CindelEnumType.value, valueField: 'code')` stores a custom enum
  instance field.
- `@ignore` excludes transient fields from generated persistence.
- `@Embedded` stores nested value objects as JSON maps.
- `List<EmbeddedType>` stores lists of embedded value objects.

```dart
enum Plan {
  free('free'),
  pro('pro');

  const Plan(this.code);

  final String code;
}

class User {
  Id id = autoIncrement;

  late DateTime createdAt;
  Duration? sessionLength;
  late List<String> tags;

  @Enumerated(CindelEnumType.value, valueField: 'code')
  late Plan plan;

  @ignore
  Object? uiState;
}
```

## Embedded Objects

Use `@Embedded` for value objects that live inside a parent collection document
instead of their own collection. Embedded values can be nullable and can also be
stored as lists:

```dart
@Collection(name: 'emails')
class Email {
  Id id = autoIncrement;

  String? title;

  Recipient? sender;

  List<Recipient>? recipients;
}

@Embedded()
class Recipient {
  String? name;
  String? address;
}
```

Generated serializers store embedded objects as nested JSON-compatible maps:

```dart
{
  'id': 1,
  'title': 'Hello',
  'sender': {'name': 'Ada', 'address': 'ada@example.com'},
  'recipients': [
    {'name': 'Ben', 'address': 'ben@example.com'},
  ],
}
```

The first embedded-object slice focuses on persistence and property projection
round-trips. Query builders for filtering inside embedded fields are planned for
a later stage.

Bulk typed operations use native batch writes and deletes:

```dart
await db.users.putMany([ana, ben, cid]);
final users = await db.users.getAll([ana.id, ben.id, 404]);
await db.users.deleteAll([ana.id, ben.id]);
```

`putMany` and `deleteAll` are committed in one native transaction. `putAll`
remains available as an alias for codebases that prefer the `all` naming.

## Transactions

Use `readTxn` for a consistent read snapshot and `writeTxn` for grouped writes:

```dart
final users = await db.readTxn(() {
  return db.users.where().emailStartsWith('team').findAll();
});

await db.writeTxn(() async {
  await db.users.put(ana);
  await db.users.put(ben);
});
```

Writes inside `writeTxn` commit together. If the callback throws, Cindel rolls
back the native transaction and watchers are not notified. Writes inside
`readTxn` and nested transactions are rejected for now.

## Queries

Generated typed query builders are available for indexed fields:

```dart
final users = await db.users.where().emailEqualTo('noel@example.com').findAll();
```

Indexed string fields also get prefix helpers:

```dart
final users = await db.users.where().emailStartsWith('team').findAll();
```

Range queries are inclusive and support indexed `int`, `double`, and `String`
fields:

```dart
final users = await db.users
    .where()
    .emailBetween('a@example.com', 'm@example.com')
    .findAll();
```

Indexes can declare uniqueness, case-insensitive string lookup, compact hash
storage, word-token search, primitive list membership, or collection-level
composite keys:

```dart
@Collection(
  indexes: [
    CompositeIndex(['email', 'active']),
  ],
)
class User {
  Id id = autoIncrement;

  @index
  late String email;

  bool active = true;

  @Index(unique: true)
  late String username;

  @Index(caseSensitive: false)
  late String displayName;

  @Index(type: CindelIndexType.hash)
  late String accessToken;

  @Index(type: CindelIndexType.words, caseSensitive: false)
  late String bio;

  @Index(type: CindelIndexType.multiEntry, caseSensitive: false)
  List<String> tags = const [];
}
```

`unique` indexes reject duplicate non-null values before writes are persisted.
Case-insensitive string indexes normalize equality and prefix lookups. Hash
indexes support equality helpers only; range and prefix helpers are not
generated for them. Word indexes split strings into Unicode-aware tokens and
store them as multiple index entries per document:

```dart
final dbUsers = await db.users.where().bioWordEqualTo('database').findAll();
final prefix = await db.users.where().bioWordStartsWith('dat').findAll();
final tokens = Cindel.splitWords('Café rapido, cafe!');
final team = await db.users.where().emailActiveEqualTo(email, true).findAll();
final tagged = await db.users.where().tagsContains('flutter').findAll();
```

Queries can return all results, the first result, or a count:

```dart
final first = await db.users.where().emailEqualTo(email).findFirst();
final count = await db.users.where().emailStartsWith('team').count();
```

Queries can also delete matching objects:

```dart
final deletedOne = await db.users.where().emailEqualTo(email).deleteFirst();
final deletedCount = await db.users.where().emailStartsWith('team').deleteAll();
```

Filters run after the indexed `where` clause. They can also start from the whole
collection:

```dart
final activeTeamUsers = await db.users
    .where()
    .emailStartsWith('team')
    .filter()
    .activeEqualTo(true)
    .findAll();

final matchingNames = await db.users.filter().nameContains('No').findAll();
```

For dynamic predicates, use `whereMatches` with `CindelFilter`:

```dart
final users = await db.users
    .where()
    .emailStartsWith('team')
    .whereMatches(
      CindelFilter.all([
        CindelFilter.field('active').equalTo(true),
        CindelFilter.not(CindelFilter.field('name').endsWith('test')),
      ]),
    )
    .findAll();
```

Sorting, pagination, distinct, and projections can be chained after `where` and
`filter`:

```dart
final page = await db.users
    .all()
    .sortByName()
    .thenByEmailDesc()
    .offset(20)
    .limit(10)
    .findAll();

final names = await db.users
    .where()
    .emailStartsWith('team')
    .filter()
    .activeEqualTo(true)
    .sortByName()
    .distinctByEmail()
    .nameProperty()
    .findAll();
```

Projected fields can also be aggregated. On the MDBX binary-document path,
supported aggregates run natively without hydrating full Dart objects:

```dart
final activeCount = await db.users.filter().activeEqualTo(true).idProperty().count();
final firstName = await db.users.all().nameProperty().min();
final maxId = await db.users.all().idProperty().max();
final averageId = await db.users.all().idProperty().average();
```

For dynamic projections, use `properties`:

```dart
final rows = await db.users
    .all()
    .sortById()
    .properties(['name', 'email'])
    .findAll();
```

Execution order is: indexed `where`, filter, sort, distinct, offset, limit,
then projection.

The lower-level manual query API remains available when generated typed helpers
are not being used:

```dart
final documents = await db.queryEqual('users', 'email', 'noel@example.com');
```

## Watchers

Cindel can watch a single document:

```dart
final subscription = db
    .watchDocument('users', 1, fireImmediately: true)
    .listen((document) {
  // Update UI state.
});
```

Or an entire collection:

```dart
final subscription = db.watchCollection('users').listen((documents) {
  // Update UI state.
});
```

Generated typed collections can also watch one object, whole collections, or
queries:

```dart
final objectSub = db.users.watchObject(user.id).listen((user) {
  // user is null when the object has been deleted.
});

final querySub = db.users
    .filter()
    .activeEqualTo(true)
    .sortByName()
    .watch()
    .listen((activeUsers) {
      // Emits only when the visible query result changes.
    });
```

All watcher families support `fireImmediately`. Set it to `false` when the UI
only needs future changes:

```dart
final subscription = db.users.watchCollection(
  fireImmediately: false,
).listen((users) {
  // Runs after the next visible collection change.
});
```

Lazy watchers emit `void` when something visible changes without returning the
full snapshot:

```dart
final subscription = db.users
    .filter()
    .activeEqualTo(true)
    .watchLazy()
    .listen((_) {
      // Refresh or invalidate cached state.
    });
```

Watchers emit an initial snapshot by default and then emit again after
committed changes. Document, collection, and query watchers compare visible
snapshots, so unchanged visible data is suppressed.

## Schema Versions

When schemas are registered during `Cindel.open`, Cindel stores schema metadata
inside the native database.

```dart
final version = await db.schemaVersion('users');
```

Compatible additive schema changes advance the collection version. Destructive
changes such as removing fields, changing field types, changing the id field,
changing index status, or changing index options are rejected for now. Explicit
data migration support is deferred until the optimized storage path settles.

## Benchmarks

Run the backend comparison benchmark:

```powershell
cargo run --release --manifest-path packages/cindel/native/Cargo.toml --features benchmarks --bin cindel_bench -- --backend all --documents 10000 --query-repeats 1000
```

The benchmark prints CSV rows for open, schema registration, indexed writes,
point reads, indexed queries, batch writes, and deletes.

See `docs/backend_evaluation.md` for the current `libmdbx` decision record and
benchmark evidence.

## Native Binaries

Cindel can load native libraries from a Flutter plugin bundle before falling
back to the local native-assets hook. The hook is off by default for consumers
and can be enabled by maintainers with:

```yaml
hooks:
  user_defines:
    cindel:
      build_native_assets: true
```

Maintainers regenerate the bundled libraries with:

```powershell
.\tool\prebuilt\build_windows.ps1
.\tool\prebuilt\build_android.ps1
```

```sh
./tool/prebuilt/build_apple.sh
./tool/prebuilt/build_linux.sh
```

Set `CINDEL_NATIVE_LIBRARY` to an absolute library path when testing a custom
native build without copying it into `cindel_flutter_libs`.

## Development

Install dependencies:

```powershell
dart pub get
```

Validate the workspace:

```powershell
dart format --output=none --set-exit-if-changed .
dart analyze
cargo fmt --manifest-path packages/cindel/native/Cargo.toml --check
cargo test --manifest-path packages/cindel/native/Cargo.toml
dart test packages/cindel/test -r expanded
```

See `CONTRIBUTING.md` for contribution guidelines.
See `CHANGELOG.md` for version history.

## Roadmap

The full public roadmap lives in `ROADMAP.md`.

Validated so far:

- [x] Monorepo scaffold with Dart workspace packages.
- [x] Dart to Rust FFI bootstrap.
- [x] Rust native core compilation on Windows.
- [x] SQLite storage backend through `rusqlite`.
- [x] Document persistence by collection and id.
- [x] Manual Dart API with `put`, `get`, and `delete`.
- [x] Generated collection schemas and serializers.
- [x] Generated typed collection accessors.
- [x] Native auto-increment id allocation.
- [x] Atomic bulk writes and deletes.
- [x] Simple indexes generated from schema metadata.
- [x] Equality queries over indexed fields.
- [x] Inclusive range queries over indexed fields.
- [x] Generated typed query builders.
- [x] Query deletes.
- [x] Explicit read and write transactions.
- [x] Generated filter builders.
- [x] Sorting, pagination, distinct, and primitive property projections.
- [x] Unique, case-insensitive, value, and hash index variants.
- [x] Word-token indexes for simple full-text-style search.
- [x] Composite indexes and primitive list membership indexes.
- [x] Schema type expansion for dates, durations, primitive lists, enums,
  nullable fields, and ignored fields.
- [x] Embedded objects and embedded object lists.
- [x] Document, collection, object, and query watchers with Dart streams.
- [x] Lazy watchers and `fireImmediately` control.
- [x] Native collection revision counters after committed writes.
- [x] Schema metadata registration and version persistence.
- [x] In-memory database support for tests and short-lived work.
- [x] Compatible additive schema version bumps.
- [x] Rejection of incompatible schema changes.
- [x] Internal Rust benchmark baseline for SQLite.
- [x] MDBX default backend with SQLite as an explicit secondary backend.
- [x] Apache-2.0 license, contribution guide, and package-style README.

Next areas:

- [x] Typed collection APIs.
- [x] Prebuilt native binary distribution for Android and Windows.
- [x] Query builders.
- [x] Auto-increment id support.
- [x] Bulk collection operations.
- [x] Transaction API.
- [x] Filter builder.
- [x] Sorting, pagination, distinct, and primitive property projections.
- [x] Index variants.
- [x] Full-text search primitives.
- [x] Embedded objects.
- [x] Query watchers.
- [ ] Public migration tooling after the optimized storage format stabilizes.
- [ ] Better native error reporting.
- [x] Example Flutter application.
- [ ] Apple prebuilt native binaries.
- [x] Public package publishing polish for the `0.2.0` package line.

## License

Cindel is licensed under the Apache License, Version 2.0. See `LICENSE`.
