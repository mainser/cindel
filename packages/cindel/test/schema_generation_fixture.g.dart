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

  UserQueryFilter filter() =>
      UserQueryFilter(CindelQuery.all(database: database, schema: UserSchema));
}

extension UserCindelQueryFilterAccess on CindelQuery<User> {
  UserQueryFilter filter() => UserQueryFilter(this);
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

final class UserQueryFilter {
  const UserQueryFilter(this._query);

  final CindelQuery<User> _query;

  CindelQuery<User> idEqualTo(int value) {
    return _query.whereMatches(CindelFilter.field("id").equalTo(value));
  }

  CindelQuery<User> idGreaterThan(int value) {
    return _query.whereMatches(CindelFilter.field("id").greaterThan(value));
  }

  CindelQuery<User> idGreaterThanOrEqualTo(int value) {
    return _query.whereMatches(
      CindelFilter.field("id").greaterThanOrEqualTo(value),
    );
  }

  CindelQuery<User> idLessThan(int value) {
    return _query.whereMatches(CindelFilter.field("id").lessThan(value));
  }

  CindelQuery<User> idLessThanOrEqualTo(int value) {
    return _query.whereMatches(
      CindelFilter.field("id").lessThanOrEqualTo(value),
    );
  }

  CindelQuery<User> idBetween(int? lower, int? upper) {
    return _query.whereMatches(CindelFilter.field("id").between(lower, upper));
  }

  CindelQuery<User> nameEqualTo(String value) {
    return _query.whereMatches(CindelFilter.field("name").equalTo(value));
  }

  CindelQuery<User> nameContains(String value) {
    return _query.whereMatches(CindelFilter.field("name").contains(value));
  }

  CindelQuery<User> nameStartsWith(String value) {
    return _query.whereMatches(CindelFilter.field("name").startsWith(value));
  }

  CindelQuery<User> nameEndsWith(String value) {
    return _query.whereMatches(CindelFilter.field("name").endsWith(value));
  }

  CindelQuery<User> emailEqualTo(String value) {
    return _query.whereMatches(CindelFilter.field("email").equalTo(value));
  }

  CindelQuery<User> emailContains(String value) {
    return _query.whereMatches(CindelFilter.field("email").contains(value));
  }

  CindelQuery<User> emailStartsWith(String value) {
    return _query.whereMatches(CindelFilter.field("email").startsWith(value));
  }

  CindelQuery<User> emailEndsWith(String value) {
    return _query.whereMatches(CindelFilter.field("email").endsWith(value));
  }

  CindelQuery<User> activeEqualTo(bool? value) {
    return _query.whereMatches(CindelFilter.field("active").equalTo(value));
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
