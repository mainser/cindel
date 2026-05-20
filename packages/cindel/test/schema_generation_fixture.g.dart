// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'schema_generation_fixture.dart';

// **************************************************************************
// CindelGenerator
// **************************************************************************

// ignore_for_file: constant_identifier_names

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
);

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
