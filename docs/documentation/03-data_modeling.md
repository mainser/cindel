# Data Modeling

Cindel data modeling starts with Dart classes. A root model becomes a persisted
collection, fields become persisted values, and generated schemas connect those
classes to the database API.

This guide covers model structure only: collections, ids, field types, ignored
fields, enums, embedded objects, and supported Freezed model shapes.

## Collections

A collection is a root persisted type. Each collection gets its own generated
schema and typed collection API.

Use a collection for data that should be stored and queried independently, such
as users, projects, tasks, products, orders, or settings.

```dart
import 'package:cindel/cindel.dart';

part 'user.g.dart';

@Collection(name: 'users')
class User {
  Id dbId = autoIncrement;

  late String email;
  late String name;
  bool active = true;
}
```

After generation, the model above provides a schema such as `UserSchema` and a
typed collection getter such as `db.users`.

### `@Collection`

Use `@Collection(...)` when you want to configure the collection.

```dart
@Collection(name: 'users')
class User {
  Id dbId = autoIncrement;
  late String email;
  late String name;
}
```

The `name` is the persisted collection name. It is the name stored in database
metadata and used when opening the database with generated schemas.

```dart
final db = await Cindel.open(
  directory: directory.path,
  schemas: [UserSchema],
);

await db.users.put(user);
```

A collection should represent a root entity. If a type only exists as part of
another object, model it as an embedded object instead.

Collections must have one persisted id field named `dbId`:

```dart
@Collection(name: 'projects')
class Project {
  Id dbId = autoIncrement;
  late String title;
}
```

Mutable models commonly use a no-argument constructor and assign fields before
writing. Immutable models can use constructor parameters for persisted fields.

### `@collection`

`@collection` is the shorthand for `@Collection()` when defaults are enough.

```dart
@collection
class Project {
  Id dbId = autoIncrement;
  late String title;
}
```

When no collection name is provided, the generator derives the persisted
collection name from the Dart class name.

Use `@collection` for simple models where the derived name is acceptable. Use
`@Collection(name: ...)` when you want the stored collection name to be
explicit.

### `@Name`

Use `@Name` when the persisted name should differ from the Dart name.

```dart
@Name('accounts')
@collection
class Account {
  Id dbId = autoIncrement;

  @Name('user_name')
  late String username;
}
```

In this example:

- the Dart class remains `Account`,
- the generated schema remains `AccountSchema`,
- application code keeps using the Dart field `username`,
- the persisted collection name is `accounts`,
- the persisted field name is `user_name`.

`@Name` is useful when a stored schema name must stay stable while Dart code is
renamed, or when the database format must use a different naming convention
from the Dart API.

## IDs

Every root collection needs exactly one persisted id field named `dbId`.

```dart
@collection
class Task {
  Id dbId = autoIncrement;
  late String title;
}
```

The id uniquely identifies one object inside its collection. Generated CRUD
helpers use ids for methods such as `get`, `getAll`, `delete`, and `deleteAll`.

```dart
final task = await db.tasks.get(taskId);
await db.tasks.delete(taskId);
```

### `Id`

`Id` is the public id type used by Cindel models and generated schemas.

```dart
class Task {
  Id dbId = autoIncrement;
}
```

Use `Id` for the persisted `dbId` field instead of using an unrelated Dart type
for collection identity.

### `autoIncrement`

Use `autoIncrement` when Cindel should assign the next id during insertion.

```dart
final task = Task()
  ..title = 'Write docs';

await db.tasks.put(task);

print(task.dbId);
```

When `put` stores an object whose id is `autoIncrement`, Cindel allocates an id
and writes it back through the generated id setter.

This is the usual choice for mutable model classes:

```dart
@collection
class Note {
  Id dbId = autoIncrement;
  late String body;
}
```

### Explicit IDs

Use an explicit id when your application already owns the id value.

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

Explicit ids are useful when ids come from imported data, deterministic test
fixtures, or another part of the application.

## Supported Field Types

Cindel persists these field shapes:

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

Example:

```dart
@collection
class Task {
  Id dbId = autoIncrement;

  late String title;
  bool completed = false;
  int priority = 0;
  DateTime createdAt = DateTime.now().toUtc();
  Duration? reminderAfter;
  List<String> tags = const [];
}
```

Nullable fields are supported when the underlying value type is supported:

```dart
@collection
class Profile {
  Id dbId = autoIncrement;

  String? displayName;
  DateTime? birthday;
}
```

Lists can contain supported non-list values:

```dart
@collection
class Article {
  Id dbId = autoIncrement;

  late String title;
  List<String> tags = const [];
}
```

Nested lists are not supported:

```dart
@collection
class Matrix {
  Id dbId = autoIncrement;

  // Not supported.
  List<List<int>> values = const [];
}
```

For structured child values, use embedded objects.

## Ignored Fields

Use `@ignore` for fields that should exist in Dart but should not be persisted.

```dart
@collection
class User {
  Id dbId = autoIncrement;

  late String email;

  @ignore
  String runtimeOnlyLabel = '';
}
```

Ignored fields are excluded from generated persistence. They are useful for
view state, temporary labels, derived values, caches, or other runtime-only
data.

Do not use `@ignore` for data that must survive database close/reopen. If the
value belongs to stored application state, make it a supported persisted field
instead.

## Enums

Cindel supports enum fields. Use `@Enumerated` to control how enum values are
stored.

```dart
enum Plan {
  free,
  pro,
}

@collection
class Subscription {
  Id dbId = autoIncrement;

  @Enumerated(CindelEnumType.name)
  Plan plan = Plan.free;
}
```

Available strategies are:

- `CindelEnumType.name`
- `CindelEnumType.ordinal`
- `CindelEnumType.value`

### Name-based enums

Use `CindelEnumType.name` to store the enum case name.

```dart
enum UserRole {
  admin,
  editor,
  viewer,
}

@collection
class User {
  Id dbId = autoIncrement;

  @Enumerated(CindelEnumType.name)
  UserRole role = UserRole.viewer;
}
```

### Ordinal enums

Use `CindelEnumType.ordinal` to store the enum index.

```dart
enum Priority {
  low,
  normal,
  high,
}

@collection
class Task {
  Id dbId = autoIncrement;

  @Enumerated(CindelEnumType.ordinal)
  Priority priority = Priority.normal;
}
```

Ordinal storage is compact, but enum order becomes part of the stored data
contract. Use it only when the enum order is stable.

### Value-based enums

Use `CindelEnumType.value` when each enum case has a stable field value.

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
  AccountStatus status = AccountStatus.active;
}
```

Value-based enum storage is useful when your application already has stable
external codes for enum values.

## Embedded Objects

Embedded objects are values stored inside a parent collection object. Use them
for structured data that does not need its own collection API.

For example, an email can have a sender and a list of recipients:

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

The `Email` is the root collection. `Recipient` and `RecipientMetadata` are
stored as part of each email document.

### Defining Embedded Objects

Declare embedded value types with `@embedded` or `@Embedded()`.

```dart
@embedded
class Address {
  late String city;
  late String country;
}

@collection
class Customer {
  Id dbId = autoIncrement;

  late String name;
  Address? billingAddress;
  List<Address> previousAddresses = const [];
}
```

Embedded objects can contain supported persisted field types, including nested
embedded objects:

```dart
@embedded
class Contact {
  String? name;
  String? email;
  Address? address;
}
```

Use embedded objects when the value belongs to its parent and is normally read
or written with that parent.

### Embedded Filters

Generated filters can query inside embedded objects.

Filter a single embedded object:

```dart
final messages = await db.emails
    .filter()
    .sender((recipient) {
      return recipient.addressEqualTo('ada@example.com');
    })
    .findAll();
```

Filter nested embedded objects:

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

Filter embedded object lists by element:

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

### Limitations

Embedded objects have these current limits:

- embedded classes do not get their own collection API,
- embedded classes are not passed directly to `Cindel.open` as schemas,
- embedded objects are stored and loaded through their parent collection,
- indexes inside embedded classes are not supported,
- put indexes on root collection fields when indexed lookup is needed,
- nested lists are not supported.

If a value needs independent lifecycle, independent ids, direct CRUD methods,
or its own collection-level queries, model it as a root collection instead.

## Freezed Models

Cindel supports Freezed classic classes and single primary-factory models.
Freezed union/sealed multi-constructor models are not supported as Cindel
collections.

### Primary Factory

For common Freezed primary-factory models, place Cindel annotations on the
factory constructor parameters.

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
    required String sku,
    required String name,
    @Default(true) bool active,
    @ignore String? runtimeLabel,
  }) = _Product;
}
```

Annotations such as `@Enumerated` and `@ignore` can be placed on factory
parameters:

```dart
enum ProductState {
  draft,
  published,
}

@freezed
@Collection(name: 'products')
abstract class Product with _$Product {
  const factory Product({
    required Id dbId,
    required String sku,
    @Enumerated(CindelEnumType.name) required ProductState state,
    @ignore String? runtimeLabel,
  }) = _Product;
}
```

Use this style when the Freezed model is primarily defined by its main factory
constructor.

### Classic Class

Cindel also supports Freezed classic classes that expose concrete final fields.

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
  final String email;

  @override
  final String name;
}
```

Use the classic class style when you want explicit final fields on the class
body.

Freezed models still follow the same collection rules as regular Cindel
models: they need a persisted `dbId`, supported persisted field types, and a
generated schema registered when the database opens.
