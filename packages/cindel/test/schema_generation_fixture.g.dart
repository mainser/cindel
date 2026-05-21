// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'schema_generation_fixture.dart';

// **************************************************************************
// CindelGenerator
// **************************************************************************

// ignore_for_file: non_constant_identifier_names

final UserSchema = CindelCollectionSchema<User>(
  name: "users",
  dartName: "User",
  idField: "id",
  fields: <CindelFieldSchema>[
    CindelFieldSchema(
      name: "id",
      dartType: "int",
      isId: true,
      isIndexed: false,
    ),
    CindelFieldSchema(
      name: "name",
      dartType: "String",
      isId: false,
      isIndexed: false,
    ),
    CindelFieldSchema(
      name: "email",
      dartType: "String",
      isId: false,
      isIndexed: true,
    ),
    CindelFieldSchema(
      name: "active",
      dartType: "bool?",
      isId: false,
      isIndexed: false,
    ),
  ],
  toDocument: _$UserToCindelDocument,
  fromDocument: _$UserFromCindelDocument,
  setId: _$UserSetCindelId,
);

extension UserCindelCollectionAccess on CindelDatabase {
  CindelTypedCollection<User> get users => typedCollection(UserSchema);
}

extension UserCindelQueryAccess on CindelTypedCollection<User> {
  UserQueryWhere where() => UserQueryWhere(this);
}

final class UserQueryWhere {
  const UserQueryWhere(this._collection);

  final CindelTypedCollection<User> _collection;

  CindelQuery<User> emailEqualTo(String value) {
    return CindelQuery.equal(
      database: _collection.database,
      schema: UserSchema,
      field: "email",
      value: value,
    );
  }

  CindelQuery<User> emailStartsWith(String prefix) {
    return CindelQuery.stringStartsWith(
      database: _collection.database,
      schema: UserSchema,
      field: "email",
      prefix: prefix,
    );
  }

  CindelQuery<User> emailBetween(String? lower, String? upper) {
    return CindelQuery.range(
      database: _collection.database,
      schema: UserSchema,
      field: "email",
      lower: lower,
      upper: upper,
    );
  }
}

Map<String, Object?> _$UserToCindelDocument(User object) {
  return <String, Object?>{
    "id": object.id,
    "name": object.name,
    "email": object.email,
    "active": object.active,
  };
}

User _$UserFromCindelDocument(Map<String, Object?> document) {
  final object = User();
  object.id = document["id"] as int;
  object.name = document["name"] as String;
  object.email = document["email"] as String;
  object.active = document["active"] as bool?;
  return object;
}

void _$UserSetCindelId(User object, int id) {
  object.id = id;
}
