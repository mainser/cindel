# Data Modeling

Cindel models are Dart classes that describe the data your app wants to store.
A root model becomes a collection, its fields become stored values, and code
generation creates the schema and typed API used by the rest of the app.

This guide focuses on model shape: collections, ids, field names, supported
field types, ignored fields, enums, embedded objects, and Freezed models. It
does not try to document every generated collection or query method.

## Collections

Use a collection for data that has its own identity and lifecycle in your app:
users, projects, tasks, products, orders, settings, cached records, and similar
root data.

```dart
import 'package:cindel/cindel.dart';

part 'user.g.dart';

@Collection(name: 'users')
class User {
  Id dbId = autoIncrement;

  @Index(unique: true)
  late String email;

  late String name;
  bool active = true;
}
```

After generation, this model gives the app:

- a schema constant such as `UserSchema`,
- a generated collection getter such as `db.users`,
- typed reads and writes for `User`,
- generated query helpers based on the fields and indexes.

### `@Collection`

Use `@Collection(...)` when you want to configure the stored collection.

```dart
@Collection(name: 'users')
class User {
  Id dbId = autoIncrement;
  late String email;
}
```

The `name` is the persisted collection name. It is stored with the database and
is the name Cindel uses whenever that collection is opened, migrated, backed
up, restored, or synced.

Keep persisted names stable once real data exists. Renaming a Dart class is
ordinary refactoring; changing the stored collection name changes the database
format your app expects.

Use a collection when the object should be saved, loaded, queried, deleted, or
linked independently.

### `@collection`

`@collection` is shorthand for `@Collection()` when defaults are enough.

```dart
@collection
class Project {
  Id dbId = autoIncrement;
  late String title;
}
```

When no name is provided, the generator derives the collection name from the
Dart class name. This is convenient for simple apps and tests. Use
`@Collection(name: ...)` when you want the stored name to be explicit.

### `@Name`

Use `@Name` when the stored name should differ from the Dart name.

```dart
@Name('accounts')
@collection
class Account {
  Id dbId = autoIncrement;

  @Name('user_name')
  @Index(unique: true, replace: true)
  late String username;
}
```

In Dart, the app still works with `Account`, `AccountSchema`, `db.accounts`,
and `username`. In storage, the collection is named `accounts` and the field is
named `user_name`.

`@Name` is useful when you want to keep a stored format stable while improving
Dart naming, or when the stored format must follow a naming convention that is
different from the Dart API.

## IDs

Every root collection needs one persisted id field named `dbId`.

```dart
@collection
class Task {
  Id dbId = autoIncrement;
  late String title;
}
```

The id identifies one object inside its collection. Generated collection
methods use ids for operations such as `get`, `getAll`, `delete`, and
`deleteAll`.

### `Id`

Use `Id` for the persisted `dbId` field.

```dart
class Task {
  Id dbId = autoIncrement;
}
```

Do not replace it with an unrelated Dart type for collection identity. The
generated schema and collection API expect Cindel's `Id` type.

### `autoIncrement`

Use `autoIncrement` when Cindel should assign the id when the object is first
stored.

```dart
final task = Task()
  ..title = 'Write docs';

await db.tasks.put(task);

print(task.dbId);
```

After `put`, the generated id setter writes the allocated id back to the
object. This is the usual style for mutable model classes.

### Explicit IDs

Use an explicit id when your app already owns the id value.

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

Explicit ids are useful for imported data, deterministic fixtures, or app
domains where another layer already assigns stable local ids.

## Persisted Fields

Cindel persists fields whose types are supported and are not marked with
`@ignore`.

Supported field shapes are:

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

Nullable fields are fine when the underlying value type is supported:

```dart
@collection
class Profile {
  Id dbId = autoIncrement;

  String? displayName;
  DateTime? birthday;
}
```

Lists can contain supported values:

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

For structured child values, use embedded objects. For independently stored
objects, use another root collection.

## Ignored Fields

Use `@ignore` for fields that should exist in Dart but should not be stored.

```dart
@collection
class User {
  Id dbId = autoIncrement;

  late String email;

  @ignore
  String runtimeOnlyLabel = '';
}
```

Ignored fields are useful for:

- UI-only labels,
- temporary selection state,
- derived values that can be recomputed,
- caches that do not need to survive close and reopen,
- fields used only while building a screen or command.

Do not mark real app data as ignored. If a value must be available after the
database is reopened, model it as a supported persisted field.

## Enums

Cindel can persist enum fields. Use `@Enumerated` to choose how the enum is
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

### Name-Based Enums

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

This is usually the easiest strategy to read and debug. Treat enum case names
as stored data once the app has persisted records.

### Ordinal Enums

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
contract. Only use it when you can keep that order stable.

### Value-Based Enums

Use `CindelEnumType.value` when every enum case has a stable field value.

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

Value-based enum storage is useful when your app already has durable external
codes, such as server values, import formats, or business identifiers.

## Embedded Objects

Embedded objects are value objects stored inside a parent collection object.
They are useful for structured data that belongs to its parent and is normally
read or written with that parent.

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

`Email` is the root collection. `Recipient` and `RecipientMetadata` are stored
inside each email record.

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

Use an embedded object when the value does not need its own id, direct CRUD
methods, or independent collection-level queries.

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

### Embedded Object Limits

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

Cindel supports two Freezed shapes:

- classic classes with concrete final fields,
- single primary-factory models.

Freezed union or sealed multi-constructor models are not supported as Cindel
collections.

### Primary Factory

For a Freezed primary-factory model, place Cindel annotations on the factory
constructor parameters.

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
    @Index(unique: true) required String sku,
    @Index() required String name,
    @Default(true) bool active,
    @ignore String? runtimeLabel,
  }) = _Product;
}
```

Annotations such as `@Index`, `@Enumerated`, and `@ignore` can be placed on
factory parameters:

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

Use this style when the model is primarily defined by one Freezed factory.

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
  @Index(unique: true)
  final String email;

  @override
  final String name;
}
```

Use the classic class style when you want explicit final fields in the class
body.

Freezed models follow the same collection rules as regular Cindel models: they
need one persisted `dbId`, supported persisted field types, generated code, and
a generated schema registered when the database opens.

## Modeling Checklist

Before generating code, check the model from the app's point of view:

- Is this a root thing the app saves independently? Use a collection.
- Is this a value that only belongs to a parent object? Use an embedded object.
- Does the collection have exactly one persisted `dbId`?
- Should Cindel assign ids, or does the app provide explicit ids?
- Are all persisted fields supported by Cindel?
- Are runtime-only fields marked with `@ignore`?
- Are enum storage choices stable enough for persisted data?
- Are stored names stable if real users already have data?
- Are Freezed models limited to supported single-shape models?
