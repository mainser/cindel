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
      isIndexUnique: false,
      indexCaseSensitive: true,
      indexType: CindelIndexType.value,
    ),
    CindelFieldSchema(
      name: "name",
      dartType: "String",
      isId: false,
      isIndexed: false,
      isIndexUnique: false,
      indexCaseSensitive: true,
      indexType: CindelIndexType.value,
    ),
    CindelFieldSchema(
      name: "email",
      dartType: "String",
      isId: false,
      isIndexed: true,
      isIndexUnique: false,
      indexCaseSensitive: true,
      indexType: CindelIndexType.value,
    ),
    CindelFieldSchema(
      name: "username",
      dartType: "String?",
      isId: false,
      isIndexed: true,
      isIndexUnique: true,
      indexCaseSensitive: true,
      indexType: CindelIndexType.value,
    ),
    CindelFieldSchema(
      name: "displayName",
      dartType: "String?",
      isId: false,
      isIndexed: true,
      isIndexUnique: false,
      indexCaseSensitive: false,
      indexType: CindelIndexType.value,
    ),
    CindelFieldSchema(
      name: "accessToken",
      dartType: "String?",
      isId: false,
      isIndexed: true,
      isIndexUnique: false,
      indexCaseSensitive: true,
      indexType: CindelIndexType.hash,
    ),
    CindelFieldSchema(
      name: "bio",
      dartType: "String?",
      isId: false,
      isIndexed: true,
      isIndexUnique: false,
      indexCaseSensitive: false,
      indexType: CindelIndexType.words,
    ),
    CindelFieldSchema(
      name: "active",
      dartType: "bool?",
      isId: false,
      isIndexed: false,
      isIndexUnique: false,
      indexCaseSensitive: true,
      indexType: CindelIndexType.value,
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

extension UserCindelQueryModifierAccess on CindelQuery<User> {
  CindelQuery<User> sortById({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return sortBy("id", order: order);
  }

  CindelQuery<User> sortByIdDesc() {
    return sortBy("id", order: CindelSortOrder.descending);
  }

  CindelQuery<User> thenById({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return thenBy("id", order: order);
  }

  CindelQuery<User> thenByIdDesc() {
    return thenBy("id", order: CindelSortOrder.descending);
  }

  CindelQuery<User> distinctById() {
    return distinctBy("id");
  }

  CindelPropertyQuery<User, int> idProperty() {
    return property<int>("id");
  }

  CindelQuery<User> sortByName({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return sortBy("name", order: order);
  }

  CindelQuery<User> sortByNameDesc() {
    return sortBy("name", order: CindelSortOrder.descending);
  }

  CindelQuery<User> thenByName({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return thenBy("name", order: order);
  }

  CindelQuery<User> thenByNameDesc() {
    return thenBy("name", order: CindelSortOrder.descending);
  }

  CindelQuery<User> distinctByName() {
    return distinctBy("name");
  }

  CindelPropertyQuery<User, String> nameProperty() {
    return property<String>("name");
  }

  CindelQuery<User> sortByEmail({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return sortBy("email", order: order);
  }

  CindelQuery<User> sortByEmailDesc() {
    return sortBy("email", order: CindelSortOrder.descending);
  }

  CindelQuery<User> thenByEmail({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return thenBy("email", order: order);
  }

  CindelQuery<User> thenByEmailDesc() {
    return thenBy("email", order: CindelSortOrder.descending);
  }

  CindelQuery<User> distinctByEmail() {
    return distinctBy("email");
  }

  CindelPropertyQuery<User, String> emailProperty() {
    return property<String>("email");
  }

  CindelQuery<User> sortByUsername({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return sortBy("username", order: order);
  }

  CindelQuery<User> sortByUsernameDesc() {
    return sortBy("username", order: CindelSortOrder.descending);
  }

  CindelQuery<User> thenByUsername({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return thenBy("username", order: order);
  }

  CindelQuery<User> thenByUsernameDesc() {
    return thenBy("username", order: CindelSortOrder.descending);
  }

  CindelQuery<User> distinctByUsername() {
    return distinctBy("username");
  }

  CindelPropertyQuery<User, String?> usernameProperty() {
    return property<String?>("username");
  }

  CindelQuery<User> sortByDisplayName({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return sortBy("displayName", order: order);
  }

  CindelQuery<User> sortByDisplayNameDesc() {
    return sortBy("displayName", order: CindelSortOrder.descending);
  }

  CindelQuery<User> thenByDisplayName({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return thenBy("displayName", order: order);
  }

  CindelQuery<User> thenByDisplayNameDesc() {
    return thenBy("displayName", order: CindelSortOrder.descending);
  }

  CindelQuery<User> distinctByDisplayName() {
    return distinctBy("displayName");
  }

  CindelPropertyQuery<User, String?> displayNameProperty() {
    return property<String?>("displayName");
  }

  CindelQuery<User> sortByAccessToken({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return sortBy("accessToken", order: order);
  }

  CindelQuery<User> sortByAccessTokenDesc() {
    return sortBy("accessToken", order: CindelSortOrder.descending);
  }

  CindelQuery<User> thenByAccessToken({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return thenBy("accessToken", order: order);
  }

  CindelQuery<User> thenByAccessTokenDesc() {
    return thenBy("accessToken", order: CindelSortOrder.descending);
  }

  CindelQuery<User> distinctByAccessToken() {
    return distinctBy("accessToken");
  }

  CindelPropertyQuery<User, String?> accessTokenProperty() {
    return property<String?>("accessToken");
  }

  CindelQuery<User> sortByBio({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return sortBy("bio", order: order);
  }

  CindelQuery<User> sortByBioDesc() {
    return sortBy("bio", order: CindelSortOrder.descending);
  }

  CindelQuery<User> thenByBio({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return thenBy("bio", order: order);
  }

  CindelQuery<User> thenByBioDesc() {
    return thenBy("bio", order: CindelSortOrder.descending);
  }

  CindelQuery<User> distinctByBio() {
    return distinctBy("bio");
  }

  CindelPropertyQuery<User, String?> bioProperty() {
    return property<String?>("bio");
  }

  CindelQuery<User> sortByActive({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return sortBy("active", order: order);
  }

  CindelQuery<User> sortByActiveDesc() {
    return sortBy("active", order: CindelSortOrder.descending);
  }

  CindelQuery<User> thenByActive({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return thenBy("active", order: order);
  }

  CindelQuery<User> thenByActiveDesc() {
    return thenBy("active", order: CindelSortOrder.descending);
  }

  CindelQuery<User> distinctByActive() {
    return distinctBy("active");
  }

  CindelPropertyQuery<User, bool?> activeProperty() {
    return property<bool?>("active");
  }
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

  CindelQuery<User> usernameEqualTo(String value) {
    return CindelQuery.equal(
      database: _collection.database,
      schema: UserSchema,
      field: "username",
      value: value,
    );
  }

  CindelQuery<User> usernameStartsWith(String prefix) {
    return CindelQuery.stringStartsWith(
      database: _collection.database,
      schema: UserSchema,
      field: "username",
      prefix: prefix,
    );
  }

  CindelQuery<User> usernameBetween(String? lower, String? upper) {
    return CindelQuery.range(
      database: _collection.database,
      schema: UserSchema,
      field: "username",
      lower: lower,
      upper: upper,
    );
  }

  CindelQuery<User> displayNameEqualTo(String value) {
    return CindelQuery.equal(
      database: _collection.database,
      schema: UserSchema,
      field: "displayName",
      value: value,
    );
  }

  CindelQuery<User> displayNameStartsWith(String prefix) {
    return CindelQuery.stringStartsWith(
      database: _collection.database,
      schema: UserSchema,
      field: "displayName",
      prefix: prefix,
    );
  }

  CindelQuery<User> displayNameBetween(String? lower, String? upper) {
    return CindelQuery.range(
      database: _collection.database,
      schema: UserSchema,
      field: "displayName",
      lower: lower,
      upper: upper,
    );
  }

  CindelQuery<User> accessTokenEqualTo(String value) {
    return CindelQuery.equal(
      database: _collection.database,
      schema: UserSchema,
      field: "accessToken",
      value: value,
    );
  }

  CindelQuery<User> bioEqualTo(String word) {
    return bioWordEqualTo(word);
  }

  CindelQuery<User> bioStartsWith(String prefix) {
    return bioWordStartsWith(prefix);
  }

  CindelQuery<User> bioWordEqualTo(String word) {
    return CindelQuery.wordsContain(
      database: _collection.database,
      schema: UserSchema,
      field: "bio",
      word: word,
    );
  }

  CindelQuery<User> bioWordStartsWith(String prefix) {
    return CindelQuery.wordsStartWith(
      database: _collection.database,
      schema: UserSchema,
      field: "bio",
      prefix: prefix,
    );
  }

  CindelQuery<User> bioWordsContain(String word) {
    return bioWordEqualTo(word);
  }

  CindelQuery<User> bioWordsStartWith(String prefix) {
    return bioWordStartsWith(prefix);
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

  CindelQuery<User> usernameEqualTo(String? value) {
    return _query.whereMatches(CindelFilter.field("username").equalTo(value));
  }

  CindelQuery<User> usernameContains(String value) {
    return _query.whereMatches(CindelFilter.field("username").contains(value));
  }

  CindelQuery<User> usernameStartsWith(String value) {
    return _query.whereMatches(
      CindelFilter.field("username").startsWith(value),
    );
  }

  CindelQuery<User> usernameEndsWith(String value) {
    return _query.whereMatches(CindelFilter.field("username").endsWith(value));
  }

  CindelQuery<User> displayNameEqualTo(String? value) {
    return _query.whereMatches(
      CindelFilter.field("displayName").equalTo(value),
    );
  }

  CindelQuery<User> displayNameContains(String value) {
    return _query.whereMatches(
      CindelFilter.field("displayName").contains(value),
    );
  }

  CindelQuery<User> displayNameStartsWith(String value) {
    return _query.whereMatches(
      CindelFilter.field("displayName").startsWith(value),
    );
  }

  CindelQuery<User> displayNameEndsWith(String value) {
    return _query.whereMatches(
      CindelFilter.field("displayName").endsWith(value),
    );
  }

  CindelQuery<User> accessTokenEqualTo(String? value) {
    return _query.whereMatches(
      CindelFilter.field("accessToken").equalTo(value),
    );
  }

  CindelQuery<User> bioEqualTo(String? value) {
    return _query.whereMatches(CindelFilter.field("bio").equalTo(value));
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
    "username": object.username,
    "displayName": object.displayName,
    "accessToken": object.accessToken,
    "bio": object.bio,
    "active": object.active,
  };
}

User _$UserFromCindelDocument(Map<String, Object?> document) {
  final object = User();
  object.id = document["id"] as int;
  object.name = document["name"] as String;
  object.email = document["email"] as String;
  object.username = document["username"] as String?;
  object.displayName = document["displayName"] as String?;
  object.accessToken = document["accessToken"] as String?;
  object.bio = document["bio"] as String?;
  object.active = document["active"] as bool?;
  return object;
}

void _$UserSetCindelId(User object, int id) {
  object.id = id;
}
