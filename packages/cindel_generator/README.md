# Cindel Generator

Source generator for Cindel schemas, serializers, typed collections, query
builders, filters, projections, and native typed document hooks.

[Overview](#overview) |
[Setup](#setup) |
[Model Shape](#model-shape) |
[Freezed Models](#freezed-models) |
[Generated API](#generated-api) |
[Indexes](#indexes) |
[Embedded Objects](#embedded-objects) |
[Enums](#enums)

> Most applications use `cindel_generator` as a `dev_dependency` together with
> `build_runner`. It reads annotations from your model classes and emits the
> `*.g.dart` files consumed by the `cindel` runtime.

## Overview

`cindel_generator` turns annotated Dart classes into the code Cindel needs for
typed database access:

- Collection schema metadata.
- Manual document serializers and deserializers.
- Compact binary document serializers and deserializers.
- Native typed document readers and writers when the field layout supports it.
- Typed collection accessors on `CindelDatabase`.
- Indexed `where()` query helpers.
- `filter()` query helpers for persisted fields.
- Sorting, distinct, property projection, and aggregate helpers.
- Composite index equality helpers.
- Embedded object conversion helpers.
- Embedded object and embedded object list native reader/writer hooks when the
  model layout supports native typed documents.
- Nested filter helpers for single embedded objects and embedded object list
  elements.

The package is a build-time tool. It does not open databases and it does not
ship native binaries.

## Setup

For Flutter apps, depend on Cindel and the native library package at runtime,
then add the generator as a dev dependency:

```yaml
dependencies:
  cindel: ^0.6.0
  cindel_flutter_libs: ^0.6.0

dev_dependencies:
  build_runner: ^2.15.0
  cindel_generator: ^0.6.0
```

Pure Dart packages can depend on `cindel` directly and provide a native library
path with `CINDEL_NATIVE_LIBRARY` when needed.

## Basic Usage

Create a model file with a `part` directive and Cindel annotations:

```dart
import 'package:cindel/cindel.dart';

part 'user.g.dart';

@Collection(name: 'users')
class User {
  Id dbId = autoIncrement;

  @Index(unique: true)
  late String email;

  @index
  late String name;

  bool active = true;
}
```

Run the generator:

```sh
dart run build_runner build --delete-conflicting-outputs
```

Then use the generated schema and typed collection API:

```dart
final db = await Cindel.open(
  directory: directory.path,
  schemas: [UserSchema],
);

final user = User()
  ..name = 'Jhon Doe'
  ..email = 'jhon@example.com';

await db.users.put(user);

final saved = await db.users.where().emailEqualTo('jhon@example.com').findFirst();
```

## Model Shape

Generated collections must follow the rules enforced by the generator:

- `@Collection` can only be used on concrete classes, except supported Freezed
  primary-factory models.
- A collection must declare at least one persisted field.
- A collection must declare exactly one persisted field named `dbId`.
- A collection needs either an unnamed constructor with no parameters or an
  unnamed constructor with parameters for every persisted field.
- Collections with final persisted fields need constructor parameters for every
  persisted field.
- Fields annotated with `@ignore` are excluded from persistence.

Supported persisted field shapes are:

- `bool`, `int`, `double`, and `String`.
- `DateTime` and `Duration`.
- Enums.
- Embedded objects annotated with `@Embedded`.
- Nullable variants of supported shapes.
- Lists of supported non-list shapes.

Nested lists are not supported.

## Freezed Models

The generator supports Freezed classic classes when they expose concrete final
fields:

```dart
import 'package:cindel/cindel.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'user.freezed.dart';
part 'user.g.dart';

@freezed
@Collection(name: 'users')
class User with _$User {
  const User({
    required this.dbId,
    required this.email,
    required this.name,
  });

  @override
  final Id dbId;

  @override
  @Index(unique: true)
  final String email;

  @override
  final String name;
}
```

It also supports the common Freezed primary factory style by reading persisted
properties from the unnamed factory constructor:

```dart
import 'package:cindel/cindel.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'user.freezed.dart';
part 'user.g.dart';

@freezed
@Collection(name: 'users')
abstract class User with _$User {
  const factory User({
    required Id dbId,
    required String email,
    @Index(unique: true) required String username,
    @Enumerated(CindelEnumType.ordinal) required UserStatus status,
    @Default(true) bool active,
    @ignore String? transientNote,
  }) = _User;
}
```

For primary factory models, Cindel annotations such as `@Index`,
`@Enumerated`, and `@ignore` can be placed on factory parameters. Ignored
parameters must be optional so generated hydration can rebuild the object.

IMPORTANT: Freezed union/sealed multi-constructor models are not supported.

## Generated API

For a `User` collection, the generator emits a schema named `UserSchema` and a
typed database accessor:

```dart
final users = db.users;
```

It also emits conversion functions used by the runtime:

- Dart object to manual Cindel document.
- Manual Cindel document to Dart object.
- Dart object to compact binary document.
- Compact binary document to Dart object.
- Native typed writer and reader hooks when supported by the field layout.
- Id getter, and an id setter when the model can assign generated ids.

Generated query access starts from `where()` for indexed fields and
collection-level composite indexes:

```dart
final user = await db.users.where().emailEqualTo('jhon@example.com').findFirst();
```

Generated `filter()` helpers are available for persisted fields:

```dart
final activeUsers = await db.users
    .filter()
    .activeEqualTo(true)
    .sortByName()
    .findAll();
```

Generated query modifiers include field sorting, descending sorting, distinct
helpers, and property query accessors:

```dart
final names = await db.users
    .filter()
    .activeEqualTo(true)
    .sortByName()
    .nameProperty()
    .findAll();
```

## Indexes

The generator reads `@index`, `@Index(...)`, and collection-level
`CompositeIndex(...)` annotations.

### Value Indexes

```dart
@index
late String name;
```

Value indexes generate equality helpers and range-style helpers when the field
type supports range queries.

### Unique Indexes

```dart
@Index(unique: true)
late String email;
```

Unique indexes generate the same lookup helpers and tell the runtime to enforce
unique values.

### Hash Indexes

```dart
@Index(type: CindelIndexType.hash)
late String externalId;
```

Hash indexes generate equality helpers only.

### Word Indexes

```dart
@Index(type: CindelIndexType.words)
late String bio;
```

Word indexes are supported for string fields.

### Multi-Entry Indexes

```dart
@Index(type: CindelIndexType.multiEntry)
late List<String> tags;
```

Multi-entry indexes are supported for lists of primitive values, `DateTime`,
`Duration`, or enums.

### Composite Indexes

```dart
@Collection(
  indexes: [
    CompositeIndex(['teamId', 'email'], unique: true),
  ],
)
class TeamMember {
  Id dbId = autoIncrement;

  late int teamId;
  late String email;
  late String name;
}
```

Composite indexes generate equality helpers for the configured field set.

## Embedded Objects

Embedded classes are converted as part of their parent document. They are value
objects, not root collections, and can be declared with `@Embedded()` or the
lowercase `@embedded` constant.

```dart
@embedded
class Address {
  late String city;
  late String country;
}

@embedded
class Contact {
  String? name;
  String? email;
  Address? address;
}

@collection
class User {
  Id dbId = autoIncrement;
  late String name;
  Contact? primaryContact;
  List<Contact>? contacts;
}
```

For single embedded object fields, generated filters include nested object
helpers. Helpers can continue into nested embedded objects:

```dart
final users = await db.users
    .filter()
    .primaryContact((contact) {
      return contact.address((address) {
        return address.cityEqualTo('Santo Domingo');
      });
    })
    .findAll();

final team = await db.users
    .filter()
    .contactsElement((contact) {
      return contact.address((address) {
        return address.countryEqualTo('DO');
      });
    })
    .findAll();
```

The generator also emits:

- embedded conversion helpers used by document and binary serializers,
- whole-object equality filters such as `primaryContactEqualTo(value)`,
- embedded-list equality filters such as `contactsEqualTo(values)`,
- embedded-list element equality filters such as `contactsElementEqualTo(value)`,
- embedded-list nested element filters such as `contactsElement((contact) => ...)`,
- native writer calls for embedded objects and embedded object lists,
- native reader calls for embedded objects and embedded object lists.

Embedded indexes are not supported by the generator. `@Index` inside an
embedded class is rejected. Put indexes on root collection fields instead.

## Enums

The generator supports enum fields and `@Enumerated(...)` strategies.

```dart
enum UserRole { admin, editor, viewer }

@collection
class User {
  Id dbId = autoIncrement;

  @Enumerated(CindelEnumType.name)
  late UserRole role;
}
```

For value-based enum persistence:

```dart
enum AccountStatus {
  active('A'),
  suspended('S');

  const AccountStatus(this.code);
  final String code;
}

@collection
class Account {
  Id dbId = autoIncrement;

  @Enumerated(CindelEnumType.value, valueField: 'code')
  late AccountStatus status;
}
```

## Builder Details

The package registers a `build_runner` builder named `cindel_generator`.

It uses `source_gen` as a shared part builder:

- Input: `.dart` files.
- Intermediate output: `.cindel.g.part`.
- Final user-facing output: the combined `*.g.dart` part file.

In normal projects, adding the dependency and running `build_runner` is enough.

## Status

Cindel is in active pre-1.0 development. This generator follows the same
release line as the runtime package and emits the native typed readers, writers,
query helpers, and hydration hooks used by the optimized Cindel runtime.
