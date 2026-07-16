# Cindel Annotations

Public annotations and shared schema metadata types for Cindel models.

[Overview](#overview) |
[When To Use It](#when-to-use-it) |
[Annotations](#annotations) |
[Indexes](#indexes) |
[Ids](#ids) |
[Enum Fields](#enum-fields)

> Most applications should import `package:cindel/cindel.dart`. The main
> `cindel` package re-exports these annotations together with the runtime API.
> Use `cindel_annotations` directly when building generators, tooling, or
> packages that only need model metadata and should not depend on the native
> database runtime.

## Overview

`cindel_annotations` contains the small, stable annotation surface used by
`cindel_generator` to turn regular Dart classes into Cindel schemas,
collections, query builders, and typed database accessors.

It does not open databases, run queries, or include native binaries. It only
defines the model metadata that the generator and runtime agree on.

## When To Use It

Use the main Cindel package in app code:

```dart
import 'package:cindel/cindel.dart';
```

Use this package directly only when you need annotations without the database
runtime:

```dart
import 'package:cindel_annotations/cindel_annotations.dart';
```

Typical direct users are:

- Code generators.
- Schema analysis tools.
- Shared model packages that do not open a database.
- Tests for generator behavior.

## Annotations

### `@Collection`

Marks a Dart class as a persisted root collection.

```dart
@Collection(name: 'users')
class User {
  Id dbId = autoIncrement;

  late String name;
  late String email;
}
```

When `name` is omitted, the generator derives the collection name from the
class name.

```dart
@collection
class Project {
  Id dbId = autoIncrement;
  late String title;
}
```

`@collection` is the shorthand constant for `@Collection()`.

### `@Name`

Overrides the persisted name for a collection or field while keeping the Dart
identifier available for generated method names and property access.

```dart
@Name('accounts')
@collection
class Account {
  Id dbId = autoIncrement;

  @Name('user_name')
  late String username;
}
```

This is useful when a Dart rename should not change the stored schema name.

### `@Embedded`

Marks a Dart class as a value object stored inside a parent document.

```dart
@embedded
class Address {
  late String city;
  late String country;
}

@collection
class User {
  Id dbId = autoIncrement;
  late String name;
  late Address address;
}
```

Embedded objects do not get their own collection or generated collection API.

### `@ignore`

Excludes a field from generated persistence.

```dart
@collection
class User {
  Id dbId = autoIncrement;

  late String name;

  @ignore
  bool selectedInUi = false;
}
```

Use it for transient UI state, cached values, or fields that should be
computed from persisted data.

## Indexes

Indexes tell the generator and runtime which fields should support efficient
lookup helpers.

### Value Indexes

`@index` is the shorthand for a regular value index.

```dart
@collection
class User {
  Id dbId = autoIncrement;

  @index
  late String name;
}
```

Value indexes support equality and range-style helpers where the field type
allows it.

### Unique Indexes

Use `@Index(unique: true)` when a value must be unique in the collection.

```dart
@collection
class User {
  Id dbId = autoIncrement;

  @Index(unique: true)
  late String email;
}
```

`replace` defaults to `false`. Use `@Index(unique: true)` for a normal unique
index. Add `replace: true` only when a write with the same indexed value should
replace the existing document instead of throwing a duplicate value error.

```dart
@collection
class User {
  Id dbId = autoIncrement;

  @Index(unique: true, replace: true)
  late String email;
}
```

### Case-Insensitive String Indexes

Use `caseSensitive: false` for case-insensitive string lookup.

```dart
@Index(caseSensitive: false)
late String username;
```

### Hash Indexes

Hash indexes store a compact hash and support equality lookup only.

```dart
@Index(type: CindelIndexType.hash)
late String externalId;
```

### Word Indexes

Word indexes split a string into searchable tokens.

```dart
@Index(type: CindelIndexType.words)
late String bio;
```

### Multi-Entry Indexes

Multi-entry indexes add one index entry for each primitive list item.

```dart
@Index(type: CindelIndexType.multiEntry)
late List<String> tags;
```

Use this for membership-style queries over primitive lists.

### Composite Indexes

Composite indexes are declared at the collection level.

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

The field order matters because it defines the composite key order.

Composite indexes also support `replace: true` when they are unique. This is
optional; normal unique composite indexes should omit it:

```dart
@Collection(
  indexes: [
    CompositeIndex(['teamId', 'email'], unique: true, replace: true),
  ],
)
class TeamMember {
  Id dbId = autoIncrement;
  late int teamId;
  late String email;
}
```

## Ids

`Id` is the type used by generated schemas for document ids.

```dart
@collection
class User {
  Id dbId = autoIncrement;
  late String name;
}
```

`autoIncrement` is the sentinel value that tells Cindel to allocate the next
native id when the object is inserted.

You can also assign ids manually:

```dart
@collection
class User {
  Id dbId;
  late String name;

  User({required this.dbId, required this.name});
}

final user = User(dbId: 42, name: 'Jhon Doe');
```

## Enum Fields

Use `@Enumerated` to choose how enum values are stored.

```dart
enum UserRole { admin, editor, viewer }

@collection
class User {
  Id dbId = autoIncrement;

  @Enumerated(CindelEnumType.name)
  late UserRole role;
}
```

Available strategies:

- `CindelEnumType.name`: stores the enum case name.
- `CindelEnumType.ordinal`: stores the enum index.
- `CindelEnumType.value`: stores an enum instance field.

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

## Package Role

The Cindel packages are published separately:

- `cindel_annotations`: annotations and metadata types.
- `cindel_generator`: code generation for annotated models.
- `cindel`: runtime API, typed collections, queries, watchers, and native FFI.
- `cindel_flutter_libs`: native libraries and Web runtime assets for Flutter
  apps.

This package is intentionally small so generator and tooling packages can share
the schema contract without depending on the database runtime.

## Status

Annotation names are designed to stay small and familiar. Generated schema
behavior follows the runtime package's release line.
