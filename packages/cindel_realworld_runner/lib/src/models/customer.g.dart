// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'customer.dart';

// **************************************************************************
// CindelGenerator
// **************************************************************************

// ignore_for_file: non_constant_identifier_names

final CustomerSchema = CindelCollectionSchema<Customer>(
  name: "customers",
  dartName: "Customer",
  idField: "dbId",
  fields: <CindelFieldSchema>[
    CindelFieldSchema(
      name: "dbId",
      dartType: "int",
      binaryType: "int",
      isId: true,
      isIndexed: false,
      isIndexUnique: false,
      isIndexReplace: false,
      indexCaseSensitive: true,
      indexType: CindelIndexType.value,
    ),
    CindelFieldSchema(
      name: "email",
      dartType: "String",
      binaryType: "string",
      isId: false,
      isIndexed: true,
      isIndexUnique: true,
      isIndexReplace: true,
      indexCaseSensitive: false,
      indexType: CindelIndexType.value,
    ),
    CindelFieldSchema(
      name: "name",
      dartType: "String",
      binaryType: "string",
      isId: false,
      isIndexed: false,
      isIndexUnique: false,
      isIndexReplace: false,
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
      isIndexReplace: false,
      indexCaseSensitive: true,
      indexType: CindelIndexType.value,
    ),
    CindelFieldSchema(
      name: "loyaltyPoints",
      dartType: "int",
      binaryType: "int",
      isId: false,
      isIndexed: false,
      isIndexUnique: false,
      isIndexReplace: false,
      indexCaseSensitive: true,
      indexType: CindelIndexType.value,
    ),
    CindelFieldSchema(
      name: "lifetimeValue",
      dartType: "double",
      binaryType: "double",
      isId: false,
      isIndexed: false,
      isIndexUnique: false,
      isIndexReplace: false,
      indexCaseSensitive: true,
      indexType: CindelIndexType.value,
    ),
    CindelFieldSchema(
      name: "signedUpAt",
      dartType: "DateTime",
      binaryType: "int",
      isId: false,
      isIndexed: true,
      isIndexUnique: false,
      isIndexReplace: false,
      indexCaseSensitive: true,
      indexType: CindelIndexType.value,
    ),
    CindelFieldSchema(
      name: "preferredResponseTime",
      dartType: "Duration?",
      binaryType: "int",
      isId: false,
      isIndexed: false,
      isIndexUnique: false,
      isIndexReplace: false,
      indexCaseSensitive: true,
      indexType: CindelIndexType.value,
    ),
    CindelFieldSchema(
      name: "status",
      dartType: "CustomerStatus",
      binaryType: "string",
      isId: false,
      isIndexed: false,
      isIndexUnique: false,
      isIndexReplace: false,
      indexCaseSensitive: true,
      indexType: CindelIndexType.value,
    ),
    CindelFieldSchema(
      name: "tier",
      dartType: "CustomerTier",
      binaryType: "string",
      isId: false,
      isIndexed: false,
      isIndexUnique: false,
      isIndexReplace: false,
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
      isIndexReplace: false,
      indexCaseSensitive: false,
      indexType: CindelIndexType.multiEntry,
    ),
    CindelFieldSchema(
      name: "defaultShippingAddress",
      dartType: "CustomerAddress?",
      binaryType: "object",
      isId: false,
      isIndexed: false,
      isIndexUnique: false,
      isIndexReplace: false,
      indexCaseSensitive: true,
      indexType: CindelIndexType.value,
    ),
    CindelFieldSchema(
      name: "savedAddresses",
      dartType: "List<CustomerAddress>",
      binaryType: "list",
      isId: false,
      isIndexed: false,
      isIndexUnique: false,
      isIndexReplace: false,
      indexCaseSensitive: true,
      indexType: CindelIndexType.value,
    ),
  ],
  links: <CindelLinkSchema>[
    CindelLinkSchema(
      name: "orders",
      dartName: "orders",
      targetCollection: "orders",
      isToMany: true,
      isBacklink: true,
      backlinkTo: "customer",
    ),
  ],
  compositeIndexes: <CindelCompositeIndexSchema>[
    CindelCompositeIndexSchema(
      name: "email_active",
      fields: <String>["email", "active"],
      isUnique: false,
      isReplace: false,
      caseSensitive: true,
    ),
  ],
  toDocument: _$CustomerToCindelDocument,
  fromDocument: _$CustomerFromCindelDocument,
  toBinaryDocument: _$CustomerToCindelBinaryDocument,
  fromBinaryDocument: _$CustomerFromCindelBinaryDocument,
  writeNativeDocument: _$CustomerWriteCindelNativeDocument,
  readNativeDocument: _$CustomerReadCindelNativeDocument,
  getId: _$CustomerGetCindelId,
  setId: _$CustomerSetCindelId,
  bindLinks: _$CustomerBindCindelLinks,
);

void _$CustomerBindCindelLinks(
  Object database,
  CindelCollectionSchema<Customer> schema,
  Customer object,
) {
  final cindelDatabase = database as CindelDatabase;
  final ownerSchema = schema as dynamic;
  object.orders.bind(
    cindelDatabase,
    ownerSchema,
    object,
    schema.links.firstWhere((link) => link.dartName == "orders"),
  );
}

extension CustomerCindelCollectionAccess on CindelDatabase {
  CindelTypedCollection<Customer> get customers =>
      typedCollection(CustomerSchema);
}

extension CustomerCindelQueryAccess on CindelTypedCollection<Customer> {
  CustomerQueryWhere where() => CustomerQueryWhere(this);

  CustomerQueryFilter filter() => CustomerQueryFilter(
    CindelQuery.all(database: database, schema: CustomerSchema),
  );

  Future<void> putByEmail(Customer object) {
    return putByUniqueIndex(
      object,
      indexName: "email",
      values: <Object?>[object.email],
      isComposite: false,
    );
  }

  Future<void> putAllByEmail(Iterable<Customer> objects) {
    return putAllByUniqueIndex(
      objects,
      indexName: "email",
      values: (object) => <Object?>[object.email],
      isComposite: false,
    );
  }
}

extension CustomerCindelQueryFilterAccess on CindelQuery<Customer> {
  CustomerQueryFilter filter() => CustomerQueryFilter(this);
}

extension CustomerCindelQueryModifierAccess on CindelQuery<Customer> {
  CindelQuery<Customer> sortByDbId({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return sortBy("dbId", order: order);
  }

  CindelQuery<Customer> sortByDbIdDesc() {
    return sortBy("dbId", order: CindelSortOrder.descending);
  }

  CindelQuery<Customer> thenByDbId({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return thenBy("dbId", order: order);
  }

  CindelQuery<Customer> thenByDbIdDesc() {
    return thenBy("dbId", order: CindelSortOrder.descending);
  }

  CindelQuery<Customer> distinctByDbId() {
    return distinctBy("dbId");
  }

  CindelPropertyQuery<Customer, int> dbIdProperty() {
    return property<int>("dbId");
  }

  CindelQuery<Customer> sortByEmail({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return sortBy("email", order: order);
  }

  CindelQuery<Customer> sortByEmailDesc() {
    return sortBy("email", order: CindelSortOrder.descending);
  }

  CindelQuery<Customer> thenByEmail({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return thenBy("email", order: order);
  }

  CindelQuery<Customer> thenByEmailDesc() {
    return thenBy("email", order: CindelSortOrder.descending);
  }

  CindelQuery<Customer> distinctByEmail() {
    return distinctBy("email");
  }

  CindelPropertyQuery<Customer, String> emailProperty() {
    return property<String>("email");
  }

  CindelQuery<Customer> sortByName({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return sortBy("name", order: order);
  }

  CindelQuery<Customer> sortByNameDesc() {
    return sortBy("name", order: CindelSortOrder.descending);
  }

  CindelQuery<Customer> thenByName({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return thenBy("name", order: order);
  }

  CindelQuery<Customer> thenByNameDesc() {
    return thenBy("name", order: CindelSortOrder.descending);
  }

  CindelQuery<Customer> distinctByName() {
    return distinctBy("name");
  }

  CindelPropertyQuery<Customer, String> nameProperty() {
    return property<String>("name");
  }

  CindelQuery<Customer> sortByActive({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return sortBy("active", order: order);
  }

  CindelQuery<Customer> sortByActiveDesc() {
    return sortBy("active", order: CindelSortOrder.descending);
  }

  CindelQuery<Customer> thenByActive({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return thenBy("active", order: order);
  }

  CindelQuery<Customer> thenByActiveDesc() {
    return thenBy("active", order: CindelSortOrder.descending);
  }

  CindelQuery<Customer> distinctByActive() {
    return distinctBy("active");
  }

  CindelPropertyQuery<Customer, bool> activeProperty() {
    return property<bool>("active");
  }

  CindelQuery<Customer> sortByLoyaltyPoints({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return sortBy("loyaltyPoints", order: order);
  }

  CindelQuery<Customer> sortByLoyaltyPointsDesc() {
    return sortBy("loyaltyPoints", order: CindelSortOrder.descending);
  }

  CindelQuery<Customer> thenByLoyaltyPoints({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return thenBy("loyaltyPoints", order: order);
  }

  CindelQuery<Customer> thenByLoyaltyPointsDesc() {
    return thenBy("loyaltyPoints", order: CindelSortOrder.descending);
  }

  CindelQuery<Customer> distinctByLoyaltyPoints() {
    return distinctBy("loyaltyPoints");
  }

  CindelPropertyQuery<Customer, int> loyaltyPointsProperty() {
    return property<int>("loyaltyPoints");
  }

  CindelQuery<Customer> sortByLifetimeValue({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return sortBy("lifetimeValue", order: order);
  }

  CindelQuery<Customer> sortByLifetimeValueDesc() {
    return sortBy("lifetimeValue", order: CindelSortOrder.descending);
  }

  CindelQuery<Customer> thenByLifetimeValue({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return thenBy("lifetimeValue", order: order);
  }

  CindelQuery<Customer> thenByLifetimeValueDesc() {
    return thenBy("lifetimeValue", order: CindelSortOrder.descending);
  }

  CindelQuery<Customer> distinctByLifetimeValue() {
    return distinctBy("lifetimeValue");
  }

  CindelPropertyQuery<Customer, double> lifetimeValueProperty() {
    return property<double>("lifetimeValue");
  }

  CindelQuery<Customer> sortBySignedUpAt({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return sortBy("signedUpAt", order: order);
  }

  CindelQuery<Customer> sortBySignedUpAtDesc() {
    return sortBy("signedUpAt", order: CindelSortOrder.descending);
  }

  CindelQuery<Customer> thenBySignedUpAt({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return thenBy("signedUpAt", order: order);
  }

  CindelQuery<Customer> thenBySignedUpAtDesc() {
    return thenBy("signedUpAt", order: CindelSortOrder.descending);
  }

  CindelQuery<Customer> distinctBySignedUpAt() {
    return distinctBy("signedUpAt");
  }

  CindelPropertyQuery<Customer, DateTime> signedUpAtProperty() {
    return property<DateTime>(
      "signedUpAt",
      decode: (value) =>
          DateTime.fromMicrosecondsSinceEpoch(value as int, isUtc: true),
    );
  }

  CindelQuery<Customer> sortByPreferredResponseTime({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return sortBy("preferredResponseTime", order: order);
  }

  CindelQuery<Customer> sortByPreferredResponseTimeDesc() {
    return sortBy("preferredResponseTime", order: CindelSortOrder.descending);
  }

  CindelQuery<Customer> thenByPreferredResponseTime({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return thenBy("preferredResponseTime", order: order);
  }

  CindelQuery<Customer> thenByPreferredResponseTimeDesc() {
    return thenBy("preferredResponseTime", order: CindelSortOrder.descending);
  }

  CindelQuery<Customer> distinctByPreferredResponseTime() {
    return distinctBy("preferredResponseTime");
  }

  CindelPropertyQuery<Customer, Duration?> preferredResponseTimeProperty() {
    return property<Duration?>(
      "preferredResponseTime",
      decode: (value) =>
          value == null ? null : Duration(microseconds: value as int),
    );
  }

  CindelQuery<Customer> sortByStatus({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return sortBy("status", order: order);
  }

  CindelQuery<Customer> sortByStatusDesc() {
    return sortBy("status", order: CindelSortOrder.descending);
  }

  CindelQuery<Customer> thenByStatus({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return thenBy("status", order: order);
  }

  CindelQuery<Customer> thenByStatusDesc() {
    return thenBy("status", order: CindelSortOrder.descending);
  }

  CindelQuery<Customer> distinctByStatus() {
    return distinctBy("status");
  }

  CindelPropertyQuery<Customer, CustomerStatus> statusProperty() {
    return property<CustomerStatus>(
      "status",
      decode: (value) => CustomerStatus.values.byName(value as String),
    );
  }

  CindelQuery<Customer> sortByTier({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return sortBy("tier", order: order);
  }

  CindelQuery<Customer> sortByTierDesc() {
    return sortBy("tier", order: CindelSortOrder.descending);
  }

  CindelQuery<Customer> thenByTier({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return thenBy("tier", order: order);
  }

  CindelQuery<Customer> thenByTierDesc() {
    return thenBy("tier", order: CindelSortOrder.descending);
  }

  CindelQuery<Customer> distinctByTier() {
    return distinctBy("tier");
  }

  CindelPropertyQuery<Customer, CustomerTier> tierProperty() {
    return property<CustomerTier>(
      "tier",
      decode: (value) => CustomerTier.values.firstWhere(
        (enumValue) => enumValue.code == value,
      ),
    );
  }

  CindelQuery<Customer> sortByTags({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return sortBy("tags", order: order);
  }

  CindelQuery<Customer> sortByTagsDesc() {
    return sortBy("tags", order: CindelSortOrder.descending);
  }

  CindelQuery<Customer> thenByTags({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return thenBy("tags", order: order);
  }

  CindelQuery<Customer> thenByTagsDesc() {
    return thenBy("tags", order: CindelSortOrder.descending);
  }

  CindelQuery<Customer> distinctByTags() {
    return distinctBy("tags");
  }

  CindelPropertyQuery<Customer, List<String>> tagsProperty() {
    return property<List<String>>(
      "tags",
      decode: (value) => (value as List<Object?>)
          .map((value) => value as String)
          .toList(growable: false),
    );
  }

  CindelQuery<Customer> sortByDefaultShippingAddress({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return sortBy("defaultShippingAddress", order: order);
  }

  CindelQuery<Customer> sortByDefaultShippingAddressDesc() {
    return sortBy("defaultShippingAddress", order: CindelSortOrder.descending);
  }

  CindelQuery<Customer> thenByDefaultShippingAddress({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return thenBy("defaultShippingAddress", order: order);
  }

  CindelQuery<Customer> thenByDefaultShippingAddressDesc() {
    return thenBy("defaultShippingAddress", order: CindelSortOrder.descending);
  }

  CindelQuery<Customer> distinctByDefaultShippingAddress() {
    return distinctBy("defaultShippingAddress");
  }

  CindelPropertyQuery<Customer, CustomerAddress?>
  defaultShippingAddressProperty() {
    return property<CustomerAddress?>(
      "defaultShippingAddress",
      decode: (value) => value == null
          ? null
          : _$CustomerAddressFromCindelEmbedded(
              (value as Map).cast<String, Object?>(),
            ),
    );
  }

  CindelQuery<Customer> sortBySavedAddresses({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return sortBy("savedAddresses", order: order);
  }

  CindelQuery<Customer> sortBySavedAddressesDesc() {
    return sortBy("savedAddresses", order: CindelSortOrder.descending);
  }

  CindelQuery<Customer> thenBySavedAddresses({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return thenBy("savedAddresses", order: order);
  }

  CindelQuery<Customer> thenBySavedAddressesDesc() {
    return thenBy("savedAddresses", order: CindelSortOrder.descending);
  }

  CindelQuery<Customer> distinctBySavedAddresses() {
    return distinctBy("savedAddresses");
  }

  CindelPropertyQuery<Customer, List<CustomerAddress>>
  savedAddressesProperty() {
    return property<List<CustomerAddress>>(
      "savedAddresses",
      decode: (value) => (value as List<Object?>)
          .map(
            (value) => _$CustomerAddressFromCindelEmbedded(
              (value as Map).cast<String, Object?>(),
            ),
          )
          .toList(growable: false),
    );
  }
}

final class CustomerQueryFilter {
  const CustomerQueryFilter(this._query);

  final CindelQuery<Customer> _query;

  CindelQuery<Customer> dbIdEqualTo(int value) {
    return _query.whereMatches(CindelFilter.field("dbId").equalTo(value));
  }

  CindelQuery<Customer> dbIdGreaterThan(int value) {
    return _query.whereMatches(CindelFilter.field("dbId").greaterThan(value));
  }

  CindelQuery<Customer> dbIdGreaterThanOrEqualTo(int value) {
    return _query.whereMatches(
      CindelFilter.field("dbId").greaterThanOrEqualTo(value),
    );
  }

  CindelQuery<Customer> dbIdLessThan(int value) {
    return _query.whereMatches(CindelFilter.field("dbId").lessThan(value));
  }

  CindelQuery<Customer> dbIdLessThanOrEqualTo(int value) {
    return _query.whereMatches(
      CindelFilter.field("dbId").lessThanOrEqualTo(value),
    );
  }

  CindelQuery<Customer> dbIdBetween(int? lower, int? upper) {
    return _query.whereMatches(
      CindelFilter.field("dbId").between(lower, upper),
    );
  }

  CindelQuery<Customer> emailEqualTo(String value) {
    return _query.whereMatches(CindelFilter.field("email").equalTo(value));
  }

  CindelQuery<Customer> emailContains(String value) {
    return _query.whereMatches(CindelFilter.field("email").contains(value));
  }

  CindelQuery<Customer> emailStartsWith(String value) {
    return _query.whereMatches(CindelFilter.field("email").startsWith(value));
  }

  CindelQuery<Customer> emailEndsWith(String value) {
    return _query.whereMatches(CindelFilter.field("email").endsWith(value));
  }

  CindelQuery<Customer> nameEqualTo(String value) {
    return _query.whereMatches(CindelFilter.field("name").equalTo(value));
  }

  CindelQuery<Customer> nameContains(String value) {
    return _query.whereMatches(CindelFilter.field("name").contains(value));
  }

  CindelQuery<Customer> nameStartsWith(String value) {
    return _query.whereMatches(CindelFilter.field("name").startsWith(value));
  }

  CindelQuery<Customer> nameEndsWith(String value) {
    return _query.whereMatches(CindelFilter.field("name").endsWith(value));
  }

  CindelQuery<Customer> activeEqualTo(bool value) {
    return _query.whereMatches(CindelFilter.field("active").equalTo(value));
  }

  CindelQuery<Customer> loyaltyPointsEqualTo(int value) {
    return _query.whereMatches(
      CindelFilter.field("loyaltyPoints").equalTo(value),
    );
  }

  CindelQuery<Customer> loyaltyPointsGreaterThan(int value) {
    return _query.whereMatches(
      CindelFilter.field("loyaltyPoints").greaterThan(value),
    );
  }

  CindelQuery<Customer> loyaltyPointsGreaterThanOrEqualTo(int value) {
    return _query.whereMatches(
      CindelFilter.field("loyaltyPoints").greaterThanOrEqualTo(value),
    );
  }

  CindelQuery<Customer> loyaltyPointsLessThan(int value) {
    return _query.whereMatches(
      CindelFilter.field("loyaltyPoints").lessThan(value),
    );
  }

  CindelQuery<Customer> loyaltyPointsLessThanOrEqualTo(int value) {
    return _query.whereMatches(
      CindelFilter.field("loyaltyPoints").lessThanOrEqualTo(value),
    );
  }

  CindelQuery<Customer> loyaltyPointsBetween(int? lower, int? upper) {
    return _query.whereMatches(
      CindelFilter.field("loyaltyPoints").between(lower, upper),
    );
  }

  CindelQuery<Customer> lifetimeValueEqualTo(double value) {
    return _query.whereMatches(
      CindelFilter.field("lifetimeValue").equalTo(value),
    );
  }

  CindelQuery<Customer> lifetimeValueGreaterThan(double value) {
    return _query.whereMatches(
      CindelFilter.field("lifetimeValue").greaterThan(value),
    );
  }

  CindelQuery<Customer> lifetimeValueGreaterThanOrEqualTo(double value) {
    return _query.whereMatches(
      CindelFilter.field("lifetimeValue").greaterThanOrEqualTo(value),
    );
  }

  CindelQuery<Customer> lifetimeValueLessThan(double value) {
    return _query.whereMatches(
      CindelFilter.field("lifetimeValue").lessThan(value),
    );
  }

  CindelQuery<Customer> lifetimeValueLessThanOrEqualTo(double value) {
    return _query.whereMatches(
      CindelFilter.field("lifetimeValue").lessThanOrEqualTo(value),
    );
  }

  CindelQuery<Customer> lifetimeValueBetween(double? lower, double? upper) {
    return _query.whereMatches(
      CindelFilter.field("lifetimeValue").between(lower, upper),
    );
  }

  CindelQuery<Customer> signedUpAtEqualTo(DateTime value) {
    return _query.whereMatches(
      CindelFilter.field("signedUpAt").equalTo(value.microsecondsSinceEpoch),
    );
  }

  CindelQuery<Customer> signedUpAtGreaterThan(DateTime value) {
    return _query.whereMatches(
      CindelFilter.field(
        "signedUpAt",
      ).greaterThan(value.microsecondsSinceEpoch),
    );
  }

  CindelQuery<Customer> signedUpAtGreaterThanOrEqualTo(DateTime value) {
    return _query.whereMatches(
      CindelFilter.field(
        "signedUpAt",
      ).greaterThanOrEqualTo(value.microsecondsSinceEpoch),
    );
  }

  CindelQuery<Customer> signedUpAtLessThan(DateTime value) {
    return _query.whereMatches(
      CindelFilter.field("signedUpAt").lessThan(value.microsecondsSinceEpoch),
    );
  }

  CindelQuery<Customer> signedUpAtLessThanOrEqualTo(DateTime value) {
    return _query.whereMatches(
      CindelFilter.field(
        "signedUpAt",
      ).lessThanOrEqualTo(value.microsecondsSinceEpoch),
    );
  }

  CindelQuery<Customer> signedUpAtBetween(DateTime? lower, DateTime? upper) {
    return _query.whereMatches(
      CindelFilter.field(
        "signedUpAt",
      ).between(lower?.microsecondsSinceEpoch, upper?.microsecondsSinceEpoch),
    );
  }

  CindelQuery<Customer> preferredResponseTimeEqualTo(Duration? value) {
    return _query.whereMatches(
      CindelFilter.field(
        "preferredResponseTime",
      ).equalTo(value?.inMicroseconds),
    );
  }

  CindelQuery<Customer> preferredResponseTimeGreaterThan(Duration value) {
    return _query.whereMatches(
      CindelFilter.field(
        "preferredResponseTime",
      ).greaterThan(value.inMicroseconds),
    );
  }

  CindelQuery<Customer> preferredResponseTimeGreaterThanOrEqualTo(
    Duration value,
  ) {
    return _query.whereMatches(
      CindelFilter.field(
        "preferredResponseTime",
      ).greaterThanOrEqualTo(value.inMicroseconds),
    );
  }

  CindelQuery<Customer> preferredResponseTimeLessThan(Duration value) {
    return _query.whereMatches(
      CindelFilter.field(
        "preferredResponseTime",
      ).lessThan(value.inMicroseconds),
    );
  }

  CindelQuery<Customer> preferredResponseTimeLessThanOrEqualTo(Duration value) {
    return _query.whereMatches(
      CindelFilter.field(
        "preferredResponseTime",
      ).lessThanOrEqualTo(value.inMicroseconds),
    );
  }

  CindelQuery<Customer> preferredResponseTimeBetween(
    Duration? lower,
    Duration? upper,
  ) {
    return _query.whereMatches(
      CindelFilter.field(
        "preferredResponseTime",
      ).between(lower?.inMicroseconds, upper?.inMicroseconds),
    );
  }

  CindelQuery<Customer> statusEqualTo(CustomerStatus value) {
    return _query.whereMatches(
      CindelFilter.field("status").equalTo(value.name),
    );
  }

  CindelQuery<Customer> tierEqualTo(CustomerTier value) {
    return _query.whereMatches(CindelFilter.field("tier").equalTo(value.code));
  }

  CindelQuery<Customer> tagsEqualTo(List<String> value) {
    return _query.whereMatches(
      CindelFilter.field(
        "tags",
      ).equalTo(value.map((value) => value).toList(growable: false)),
    );
  }

  CindelQuery<Customer> tagsElementEqualTo(String value) {
    return _query.whereMatches(CindelFilter.field("tags").contains(value));
  }

  CindelQuery<Customer> tagsIsEmpty() {
    return _query.whereMatches(CindelFilter.field("tags").isEmpty());
  }

  CindelQuery<Customer> tagsIsNotEmpty() {
    return _query.whereMatches(CindelFilter.field("tags").isNotEmpty());
  }

  CindelQuery<Customer> tagsLengthEqualTo(int length) {
    return _query.whereMatches(
      CindelFilter.field("tags").lengthEqualTo(length),
    );
  }

  CindelQuery<Customer> tagsLengthLessThan(int length, {bool include = false}) {
    return _query.whereMatches(
      CindelFilter.field("tags").lengthLessThan(length, include: include),
    );
  }

  CindelQuery<Customer> tagsLengthGreaterThan(
    int length, {
    bool include = false,
  }) {
    return _query.whereMatches(
      CindelFilter.field("tags").lengthGreaterThan(length, include: include),
    );
  }

  CindelQuery<Customer> tagsLengthBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return _query.whereMatches(
      CindelFilter.field("tags").lengthBetween(
        lower,
        upper,
        includeLower: includeLower,
        includeUpper: includeUpper,
      ),
    );
  }

  CindelQuery<Customer> defaultShippingAddressEqualTo(CustomerAddress? value) {
    return _query.whereMatches(
      CindelFilter.field("defaultShippingAddress").equalTo(
        value == null ? null : _$CustomerAddressToCindelEmbedded(value),
      ),
    );
  }

  CindelQuery<Customer> defaultShippingAddress(
    CindelFilterPredicate Function(
      CustomerCustomerAddressCindelEmbeddedFilter q,
    )
    filter,
  ) {
    return _query.whereMatches(
      filter(
        const CustomerCustomerAddressCindelEmbeddedFilter._(<String>[
          "defaultShippingAddress",
        ]),
      ),
    );
  }

  CindelQuery<Customer> savedAddressesEqualTo(List<CustomerAddress> value) {
    return _query.whereMatches(
      CindelFilter.field("savedAddresses").equalTo(
        value
            .map((value) => _$CustomerAddressToCindelEmbedded(value))
            .toList(growable: false),
      ),
    );
  }

  CindelQuery<Customer> savedAddressesElementEqualTo(CustomerAddress value) {
    return _query.whereMatches(
      CindelFilter.field(
        "savedAddresses",
      ).contains(_$CustomerAddressToCindelEmbedded(value)),
    );
  }

  CindelQuery<Customer> savedAddressesIsEmpty() {
    return _query.whereMatches(CindelFilter.field("savedAddresses").isEmpty());
  }

  CindelQuery<Customer> savedAddressesIsNotEmpty() {
    return _query.whereMatches(
      CindelFilter.field("savedAddresses").isNotEmpty(),
    );
  }

  CindelQuery<Customer> savedAddressesLengthEqualTo(int length) {
    return _query.whereMatches(
      CindelFilter.field("savedAddresses").lengthEqualTo(length),
    );
  }

  CindelQuery<Customer> savedAddressesLengthLessThan(
    int length, {
    bool include = false,
  }) {
    return _query.whereMatches(
      CindelFilter.field(
        "savedAddresses",
      ).lengthLessThan(length, include: include),
    );
  }

  CindelQuery<Customer> savedAddressesLengthGreaterThan(
    int length, {
    bool include = false,
  }) {
    return _query.whereMatches(
      CindelFilter.field(
        "savedAddresses",
      ).lengthGreaterThan(length, include: include),
    );
  }

  CindelQuery<Customer> savedAddressesLengthBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return _query.whereMatches(
      CindelFilter.field("savedAddresses").lengthBetween(
        lower,
        upper,
        includeLower: includeLower,
        includeUpper: includeUpper,
      ),
    );
  }

  CindelQuery<Customer> savedAddressesElement(
    CindelFilterPredicate Function(
      CustomerCustomerAddressCindelEmbeddedFilter q,
    )
    filter,
  ) {
    return _query.whereMatches(
      filter(
        const CustomerCustomerAddressCindelEmbeddedFilter._(<String>[
          "savedAddresses",
        ]),
      ),
    );
  }

  CindelQuery<Customer> optional(
    bool enabled,
    CindelQuery<Customer> Function(CustomerQueryFilter q) option,
  ) {
    return _query.optional(
      enabled,
      (query) => option(CustomerQueryFilter(query)),
    );
  }

  CindelQuery<Customer> anyOf<E>(
    Iterable<E> items,
    CindelQuery<Customer> Function(CustomerQueryFilter q, E item) option,
  ) {
    return _query.anyOf(
      items,
      (query, item) => option(CustomerQueryFilter(query), item),
    );
  }

  CindelQuery<Customer> allOf<E>(
    Iterable<E> items,
    CindelQuery<Customer> Function(CustomerQueryFilter q, E item) option,
  ) {
    return _query.allOf(
      items,
      (query, item) => option(CustomerQueryFilter(query), item),
    );
  }
}

final class CustomerQueryWhere {
  const CustomerQueryWhere(this._collection);

  final CindelTypedCollection<Customer> _collection;

  CindelQuery<Customer> emailEqualTo(String value) {
    return CindelQuery.equal(
      database: _collection.database,
      schema: CustomerSchema,
      field: "email",
      value: value,
    );
  }

  CindelQuery<Customer> emailStartsWith(String prefix) {
    return CindelQuery.stringStartsWith(
      database: _collection.database,
      schema: CustomerSchema,
      field: "email",
      prefix: prefix,
    );
  }

  CindelQuery<Customer> emailBetween(String? lower, String? upper) {
    return CindelQuery.range(
      database: _collection.database,
      schema: CustomerSchema,
      field: "email",
      lower: lower,
      upper: upper,
    );
  }

  CindelQuery<Customer> signedUpAtEqualTo(DateTime value) {
    return CindelQuery.equal(
      database: _collection.database,
      schema: CustomerSchema,
      field: "signedUpAt",
      value: value.microsecondsSinceEpoch,
    );
  }

  CindelQuery<Customer> signedUpAtBetween(DateTime? lower, DateTime? upper) {
    return CindelQuery.range(
      database: _collection.database,
      schema: CustomerSchema,
      field: "signedUpAt",
      lower: lower?.microsecondsSinceEpoch,
      upper: upper?.microsecondsSinceEpoch,
    );
  }

  CindelQuery<Customer> tagsContains(String value) {
    return CindelQuery.equal(
      database: _collection.database,
      schema: CustomerSchema,
      field: "tags",
      value: value,
    );
  }

  CindelQuery<Customer> emailActiveEqualTo(String email, bool active) {
    return CindelQuery.compositeEqual(
      database: _collection.database,
      schema: CustomerSchema,
      index: "email_active",
      values: <Object>[email, active],
    );
  }
}

final class CustomerCustomerAddressCindelEmbeddedFilter {
  const CustomerCustomerAddressCindelEmbeddedFilter._(this._path);

  final List<String> _path;

  CindelFilterPredicate line1EqualTo(String? value) {
    return CindelFilter.path(<String>[..._path, "line1"]).equalTo(value);
  }

  CindelFilterPredicate line1Contains(String value) {
    return CindelFilter.path(<String>[..._path, "line1"]).contains(value);
  }

  CindelFilterPredicate line1StartsWith(String value) {
    return CindelFilter.path(<String>[..._path, "line1"]).startsWith(value);
  }

  CindelFilterPredicate line1EndsWith(String value) {
    return CindelFilter.path(<String>[..._path, "line1"]).endsWith(value);
  }

  CindelFilterPredicate cityEqualTo(String? value) {
    return CindelFilter.path(<String>[..._path, "city"]).equalTo(value);
  }

  CindelFilterPredicate cityContains(String value) {
    return CindelFilter.path(<String>[..._path, "city"]).contains(value);
  }

  CindelFilterPredicate cityStartsWith(String value) {
    return CindelFilter.path(<String>[..._path, "city"]).startsWith(value);
  }

  CindelFilterPredicate cityEndsWith(String value) {
    return CindelFilter.path(<String>[..._path, "city"]).endsWith(value);
  }

  CindelFilterPredicate countryEqualTo(String? value) {
    return CindelFilter.path(<String>[..._path, "country"]).equalTo(value);
  }

  CindelFilterPredicate countryContains(String value) {
    return CindelFilter.path(<String>[..._path, "country"]).contains(value);
  }

  CindelFilterPredicate countryStartsWith(String value) {
    return CindelFilter.path(<String>[..._path, "country"]).startsWith(value);
  }

  CindelFilterPredicate countryEndsWith(String value) {
    return CindelFilter.path(<String>[..._path, "country"]).endsWith(value);
  }

  CindelFilterPredicate postalCodeEqualTo(String? value) {
    return CindelFilter.path(<String>[..._path, "postalCode"]).equalTo(value);
  }

  CindelFilterPredicate postalCodeContains(String value) {
    return CindelFilter.path(<String>[..._path, "postalCode"]).contains(value);
  }

  CindelFilterPredicate postalCodeStartsWith(String value) {
    return CindelFilter.path(<String>[
      ..._path,
      "postalCode",
    ]).startsWith(value);
  }

  CindelFilterPredicate postalCodeEndsWith(String value) {
    return CindelFilter.path(<String>[..._path, "postalCode"]).endsWith(value);
  }

  CindelFilterPredicate locationEqualTo(CustomerGeoPoint? value) {
    return CindelFilter.path(
      <String>[..._path, "location"],
    ).equalTo(value == null ? null : _$CustomerGeoPointToCindelEmbedded(value));
  }

  CindelFilterPredicate location(
    CindelFilterPredicate Function(
      CustomerCustomerGeoPointCindelEmbeddedFilter q,
    )
    filter,
  ) {
    return filter(
      CustomerCustomerGeoPointCindelEmbeddedFilter._(<String>[
        ..._path,
        "location",
      ]),
    );
  }
}

final class CustomerCustomerGeoPointCindelEmbeddedFilter {
  const CustomerCustomerGeoPointCindelEmbeddedFilter._(this._path);

  final List<String> _path;

  CindelFilterPredicate latitudeEqualTo(double value) {
    return CindelFilter.path(<String>[..._path, "latitude"]).equalTo(value);
  }

  CindelFilterPredicate latitudeGreaterThan(double value) {
    return CindelFilter.path(<String>[..._path, "latitude"]).greaterThan(value);
  }

  CindelFilterPredicate latitudeGreaterThanOrEqualTo(double value) {
    return CindelFilter.path(<String>[
      ..._path,
      "latitude",
    ]).greaterThanOrEqualTo(value);
  }

  CindelFilterPredicate latitudeLessThan(double value) {
    return CindelFilter.path(<String>[..._path, "latitude"]).lessThan(value);
  }

  CindelFilterPredicate latitudeLessThanOrEqualTo(double value) {
    return CindelFilter.path(<String>[
      ..._path,
      "latitude",
    ]).lessThanOrEqualTo(value);
  }

  CindelFilterPredicate latitudeBetween(double? lower, double? upper) {
    return CindelFilter.path(<String>[
      ..._path,
      "latitude",
    ]).between(lower, upper);
  }

  CindelFilterPredicate longitudeEqualTo(double value) {
    return CindelFilter.path(<String>[..._path, "longitude"]).equalTo(value);
  }

  CindelFilterPredicate longitudeGreaterThan(double value) {
    return CindelFilter.path(<String>[
      ..._path,
      "longitude",
    ]).greaterThan(value);
  }

  CindelFilterPredicate longitudeGreaterThanOrEqualTo(double value) {
    return CindelFilter.path(<String>[
      ..._path,
      "longitude",
    ]).greaterThanOrEqualTo(value);
  }

  CindelFilterPredicate longitudeLessThan(double value) {
    return CindelFilter.path(<String>[..._path, "longitude"]).lessThan(value);
  }

  CindelFilterPredicate longitudeLessThanOrEqualTo(double value) {
    return CindelFilter.path(<String>[
      ..._path,
      "longitude",
    ]).lessThanOrEqualTo(value);
  }

  CindelFilterPredicate longitudeBetween(double? lower, double? upper) {
    return CindelFilter.path(<String>[
      ..._path,
      "longitude",
    ]).between(lower, upper);
  }
}

Map<String, Object?> _$CustomerToCindelDocument(Customer object) {
  return <String, Object?>{
    "email": object.email,
    "name": object.name,
    "active": object.active,
    "loyaltyPoints": object.loyaltyPoints,
    "lifetimeValue": object.lifetimeValue,
    "signedUpAt": object.signedUpAt.microsecondsSinceEpoch,
    "preferredResponseTime": object.preferredResponseTime?.inMicroseconds,
    "status": object.status.name,
    "tier": object.tier.code,
    "tags": object.tags.map((value) => value).toList(growable: false),
    "defaultShippingAddress": object.defaultShippingAddress == null
        ? null
        : _$CustomerAddressToCindelEmbedded(
            object.defaultShippingAddress as CustomerAddress,
          ),
    "savedAddresses": object.savedAddresses
        .map((value) => _$CustomerAddressToCindelEmbedded(value))
        .toList(growable: false),
  };
}

Customer _$CustomerFromCindelDocument(Map<String, Object?> document) {
  final object = Customer();
  object.dbId = document["dbId"] as int;
  object.email = document["email"] as String;
  object.name = document["name"] as String;
  object.active = document["active"] as bool;
  object.loyaltyPoints = document["loyaltyPoints"] as int;
  object.lifetimeValue = document["lifetimeValue"] as double;
  object.signedUpAt = DateTime.fromMicrosecondsSinceEpoch(
    document["signedUpAt"] as int,
    isUtc: true,
  );
  object.preferredResponseTime = document["preferredResponseTime"] == null
      ? null
      : Duration(microseconds: document["preferredResponseTime"] as int);
  object.status = CustomerStatus.values.byName(document["status"] as String);
  object.tier = CustomerTier.values.firstWhere(
    (enumValue) => enumValue.code == document["tier"],
  );
  object.tags = (document["tags"] as List<Object?>)
      .map((value) => value as String)
      .toList(growable: false);
  object.defaultShippingAddress = document["defaultShippingAddress"] == null
      ? null
      : _$CustomerAddressFromCindelEmbedded(
          (document["defaultShippingAddress"] as Map).cast<String, Object?>(),
        );
  object.savedAddresses = (document["savedAddresses"] as List<Object?>)
      .map(
        (value) => _$CustomerAddressFromCindelEmbedded(
          (value as Map).cast<String, Object?>(),
        ),
      )
      .toList(growable: false);
  return object;
}

CindelBinaryDocumentBytes _$CustomerToCindelBinaryDocument(Customer object) {
  return cindelEncodeSchemaBinaryDocument(
    <Object?>[
      object.active,
      object.defaultShippingAddress == null
          ? null
          : _$CustomerAddressToCindelEmbedded(
              object.defaultShippingAddress as CustomerAddress,
            ),
      object.email,
      object.lifetimeValue,
      object.loyaltyPoints,
      object.name,
      object.preferredResponseTime?.inMicroseconds,
      object.savedAddresses
          .map((value) => _$CustomerAddressToCindelEmbedded(value))
          .toList(growable: false),
      object.signedUpAt.microsecondsSinceEpoch,
      object.status.name,
      object.tags.map((value) => value).toList(growable: false),
      object.tier.code,
    ],
    const <CindelBinaryFieldType>[
      CindelBinaryFieldType.boolValue,
      CindelBinaryFieldType.objectValue,
      CindelBinaryFieldType.stringValue,
      CindelBinaryFieldType.doubleValue,
      CindelBinaryFieldType.intValue,
      CindelBinaryFieldType.stringValue,
      CindelBinaryFieldType.intValue,
      CindelBinaryFieldType.listValue,
      CindelBinaryFieldType.intValue,
      CindelBinaryFieldType.stringValue,
      CindelBinaryFieldType.listValue,
      CindelBinaryFieldType.stringValue,
    ],
  );
}

Customer _$CustomerFromCindelBinaryDocument(CindelBinaryDocumentBytes bytes) {
  final reader = CindelSchemaBinaryDocumentReader(bytes, staticSize: 54);
  final Object? field0 = reader.readBool(0, 0);
  final Object? field1 = reader.readObject(1, 1);
  final Object? field2 = reader.readString(2, 4);
  final Object? field3 = reader.readDouble(3, 7);
  final Object? field4 = reader.readInt(4, 15);
  final Object? field5 = reader.readString(5, 23);
  final Object? field6 = reader.readInt(6, 26);
  final Object? field7 = reader.readList(7, 34);
  final Object? field8 = reader.readInt(8, 37);
  final Object? field9 = reader.readString(9, 45);
  final Object? field10 = reader.readList(10, 48);
  final Object? field11 = reader.readString(11, 51);
  final object = Customer();
  object.dbId = autoIncrement;
  object.email = field2 as String;
  object.name = field5 as String;
  object.active = field0 as bool;
  object.loyaltyPoints = field4 as int;
  object.lifetimeValue = field3 as double;
  object.signedUpAt = DateTime.fromMicrosecondsSinceEpoch(
    field8 as int,
    isUtc: true,
  );
  object.preferredResponseTime = field6 == null
      ? null
      : Duration(microseconds: field6 as int);
  object.status = CustomerStatus.values.byName(field9 as String);
  object.tier = CustomerTier.values.firstWhere(
    (enumValue) => enumValue.code == field11,
  );
  object.tags = (field10 as List<Object?>)
      .map((value) => value as String)
      .toList(growable: false);
  object.defaultShippingAddress = field1 == null
      ? null
      : _$CustomerAddressFromCindelEmbedded(
          (field1 as Map).cast<String, Object?>(),
        );
  object.savedAddresses = (field7 as List<Object?>)
      .map(
        (value) => _$CustomerAddressFromCindelEmbedded(
          (value as Map).cast<String, Object?>(),
        ),
      )
      .toList(growable: false);
  return object;
}

void _$CustomerWriteCindelNativeDocument(
  CindelNativeDocumentWriter writer,
  Customer object,
) {
  writer.writeBool(0, object.active);
  {
    final value = object.defaultShippingAddress;
    if (value == null) {
      writer.writeNull(1);
    } else {
      cindelWriteNativeObject<CustomerAddress>(
        writer,
        1,
        _$CustomerAddressCindelNativeFieldNames,
        value,
        _$CustomerAddressWriteCindelNativeEmbedded,
        _$CustomerAddressToCindelEmbedded,
      );
    }
  }
  writer.writeString(2, object.email);
  writer.writeDouble(3, object.lifetimeValue);
  writer.writeInt(4, object.loyaltyPoints);
  writer.writeString(5, object.name);
  {
    final value = object.preferredResponseTime?.inMicroseconds;
    if (value == null) {
      writer.writeNull(6);
    } else {
      writer.writeInt(6, value);
    }
  }
  {
    final list = object.savedAddresses;
    cindelWriteNativeObjectList<CustomerAddress>(
      writer,
      7,
      _$CustomerAddressCindelNativeFieldNames,
      list,
      _$CustomerAddressWriteCindelNativeEmbedded,
      _$CustomerAddressToCindelEmbedded,
    );
  }
  writer.writeInt(8, object.signedUpAt.microsecondsSinceEpoch);
  writer.writeString(9, object.status.name);
  cindelWriteNativeStringList(writer, 10, object.tags);
  writer.writeString(11, object.tier.code);
}

Customer _$CustomerReadCindelNativeDocument(
  CindelNativeDocumentReader reader,
  int documentIndex,
) {
  final object = Customer();
  object.dbId = reader.readId(documentIndex);
  object.email = reader.readString(documentIndex, 2) as String;
  object.name = reader.readString(documentIndex, 5) as String;
  object.active = reader.readBool(documentIndex, 0) as bool;
  object.loyaltyPoints = reader.readInt(documentIndex, 4) as int;
  object.lifetimeValue = reader.readDouble(documentIndex, 3) as double;
  object.signedUpAt = DateTime.fromMicrosecondsSinceEpoch(
    reader.readInt(documentIndex, 8) as int,
    isUtc: true,
  );
  object.preferredResponseTime = reader.readInt(documentIndex, 6) == null
      ? null
      : Duration(microseconds: reader.readInt(documentIndex, 6) as int);
  object.status = CustomerStatus.values.byName(
    reader.readString(documentIndex, 9) as String,
  );
  object.tier = CustomerTier.values.firstWhere(
    (enumValue) => enumValue.code == reader.readString(documentIndex, 11),
  );
  object.tags = reader.readStringList(documentIndex, 10) ?? const <String>[];
  object.defaultShippingAddress = cindelReadNativeObject<CustomerAddress>(
    reader,
    documentIndex,
    1,
    _$CustomerAddressCindelNativeFieldNames,
    _$CustomerAddressReadCindelNativeEmbedded,
    _$CustomerAddressFromCindelEmbedded,
  );
  object.savedAddresses =
      (cindelReadNativeObjectList<CustomerAddress>(
                reader,
                documentIndex,
                7,
                _$CustomerAddressCindelNativeFieldNames,
                _$CustomerAddressReadCindelNativeEmbedded,
                _$CustomerAddressFromCindelEmbedded,
              ) ??
              const <CustomerAddress?>[])
          .cast<CustomerAddress>();
  return object;
}

int _$CustomerGetCindelId(Customer object) {
  return object.dbId;
}

void _$CustomerSetCindelId(Customer object, int id) {
  object.dbId = id;
}

const _$CustomerAddressCindelNativeFieldNames = <String>[
  "line1",
  "city",
  "country",
  "postalCode",
  "location",
];

Map<String, Object?> _$CustomerAddressToCindelEmbedded(CustomerAddress object) {
  return <String, Object?>{
    "line1": object.line1,
    "city": object.city,
    "country": object.country,
    "postalCode": object.postalCode,
    "location": object.location == null
        ? null
        : _$CustomerGeoPointToCindelEmbedded(
            object.location as CustomerGeoPoint,
          ),
  };
}

CustomerAddress _$CustomerAddressFromCindelEmbedded(
  Map<String, Object?> document,
) {
  final object = CustomerAddress();
  object.line1 = document["line1"] == null
      ? null
      : document["line1"] as String?;
  object.city = document["city"] == null ? null : document["city"] as String?;
  object.country = document["country"] == null
      ? null
      : document["country"] as String?;
  object.postalCode = document["postalCode"] == null
      ? null
      : document["postalCode"] as String?;
  object.location = document["location"] == null
      ? null
      : _$CustomerGeoPointFromCindelEmbedded(
          (document["location"] as Map).cast<String, Object?>(),
        );
  return object;
}

void _$CustomerAddressWriteCindelNativeEmbedded(
  CindelNativeDocumentWriter writer,
  CustomerAddress object,
) {
  {
    final value = object.line1;
    if (value == null) {
      writer.writeNull(0);
    } else {
      writer.writeString(0, value);
    }
  }
  {
    final value = object.city;
    if (value == null) {
      writer.writeNull(1);
    } else {
      writer.writeString(1, value);
    }
  }
  {
    final value = object.country;
    if (value == null) {
      writer.writeNull(2);
    } else {
      writer.writeString(2, value);
    }
  }
  {
    final value = object.postalCode;
    if (value == null) {
      writer.writeNull(3);
    } else {
      writer.writeString(3, value);
    }
  }
  {
    final value = object.location;
    if (value == null) {
      writer.writeNull(4);
    } else {
      cindelWriteNativeObject<CustomerGeoPoint>(
        writer,
        4,
        _$CustomerGeoPointCindelNativeFieldNames,
        value,
        _$CustomerGeoPointWriteCindelNativeEmbedded,
        _$CustomerGeoPointToCindelEmbedded,
      );
    }
  }
}

CustomerAddress _$CustomerAddressReadCindelNativeEmbedded(
  CindelNativeDocumentReader reader,
  int documentIndex,
) {
  final object = CustomerAddress();
  object.line1 = reader.readString(documentIndex, 0);
  object.city = reader.readString(documentIndex, 1);
  object.country = reader.readString(documentIndex, 2);
  object.postalCode = reader.readString(documentIndex, 3);
  object.location = cindelReadNativeObject<CustomerGeoPoint>(
    reader,
    documentIndex,
    4,
    _$CustomerGeoPointCindelNativeFieldNames,
    _$CustomerGeoPointReadCindelNativeEmbedded,
    _$CustomerGeoPointFromCindelEmbedded,
  );
  return object;
}

const _$CustomerGeoPointCindelNativeFieldNames = <String>[
  "latitude",
  "longitude",
];

Map<String, Object?> _$CustomerGeoPointToCindelEmbedded(
  CustomerGeoPoint object,
) {
  return <String, Object?>{
    "latitude": object.latitude,
    "longitude": object.longitude,
  };
}

CustomerGeoPoint _$CustomerGeoPointFromCindelEmbedded(
  Map<String, Object?> document,
) {
  final object = CustomerGeoPoint();
  object.latitude = document["latitude"] as double;
  object.longitude = document["longitude"] as double;
  return object;
}

void _$CustomerGeoPointWriteCindelNativeEmbedded(
  CindelNativeDocumentWriter writer,
  CustomerGeoPoint object,
) {
  writer.writeDouble(0, object.latitude);
  writer.writeDouble(1, object.longitude);
}

CustomerGeoPoint _$CustomerGeoPointReadCindelNativeEmbedded(
  CindelNativeDocumentReader reader,
  int documentIndex,
) {
  final object = CustomerGeoPoint();
  object.latitude = reader.readDouble(documentIndex, 0) as double;
  object.longitude = reader.readDouble(documentIndex, 1) as double;
  return object;
}
