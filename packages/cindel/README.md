# cindel

Ultra-fast, lightweight NoSQL local database API for Flutter and Dart apps.
Cindel provides typed collections, generated schemas, indexed queries,
transactions, watchers, migrations, and a compact Rust native runtime behind
Dart FFI.

Maintainer: Alain Ramirez <nolbertrg@gmail.com>

Repository: <https://github.com/mainser/Cindel>

## Usage

```yaml
dependencies:
  cindel: ^0.1.15
  cindel_flutter_libs: ^0.1.9

dev_dependencies:
  build_runner: ^2.15.0
  cindel_generator: ^0.1.9
```

Define a collection:

```dart
import 'package:cindel/cindel.dart';

part 'user.g.dart';

@Collection(name: 'users')
class User {
  Id id = autoIncrement;

  @Index(unique: true)
  late String email;

  late String name;
}
```

Generate code:

```sh
dart run build_runner build --delete-conflicting-outputs
```

Open a database:

```dart
final db = await Cindel.open(
  directory: directory.path,
  schemas: [UserSchema],
);
```

For tests and short-lived work:

```dart
final db = await Cindel.openInMemory(schemas: [UserSchema]);
```

## Features

- Typed collection CRUD and bulk writes.
- Native auto-increment IDs.
- Indexed equality, range, prefix, hash, case-insensitive, unique, and word
  token queries.
- Filter builders, sorting, pagination, distinct, and primitive projections.
- Explicit read and write transactions.
- Document, collection, object, query, and lazy watchers.
- Embedded objects and embedded object lists.
- Schema versions, additive migrations, and explicit migration callbacks.

## Publishing Status

Cindel is still pre-1.0.0. The package keeps `publish_to: none` until the first
pub.dev release is intentionally prepared with hosted dependencies and a clean
`dart pub publish --dry-run`.
