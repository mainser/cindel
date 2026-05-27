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
      binaryType: "int",
      isId: true,
      isIndexed: false,
      isIndexUnique: false,
      indexCaseSensitive: true,
      indexType: CindelIndexType.value,
    ),
    CindelFieldSchema(
      name: "name",
      dartType: "String",
      binaryType: "string",
      isId: false,
      isIndexed: false,
      isIndexUnique: false,
      indexCaseSensitive: true,
      indexType: CindelIndexType.value,
    ),
    CindelFieldSchema(
      name: "email",
      dartType: "String",
      binaryType: "string",
      isId: false,
      isIndexed: true,
      isIndexUnique: false,
      indexCaseSensitive: true,
      indexType: CindelIndexType.value,
    ),
    CindelFieldSchema(
      name: "username",
      dartType: "String?",
      binaryType: "string",
      isId: false,
      isIndexed: true,
      isIndexUnique: true,
      indexCaseSensitive: true,
      indexType: CindelIndexType.value,
    ),
    CindelFieldSchema(
      name: "displayName",
      dartType: "String?",
      binaryType: "string",
      isId: false,
      isIndexed: true,
      isIndexUnique: false,
      indexCaseSensitive: false,
      indexType: CindelIndexType.value,
    ),
    CindelFieldSchema(
      name: "accessToken",
      dartType: "String?",
      binaryType: "string",
      isId: false,
      isIndexed: true,
      isIndexUnique: false,
      indexCaseSensitive: true,
      indexType: CindelIndexType.hash,
    ),
    CindelFieldSchema(
      name: "bio",
      dartType: "String?",
      binaryType: "string",
      isId: false,
      isIndexed: true,
      isIndexUnique: false,
      indexCaseSensitive: false,
      indexType: CindelIndexType.words,
    ),
    CindelFieldSchema(
      name: "active",
      dartType: "bool?",
      binaryType: "bool",
      isId: false,
      isIndexed: false,
      isIndexUnique: false,
      indexCaseSensitive: true,
      indexType: CindelIndexType.value,
    ),
    CindelFieldSchema(
      name: "createdAt",
      dartType: "DateTime",
      binaryType: "int",
      isId: false,
      isIndexed: true,
      isIndexUnique: false,
      indexCaseSensitive: true,
      indexType: CindelIndexType.value,
    ),
    CindelFieldSchema(
      name: "sessionLength",
      dartType: "Duration?",
      binaryType: "int",
      isId: false,
      isIndexed: false,
      isIndexUnique: false,
      indexCaseSensitive: true,
      indexType: CindelIndexType.value,
    ),
    CindelFieldSchema(
      name: "tags",
      dartType: "List<String>",
      binaryType: "list",
      isId: false,
      isIndexed: true,
      isIndexUnique: false,
      indexCaseSensitive: false,
      indexType: CindelIndexType.multiEntry,
    ),
    CindelFieldSchema(
      name: "scores",
      dartType: "List<int>?",
      binaryType: "list",
      isId: false,
      isIndexed: false,
      isIndexUnique: false,
      indexCaseSensitive: true,
      indexType: CindelIndexType.value,
    ),
    CindelFieldSchema(
      name: "role",
      dartType: "UserRole",
      binaryType: "string",
      isId: false,
      isIndexed: false,
      isIndexUnique: false,
      indexCaseSensitive: true,
      indexType: CindelIndexType.value,
    ),
    CindelFieldSchema(
      name: "status",
      dartType: "UserStatus",
      binaryType: "int",
      isId: false,
      isIndexed: true,
      isIndexUnique: false,
      indexCaseSensitive: true,
      indexType: CindelIndexType.value,
    ),
    CindelFieldSchema(
      name: "plan",
      dartType: "UserPlan",
      binaryType: "string",
      isId: false,
      isIndexed: false,
      isIndexUnique: false,
      indexCaseSensitive: true,
      indexType: CindelIndexType.value,
    ),
    CindelFieldSchema(
      name: "primaryRecipient",
      dartType: "Recipient?",
      binaryType: "object",
      isId: false,
      isIndexed: false,
      isIndexUnique: false,
      indexCaseSensitive: true,
      indexType: CindelIndexType.value,
    ),
    CindelFieldSchema(
      name: "recipients",
      dartType: "List<Recipient>?",
      binaryType: "list",
      isId: false,
      isIndexed: false,
      isIndexUnique: false,
      indexCaseSensitive: true,
      indexType: CindelIndexType.value,
    ),
  ],
  compositeIndexes: <CindelCompositeIndexSchema>[
    CindelCompositeIndexSchema(
      name: "email_active",
      fields: <String>["email", "active"],
      isUnique: false,
      caseSensitive: true,
    ),
  ],
  toDocument: _$UserToCindelDocument,
  fromDocument: _$UserFromCindelDocument,
  toBinaryDocument: _$UserToCindelBinaryDocument,
  fromBinaryDocument: _$UserFromCindelBinaryDocument,
  getId: _$UserGetCindelId,
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

  CindelQuery<User> sortByCreatedAt({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return sortBy("createdAt", order: order);
  }

  CindelQuery<User> sortByCreatedAtDesc() {
    return sortBy("createdAt", order: CindelSortOrder.descending);
  }

  CindelQuery<User> thenByCreatedAt({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return thenBy("createdAt", order: order);
  }

  CindelQuery<User> thenByCreatedAtDesc() {
    return thenBy("createdAt", order: CindelSortOrder.descending);
  }

  CindelQuery<User> distinctByCreatedAt() {
    return distinctBy("createdAt");
  }

  CindelPropertyQuery<User, DateTime> createdAtProperty() {
    return property<DateTime>(
      "createdAt",
      decode: (value) =>
          DateTime.fromMicrosecondsSinceEpoch(value as int, isUtc: true),
    );
  }

  CindelQuery<User> sortBySessionLength({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return sortBy("sessionLength", order: order);
  }

  CindelQuery<User> sortBySessionLengthDesc() {
    return sortBy("sessionLength", order: CindelSortOrder.descending);
  }

  CindelQuery<User> thenBySessionLength({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return thenBy("sessionLength", order: order);
  }

  CindelQuery<User> thenBySessionLengthDesc() {
    return thenBy("sessionLength", order: CindelSortOrder.descending);
  }

  CindelQuery<User> distinctBySessionLength() {
    return distinctBy("sessionLength");
  }

  CindelPropertyQuery<User, Duration?> sessionLengthProperty() {
    return property<Duration?>(
      "sessionLength",
      decode: (value) =>
          value == null ? null : Duration(microseconds: value as int),
    );
  }

  CindelQuery<User> sortByTags({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return sortBy("tags", order: order);
  }

  CindelQuery<User> sortByTagsDesc() {
    return sortBy("tags", order: CindelSortOrder.descending);
  }

  CindelQuery<User> thenByTags({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return thenBy("tags", order: order);
  }

  CindelQuery<User> thenByTagsDesc() {
    return thenBy("tags", order: CindelSortOrder.descending);
  }

  CindelQuery<User> distinctByTags() {
    return distinctBy("tags");
  }

  CindelPropertyQuery<User, List<String>> tagsProperty() {
    return property<List<String>>(
      "tags",
      decode: (value) => (value as List<Object?>)
          .map((value) => value as String)
          .toList(growable: false),
    );
  }

  CindelQuery<User> sortByScores({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return sortBy("scores", order: order);
  }

  CindelQuery<User> sortByScoresDesc() {
    return sortBy("scores", order: CindelSortOrder.descending);
  }

  CindelQuery<User> thenByScores({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return thenBy("scores", order: order);
  }

  CindelQuery<User> thenByScoresDesc() {
    return thenBy("scores", order: CindelSortOrder.descending);
  }

  CindelQuery<User> distinctByScores() {
    return distinctBy("scores");
  }

  CindelPropertyQuery<User, List<int>?> scoresProperty() {
    return property<List<int>?>(
      "scores",
      decode: (value) => value == null
          ? null
          : (value as List<Object?>)
                .map((value) => value as int)
                .toList(growable: false),
    );
  }

  CindelQuery<User> sortByRole({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return sortBy("role", order: order);
  }

  CindelQuery<User> sortByRoleDesc() {
    return sortBy("role", order: CindelSortOrder.descending);
  }

  CindelQuery<User> thenByRole({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return thenBy("role", order: order);
  }

  CindelQuery<User> thenByRoleDesc() {
    return thenBy("role", order: CindelSortOrder.descending);
  }

  CindelQuery<User> distinctByRole() {
    return distinctBy("role");
  }

  CindelPropertyQuery<User, UserRole> roleProperty() {
    return property<UserRole>(
      "role",
      decode: (value) => UserRole.values.byName(value as String),
    );
  }

  CindelQuery<User> sortByStatus({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return sortBy("status", order: order);
  }

  CindelQuery<User> sortByStatusDesc() {
    return sortBy("status", order: CindelSortOrder.descending);
  }

  CindelQuery<User> thenByStatus({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return thenBy("status", order: order);
  }

  CindelQuery<User> thenByStatusDesc() {
    return thenBy("status", order: CindelSortOrder.descending);
  }

  CindelQuery<User> distinctByStatus() {
    return distinctBy("status");
  }

  CindelPropertyQuery<User, UserStatus> statusProperty() {
    return property<UserStatus>(
      "status",
      decode: (value) => UserStatus.values[value as int],
    );
  }

  CindelQuery<User> sortByPlan({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return sortBy("plan", order: order);
  }

  CindelQuery<User> sortByPlanDesc() {
    return sortBy("plan", order: CindelSortOrder.descending);
  }

  CindelQuery<User> thenByPlan({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return thenBy("plan", order: order);
  }

  CindelQuery<User> thenByPlanDesc() {
    return thenBy("plan", order: CindelSortOrder.descending);
  }

  CindelQuery<User> distinctByPlan() {
    return distinctBy("plan");
  }

  CindelPropertyQuery<User, UserPlan> planProperty() {
    return property<UserPlan>(
      "plan",
      decode: (value) =>
          UserPlan.values.firstWhere((enumValue) => enumValue.code == value),
    );
  }

  CindelQuery<User> sortByPrimaryRecipient({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return sortBy("primaryRecipient", order: order);
  }

  CindelQuery<User> sortByPrimaryRecipientDesc() {
    return sortBy("primaryRecipient", order: CindelSortOrder.descending);
  }

  CindelQuery<User> thenByPrimaryRecipient({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return thenBy("primaryRecipient", order: order);
  }

  CindelQuery<User> thenByPrimaryRecipientDesc() {
    return thenBy("primaryRecipient", order: CindelSortOrder.descending);
  }

  CindelQuery<User> distinctByPrimaryRecipient() {
    return distinctBy("primaryRecipient");
  }

  CindelPropertyQuery<User, Recipient?> primaryRecipientProperty() {
    return property<Recipient?>(
      "primaryRecipient",
      decode: (value) => value == null
          ? null
          : _$RecipientFromCindelEmbedded(
              (value as Map).cast<String, Object?>(),
            ),
    );
  }

  CindelQuery<User> sortByRecipients({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return sortBy("recipients", order: order);
  }

  CindelQuery<User> sortByRecipientsDesc() {
    return sortBy("recipients", order: CindelSortOrder.descending);
  }

  CindelQuery<User> thenByRecipients({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return thenBy("recipients", order: order);
  }

  CindelQuery<User> thenByRecipientsDesc() {
    return thenBy("recipients", order: CindelSortOrder.descending);
  }

  CindelQuery<User> distinctByRecipients() {
    return distinctBy("recipients");
  }

  CindelPropertyQuery<User, List<Recipient>?> recipientsProperty() {
    return property<List<Recipient>?>(
      "recipients",
      decode: (value) => value == null
          ? null
          : (value as List<Object?>)
                .map(
                  (value) => _$RecipientFromCindelEmbedded(
                    (value as Map).cast<String, Object?>(),
                  ),
                )
                .toList(growable: false),
    );
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

  CindelQuery<User> createdAtEqualTo(DateTime value) {
    return CindelQuery.equal(
      database: _collection.database,
      schema: UserSchema,
      field: "createdAt",
      value: value.microsecondsSinceEpoch,
    );
  }

  CindelQuery<User> createdAtBetween(DateTime? lower, DateTime? upper) {
    return CindelQuery.range(
      database: _collection.database,
      schema: UserSchema,
      field: "createdAt",
      lower: lower?.microsecondsSinceEpoch,
      upper: upper?.microsecondsSinceEpoch,
    );
  }

  CindelQuery<User> tagsContains(String value) {
    return CindelQuery.equal(
      database: _collection.database,
      schema: UserSchema,
      field: "tags",
      value: value,
    );
  }

  CindelQuery<User> statusEqualTo(UserStatus value) {
    return CindelQuery.equal(
      database: _collection.database,
      schema: UserSchema,
      field: "status",
      value: value.index,
    );
  }

  CindelQuery<User> emailActiveEqualTo(String email, bool active) {
    return CindelQuery.compositeEqual(
      database: _collection.database,
      schema: UserSchema,
      index: "email_active",
      values: <Object>[email, active],
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

  CindelQuery<User> createdAtEqualTo(DateTime value) {
    return _query.whereMatches(
      CindelFilter.field("createdAt").equalTo(value.microsecondsSinceEpoch),
    );
  }

  CindelQuery<User> createdAtGreaterThan(DateTime value) {
    return _query.whereMatches(
      CindelFilter.field("createdAt").greaterThan(value.microsecondsSinceEpoch),
    );
  }

  CindelQuery<User> createdAtGreaterThanOrEqualTo(DateTime value) {
    return _query.whereMatches(
      CindelFilter.field(
        "createdAt",
      ).greaterThanOrEqualTo(value.microsecondsSinceEpoch),
    );
  }

  CindelQuery<User> createdAtLessThan(DateTime value) {
    return _query.whereMatches(
      CindelFilter.field("createdAt").lessThan(value.microsecondsSinceEpoch),
    );
  }

  CindelQuery<User> createdAtLessThanOrEqualTo(DateTime value) {
    return _query.whereMatches(
      CindelFilter.field(
        "createdAt",
      ).lessThanOrEqualTo(value.microsecondsSinceEpoch),
    );
  }

  CindelQuery<User> createdAtBetween(DateTime? lower, DateTime? upper) {
    return _query.whereMatches(
      CindelFilter.field(
        "createdAt",
      ).between(lower?.microsecondsSinceEpoch, upper?.microsecondsSinceEpoch),
    );
  }

  CindelQuery<User> sessionLengthEqualTo(Duration? value) {
    return _query.whereMatches(
      CindelFilter.field("sessionLength").equalTo(value?.inMicroseconds),
    );
  }

  CindelQuery<User> sessionLengthGreaterThan(Duration value) {
    return _query.whereMatches(
      CindelFilter.field("sessionLength").greaterThan(value.inMicroseconds),
    );
  }

  CindelQuery<User> sessionLengthGreaterThanOrEqualTo(Duration value) {
    return _query.whereMatches(
      CindelFilter.field(
        "sessionLength",
      ).greaterThanOrEqualTo(value.inMicroseconds),
    );
  }

  CindelQuery<User> sessionLengthLessThan(Duration value) {
    return _query.whereMatches(
      CindelFilter.field("sessionLength").lessThan(value.inMicroseconds),
    );
  }

  CindelQuery<User> sessionLengthLessThanOrEqualTo(Duration value) {
    return _query.whereMatches(
      CindelFilter.field(
        "sessionLength",
      ).lessThanOrEqualTo(value.inMicroseconds),
    );
  }

  CindelQuery<User> sessionLengthBetween(Duration? lower, Duration? upper) {
    return _query.whereMatches(
      CindelFilter.field(
        "sessionLength",
      ).between(lower?.inMicroseconds, upper?.inMicroseconds),
    );
  }

  CindelQuery<User> tagsEqualTo(List<String> value) {
    return _query.whereMatches(
      CindelFilter.field(
        "tags",
      ).equalTo(value.map((value) => value).toList(growable: false)),
    );
  }

  CindelQuery<User> scoresEqualTo(List<int>? value) {
    return _query.whereMatches(
      CindelFilter.field(
        "scores",
      ).equalTo(value?.map((value) => value).toList(growable: false)),
    );
  }

  CindelQuery<User> roleEqualTo(UserRole value) {
    return _query.whereMatches(CindelFilter.field("role").equalTo(value.name));
  }

  CindelQuery<User> statusEqualTo(UserStatus value) {
    return _query.whereMatches(
      CindelFilter.field("status").equalTo(value.index),
    );
  }

  CindelQuery<User> planEqualTo(UserPlan value) {
    return _query.whereMatches(CindelFilter.field("plan").equalTo(value.code));
  }

  CindelQuery<User> primaryRecipientEqualTo(Recipient? value) {
    return _query.whereMatches(
      CindelFilter.field(
        "primaryRecipient",
      ).equalTo(value == null ? null : _$RecipientToCindelEmbedded(value)),
    );
  }

  CindelQuery<User> recipientsEqualTo(List<Recipient>? value) {
    return _query.whereMatches(
      CindelFilter.field("recipients").equalTo(
        value
            ?.map((value) => _$RecipientToCindelEmbedded(value))
            .toList(growable: false),
      ),
    );
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
    "createdAt": object.createdAt.microsecondsSinceEpoch,
    "sessionLength": object.sessionLength?.inMicroseconds,
    "tags": object.tags.map((value) => value).toList(growable: false),
    "scores": object.scores?.map((value) => value).toList(growable: false),
    "role": object.role.name,
    "status": object.status.index,
    "plan": object.plan.code,
    "primaryRecipient": object.primaryRecipient == null
        ? null
        : _$RecipientToCindelEmbedded(object.primaryRecipient as Recipient),
    "recipients": object.recipients
        ?.map((value) => _$RecipientToCindelEmbedded(value))
        .toList(growable: false),
  };
}

User _$UserFromCindelDocument(Map<String, Object?> document) {
  final object = User();
  object.id = document["id"] as int;
  object.name = document["name"] as String;
  object.email = document["email"] as String;
  object.username = document["username"] == null
      ? null
      : document["username"] as String?;
  object.displayName = document["displayName"] == null
      ? null
      : document["displayName"] as String?;
  object.accessToken = document["accessToken"] == null
      ? null
      : document["accessToken"] as String?;
  object.bio = document["bio"] == null ? null : document["bio"] as String?;
  object.active = document["active"] == null
      ? null
      : document["active"] as bool?;
  object.createdAt = DateTime.fromMicrosecondsSinceEpoch(
    document["createdAt"] as int,
    isUtc: true,
  );
  object.sessionLength = document["sessionLength"] == null
      ? null
      : Duration(microseconds: document["sessionLength"] as int);
  object.tags = (document["tags"] as List<Object?>)
      .map((value) => value as String)
      .toList(growable: false);
  object.scores = document["scores"] == null
      ? null
      : (document["scores"] as List<Object?>)
            .map((value) => value as int)
            .toList(growable: false);
  object.role = UserRole.values.byName(document["role"] as String);
  object.status = UserStatus.values[document["status"] as int];
  object.plan = UserPlan.values.firstWhere(
    (enumValue) => enumValue.code == document["plan"],
  );
  object.primaryRecipient = document["primaryRecipient"] == null
      ? null
      : _$RecipientFromCindelEmbedded(
          (document["primaryRecipient"] as Map).cast<String, Object?>(),
        );
  object.recipients = document["recipients"] == null
      ? null
      : (document["recipients"] as List<Object?>)
            .map(
              (value) => _$RecipientFromCindelEmbedded(
                (value as Map).cast<String, Object?>(),
              ),
            )
            .toList(growable: false);
  return object;
}

CindelBinaryDocumentBytes _$UserToCindelBinaryDocument(User object) {
  return cindelEncodeSchemaBinaryDocument(
    <Object?>[
      object.accessToken,
      object.active,
      object.bio,
      object.createdAt.microsecondsSinceEpoch,
      object.displayName,
      object.email,
      object.name,
      object.plan.code,
      object.primaryRecipient == null
          ? null
          : _$RecipientToCindelEmbedded(object.primaryRecipient as Recipient),
      object.recipients
          ?.map((value) => _$RecipientToCindelEmbedded(value))
          .toList(growable: false),
      object.role.name,
      object.scores?.map((value) => value).toList(growable: false),
      object.sessionLength?.inMicroseconds,
      object.status.index,
      object.tags.map((value) => value).toList(growable: false),
      object.username,
    ],
    const <CindelBinaryFieldType>[
      CindelBinaryFieldType.stringValue,
      CindelBinaryFieldType.boolValue,
      CindelBinaryFieldType.stringValue,
      CindelBinaryFieldType.intValue,
      CindelBinaryFieldType.stringValue,
      CindelBinaryFieldType.stringValue,
      CindelBinaryFieldType.stringValue,
      CindelBinaryFieldType.stringValue,
      CindelBinaryFieldType.objectValue,
      CindelBinaryFieldType.listValue,
      CindelBinaryFieldType.stringValue,
      CindelBinaryFieldType.listValue,
      CindelBinaryFieldType.intValue,
      CindelBinaryFieldType.intValue,
      CindelBinaryFieldType.listValue,
      CindelBinaryFieldType.stringValue,
    ],
  );
}

User _$UserFromCindelBinaryDocument(CindelBinaryDocumentBytes bytes) {
  final reader = CindelSchemaBinaryDocumentReader(bytes, staticSize: 61);
  final Object? field0 = reader.readString(0, 0);
  final Object? field1 = reader.readBool(1, 3);
  final Object? field2 = reader.readString(2, 4);
  final Object? field3 = reader.readInt(3, 7);
  final Object? field4 = reader.readString(4, 15);
  final Object? field5 = reader.readString(5, 18);
  final Object? field6 = reader.readString(6, 21);
  final Object? field7 = reader.readString(7, 24);
  final Object? field8 = reader.readObject(8, 27);
  final Object? field9 = reader.readList(9, 30);
  final Object? field10 = reader.readString(10, 33);
  final Object? field11 = reader.readList(11, 36);
  final Object? field12 = reader.readInt(12, 39);
  final Object? field13 = reader.readInt(13, 47);
  final Object? field14 = reader.readList(14, 55);
  final Object? field15 = reader.readString(15, 58);
  final object = User();
  object.id = autoIncrement;
  object.name = field6 as String;
  object.email = field5 as String;
  object.username = field15 == null ? null : field15 as String?;
  object.displayName = field4 == null ? null : field4 as String?;
  object.accessToken = field0 == null ? null : field0 as String?;
  object.bio = field2 == null ? null : field2 as String?;
  object.active = field1 == null ? null : field1 as bool?;
  object.createdAt = DateTime.fromMicrosecondsSinceEpoch(
    field3 as int,
    isUtc: true,
  );
  object.sessionLength = field12 == null
      ? null
      : Duration(microseconds: field12 as int);
  object.tags = (field14 as List<Object?>)
      .map((value) => value as String)
      .toList(growable: false);
  object.scores = field11 == null
      ? null
      : (field11 as List<Object?>)
            .map((value) => value as int)
            .toList(growable: false);
  object.role = UserRole.values.byName(field10 as String);
  object.status = UserStatus.values[field13 as int];
  object.plan = UserPlan.values.firstWhere(
    (enumValue) => enumValue.code == field7,
  );
  object.primaryRecipient = field8 == null
      ? null
      : _$RecipientFromCindelEmbedded((field8 as Map).cast<String, Object?>());
  object.recipients = field9 == null
      ? null
      : (field9 as List<Object?>)
            .map(
              (value) => _$RecipientFromCindelEmbedded(
                (value as Map).cast<String, Object?>(),
              ),
            )
            .toList(growable: false);
  return object;
}

int _$UserGetCindelId(User object) {
  return object.id;
}

void _$UserSetCindelId(User object, int id) {
  object.id = id;
}

Map<String, Object?> _$RecipientToCindelEmbedded(Recipient object) {
  return <String, Object?>{
    "name": object.name,
    "address": object.address,
    "metadata": object.metadata == null
        ? null
        : _$RecipientMetadataToCindelEmbedded(
            object.metadata as RecipientMetadata,
          ),
  };
}

Recipient _$RecipientFromCindelEmbedded(Map<String, Object?> document) {
  final object = Recipient();
  object.name = document["name"] == null ? null : document["name"] as String?;
  object.address = document["address"] == null
      ? null
      : document["address"] as String?;
  object.metadata = document["metadata"] == null
      ? null
      : _$RecipientMetadataFromCindelEmbedded(
          (document["metadata"] as Map).cast<String, Object?>(),
        );
  return object;
}

Map<String, Object?> _$RecipientMetadataToCindelEmbedded(
  RecipientMetadata object,
) {
  return <String, Object?>{"label": object.label};
}

RecipientMetadata _$RecipientMetadataFromCindelEmbedded(
  Map<String, Object?> document,
) {
  final object = RecipientMetadata();
  object.label = document["label"] == null
      ? null
      : document["label"] as String?;
  return object;
}

// ignore_for_file: non_constant_identifier_names

final ImmutableUserSchema = CindelCollectionSchema<ImmutableUser>(
  name: "immutableUsers",
  dartName: "ImmutableUser",
  idField: "id",
  fields: <CindelFieldSchema>[
    CindelFieldSchema(
      name: "id",
      dartType: "int",
      binaryType: "int",
      isId: true,
      isIndexed: false,
      isIndexUnique: false,
      indexCaseSensitive: true,
      indexType: CindelIndexType.value,
    ),
    CindelFieldSchema(
      name: "email",
      dartType: "String",
      binaryType: "string",
      isId: false,
      isIndexed: true,
      isIndexUnique: false,
      indexCaseSensitive: true,
      indexType: CindelIndexType.value,
    ),
    CindelFieldSchema(
      name: "active",
      dartType: "bool",
      binaryType: "bool",
      isId: false,
      isIndexed: false,
      isIndexUnique: false,
      indexCaseSensitive: true,
      indexType: CindelIndexType.value,
    ),
  ],
  compositeIndexes: <CindelCompositeIndexSchema>[],
  toDocument: _$ImmutableUserToCindelDocument,
  fromDocument: _$ImmutableUserFromCindelDocument,
  toBinaryDocument: _$ImmutableUserToCindelBinaryDocument,
  fromBinaryDocument: _$ImmutableUserFromCindelBinaryDocument,
  writeNativeDocument: _$ImmutableUserWriteCindelNativeDocument,
  readNativeDocument: _$ImmutableUserReadCindelNativeDocument,
  getId: _$ImmutableUserGetCindelId,
);

extension ImmutableUserCindelCollectionAccess on CindelDatabase {
  CindelTypedCollection<ImmutableUser> get immutableUsers =>
      typedCollection(ImmutableUserSchema);
}

extension ImmutableUserCindelQueryAccess
    on CindelTypedCollection<ImmutableUser> {
  ImmutableUserQueryWhere where() => ImmutableUserQueryWhere(this);

  ImmutableUserQueryFilter filter() => ImmutableUserQueryFilter(
    CindelQuery.all(database: database, schema: ImmutableUserSchema),
  );
}

extension ImmutableUserCindelQueryFilterAccess on CindelQuery<ImmutableUser> {
  ImmutableUserQueryFilter filter() => ImmutableUserQueryFilter(this);
}

extension ImmutableUserCindelQueryModifierAccess on CindelQuery<ImmutableUser> {
  CindelQuery<ImmutableUser> sortById({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return sortBy("id", order: order);
  }

  CindelQuery<ImmutableUser> sortByIdDesc() {
    return sortBy("id", order: CindelSortOrder.descending);
  }

  CindelQuery<ImmutableUser> thenById({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return thenBy("id", order: order);
  }

  CindelQuery<ImmutableUser> thenByIdDesc() {
    return thenBy("id", order: CindelSortOrder.descending);
  }

  CindelQuery<ImmutableUser> distinctById() {
    return distinctBy("id");
  }

  CindelPropertyQuery<ImmutableUser, int> idProperty() {
    return property<int>("id");
  }

  CindelQuery<ImmutableUser> sortByEmail({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return sortBy("email", order: order);
  }

  CindelQuery<ImmutableUser> sortByEmailDesc() {
    return sortBy("email", order: CindelSortOrder.descending);
  }

  CindelQuery<ImmutableUser> thenByEmail({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return thenBy("email", order: order);
  }

  CindelQuery<ImmutableUser> thenByEmailDesc() {
    return thenBy("email", order: CindelSortOrder.descending);
  }

  CindelQuery<ImmutableUser> distinctByEmail() {
    return distinctBy("email");
  }

  CindelPropertyQuery<ImmutableUser, String> emailProperty() {
    return property<String>("email");
  }

  CindelQuery<ImmutableUser> sortByActive({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return sortBy("active", order: order);
  }

  CindelQuery<ImmutableUser> sortByActiveDesc() {
    return sortBy("active", order: CindelSortOrder.descending);
  }

  CindelQuery<ImmutableUser> thenByActive({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return thenBy("active", order: order);
  }

  CindelQuery<ImmutableUser> thenByActiveDesc() {
    return thenBy("active", order: CindelSortOrder.descending);
  }

  CindelQuery<ImmutableUser> distinctByActive() {
    return distinctBy("active");
  }

  CindelPropertyQuery<ImmutableUser, bool> activeProperty() {
    return property<bool>("active");
  }
}

final class ImmutableUserQueryWhere {
  const ImmutableUserQueryWhere(this._collection);

  final CindelTypedCollection<ImmutableUser> _collection;

  CindelQuery<ImmutableUser> emailEqualTo(String value) {
    return CindelQuery.equal(
      database: _collection.database,
      schema: ImmutableUserSchema,
      field: "email",
      value: value,
    );
  }

  CindelQuery<ImmutableUser> emailStartsWith(String prefix) {
    return CindelQuery.stringStartsWith(
      database: _collection.database,
      schema: ImmutableUserSchema,
      field: "email",
      prefix: prefix,
    );
  }

  CindelQuery<ImmutableUser> emailBetween(String? lower, String? upper) {
    return CindelQuery.range(
      database: _collection.database,
      schema: ImmutableUserSchema,
      field: "email",
      lower: lower,
      upper: upper,
    );
  }
}

final class ImmutableUserQueryFilter {
  const ImmutableUserQueryFilter(this._query);

  final CindelQuery<ImmutableUser> _query;

  CindelQuery<ImmutableUser> idEqualTo(int value) {
    return _query.whereMatches(CindelFilter.field("id").equalTo(value));
  }

  CindelQuery<ImmutableUser> idGreaterThan(int value) {
    return _query.whereMatches(CindelFilter.field("id").greaterThan(value));
  }

  CindelQuery<ImmutableUser> idGreaterThanOrEqualTo(int value) {
    return _query.whereMatches(
      CindelFilter.field("id").greaterThanOrEqualTo(value),
    );
  }

  CindelQuery<ImmutableUser> idLessThan(int value) {
    return _query.whereMatches(CindelFilter.field("id").lessThan(value));
  }

  CindelQuery<ImmutableUser> idLessThanOrEqualTo(int value) {
    return _query.whereMatches(
      CindelFilter.field("id").lessThanOrEqualTo(value),
    );
  }

  CindelQuery<ImmutableUser> idBetween(int? lower, int? upper) {
    return _query.whereMatches(CindelFilter.field("id").between(lower, upper));
  }

  CindelQuery<ImmutableUser> emailEqualTo(String value) {
    return _query.whereMatches(CindelFilter.field("email").equalTo(value));
  }

  CindelQuery<ImmutableUser> emailContains(String value) {
    return _query.whereMatches(CindelFilter.field("email").contains(value));
  }

  CindelQuery<ImmutableUser> emailStartsWith(String value) {
    return _query.whereMatches(CindelFilter.field("email").startsWith(value));
  }

  CindelQuery<ImmutableUser> emailEndsWith(String value) {
    return _query.whereMatches(CindelFilter.field("email").endsWith(value));
  }

  CindelQuery<ImmutableUser> activeEqualTo(bool value) {
    return _query.whereMatches(CindelFilter.field("active").equalTo(value));
  }
}

Map<String, Object?> _$ImmutableUserToCindelDocument(ImmutableUser object) {
  return <String, Object?>{
    "id": object.id,
    "email": object.email,
    "active": object.active,
  };
}

ImmutableUser _$ImmutableUserFromCindelDocument(Map<String, Object?> document) {
  return ImmutableUser(
    id: document["id"] as int,
    email: document["email"] as String,
    active: document["active"] as bool,
  );
}

CindelBinaryDocumentBytes _$ImmutableUserToCindelBinaryDocument(
  ImmutableUser object,
) {
  return cindelEncodeSchemaBinaryDocument(
    <Object?>[object.active, object.email],
    const <CindelBinaryFieldType>[
      CindelBinaryFieldType.boolValue,
      CindelBinaryFieldType.stringValue,
    ],
  );
}

ImmutableUser _$ImmutableUserFromCindelBinaryDocument(
  CindelBinaryDocumentBytes bytes,
) {
  final reader = CindelSchemaBinaryDocumentReader(bytes, staticSize: 4);
  final Object? field0 = reader.readBool(0, 0);
  final Object? field1 = reader.readString(1, 1);
  return ImmutableUser(
    id: autoIncrement,
    email: field1 as String,
    active: field0 as bool,
  );
}

void _$ImmutableUserWriteCindelNativeDocument(
  CindelNativeDocumentWriter writer,
  ImmutableUser object,
) {
  writer.writeBool(0, object.active);
  writer.writeString(1, object.email);
}

ImmutableUser _$ImmutableUserReadCindelNativeDocument(
  CindelNativeDocumentReader reader,
  int documentIndex,
) {
  return ImmutableUser(
    id: reader.readId(documentIndex),
    email: reader.readString(documentIndex, 1) as String,
    active: reader.readBool(documentIndex, 0) as bool,
  );
}

int _$ImmutableUserGetCindelId(ImmutableUser object) {
  return object.id;
}
