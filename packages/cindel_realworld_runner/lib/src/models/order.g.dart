// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'order.dart';

// **************************************************************************
// CindelGenerator
// **************************************************************************

// ignore_for_file: non_constant_identifier_names

final CustomerOrderSchema = CindelCollectionSchema<CustomerOrder>(
  name: "orders",
  dartName: "CustomerOrder",
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
      name: "orderNumber",
      dartType: "String",
      binaryType: "string",
      isId: false,
      isIndexed: true,
      isIndexUnique: true,
      isIndexReplace: true,
      indexCaseSensitive: true,
      indexType: CindelIndexType.value,
    ),
    CindelFieldSchema(
      name: "status",
      dartType: "OrderStatus",
      binaryType: "string",
      isId: false,
      isIndexed: true,
      isIndexUnique: false,
      isIndexReplace: false,
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
      isIndexReplace: false,
      indexCaseSensitive: true,
      indexType: CindelIndexType.value,
    ),
    CindelFieldSchema(
      name: "total",
      dartType: "double",
      binaryType: "double",
      isId: false,
      isIndexed: true,
      isIndexUnique: false,
      isIndexReplace: false,
      indexCaseSensitive: true,
      indexType: CindelIndexType.value,
    ),
    CindelFieldSchema(
      name: "priority",
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
      name: "shippingAddress",
      dartType: "OrderAddress?",
      binaryType: "object",
      isId: false,
      isIndexed: false,
      isIndexUnique: false,
      isIndexReplace: false,
      indexCaseSensitive: true,
      indexType: CindelIndexType.value,
    ),
    CindelFieldSchema(
      name: "items",
      dartType: "List<OrderItem>",
      binaryType: "list",
      isId: false,
      isIndexed: false,
      isIndexUnique: false,
      isIndexReplace: false,
      indexCaseSensitive: true,
      indexType: CindelIndexType.value,
    ),
    CindelFieldSchema(
      name: "note",
      dartType: "String?",
      binaryType: "string",
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
      name: "customer",
      dartName: "customer",
      targetCollection: "customers",
      isToMany: false,
      isBacklink: false,
      backlinkTo: null,
    ),
    CindelLinkSchema(
      name: "payment",
      dartName: "payment",
      targetCollection: "payments",
      isToMany: false,
      isBacklink: false,
      backlinkTo: null,
    ),
  ],
  compositeIndexes: <CindelCompositeIndexSchema>[
    CindelCompositeIndexSchema(
      name: "status_createdAt",
      fields: <String>["status", "createdAt"],
      isUnique: false,
      isReplace: false,
      caseSensitive: true,
    ),
  ],
  toDocument: _$CustomerOrderToCindelDocument,
  fromDocument: _$CustomerOrderFromCindelDocument,
  toBinaryDocument: _$CustomerOrderToCindelBinaryDocument,
  fromBinaryDocument: _$CustomerOrderFromCindelBinaryDocument,
  writeNativeDocument: _$CustomerOrderWriteCindelNativeDocument,
  readNativeDocument: _$CustomerOrderReadCindelNativeDocument,
  getId: _$CustomerOrderGetCindelId,
  setId: _$CustomerOrderSetCindelId,
  bindLinks: _$CustomerOrderBindCindelLinks,
);

void _$CustomerOrderBindCindelLinks(
  Object database,
  CindelCollectionSchema<CustomerOrder> schema,
  CustomerOrder object,
) {
  final cindelDatabase = database as CindelDatabase;
  final ownerSchema = schema as dynamic;
  object.customer.bind(
    cindelDatabase,
    ownerSchema,
    object,
    schema.links.firstWhere((link) => link.dartName == "customer"),
  );
  object.payment.bind(
    cindelDatabase,
    ownerSchema,
    object,
    schema.links.firstWhere((link) => link.dartName == "payment"),
  );
}

extension CustomerOrderCindelCollectionAccess on CindelDatabase {
  CindelTypedCollection<CustomerOrder> get orders =>
      typedCollection(CustomerOrderSchema);
}

extension CustomerOrderCindelQueryAccess
    on CindelTypedCollection<CustomerOrder> {
  CustomerOrderQueryWhere where() => CustomerOrderQueryWhere(this);

  CustomerOrderQueryFilter filter() => CustomerOrderQueryFilter(
    CindelQuery.all(database: database, schema: CustomerOrderSchema),
  );

  Future<void> putByOrderNumber(CustomerOrder object) {
    return putByUniqueIndex(
      object,
      indexName: "orderNumber",
      values: <Object?>[object.orderNumber],
      isComposite: false,
    );
  }

  Future<void> putAllByOrderNumber(Iterable<CustomerOrder> objects) {
    return putAllByUniqueIndex(
      objects,
      indexName: "orderNumber",
      values: (object) => <Object?>[object.orderNumber],
      isComposite: false,
    );
  }
}

extension CustomerOrderCindelQueryFilterAccess on CindelQuery<CustomerOrder> {
  CustomerOrderQueryFilter filter() => CustomerOrderQueryFilter(this);
}

extension CustomerOrderCindelQueryModifierAccess on CindelQuery<CustomerOrder> {
  CindelQuery<CustomerOrder> sortByDbId({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return sortBy("dbId", order: order);
  }

  CindelQuery<CustomerOrder> sortByDbIdDesc() {
    return sortBy("dbId", order: CindelSortOrder.descending);
  }

  CindelQuery<CustomerOrder> thenByDbId({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return thenBy("dbId", order: order);
  }

  CindelQuery<CustomerOrder> thenByDbIdDesc() {
    return thenBy("dbId", order: CindelSortOrder.descending);
  }

  CindelQuery<CustomerOrder> distinctByDbId() {
    return distinctBy("dbId");
  }

  CindelPropertyQuery<CustomerOrder, int> dbIdProperty() {
    return property<int>("dbId");
  }

  CindelQuery<CustomerOrder> sortByOrderNumber({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return sortBy("orderNumber", order: order);
  }

  CindelQuery<CustomerOrder> sortByOrderNumberDesc() {
    return sortBy("orderNumber", order: CindelSortOrder.descending);
  }

  CindelQuery<CustomerOrder> thenByOrderNumber({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return thenBy("orderNumber", order: order);
  }

  CindelQuery<CustomerOrder> thenByOrderNumberDesc() {
    return thenBy("orderNumber", order: CindelSortOrder.descending);
  }

  CindelQuery<CustomerOrder> distinctByOrderNumber() {
    return distinctBy("orderNumber");
  }

  CindelPropertyQuery<CustomerOrder, String> orderNumberProperty() {
    return property<String>("orderNumber");
  }

  CindelQuery<CustomerOrder> sortByStatus({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return sortBy("status", order: order);
  }

  CindelQuery<CustomerOrder> sortByStatusDesc() {
    return sortBy("status", order: CindelSortOrder.descending);
  }

  CindelQuery<CustomerOrder> thenByStatus({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return thenBy("status", order: order);
  }

  CindelQuery<CustomerOrder> thenByStatusDesc() {
    return thenBy("status", order: CindelSortOrder.descending);
  }

  CindelQuery<CustomerOrder> distinctByStatus() {
    return distinctBy("status");
  }

  CindelPropertyQuery<CustomerOrder, OrderStatus> statusProperty() {
    return property<OrderStatus>(
      "status",
      decode: (value) => OrderStatus.values.byName(value as String),
    );
  }

  CindelQuery<CustomerOrder> sortByCreatedAt({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return sortBy("createdAt", order: order);
  }

  CindelQuery<CustomerOrder> sortByCreatedAtDesc() {
    return sortBy("createdAt", order: CindelSortOrder.descending);
  }

  CindelQuery<CustomerOrder> thenByCreatedAt({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return thenBy("createdAt", order: order);
  }

  CindelQuery<CustomerOrder> thenByCreatedAtDesc() {
    return thenBy("createdAt", order: CindelSortOrder.descending);
  }

  CindelQuery<CustomerOrder> distinctByCreatedAt() {
    return distinctBy("createdAt");
  }

  CindelPropertyQuery<CustomerOrder, DateTime> createdAtProperty() {
    return property<DateTime>(
      "createdAt",
      decode: (value) =>
          DateTime.fromMicrosecondsSinceEpoch(value as int, isUtc: true),
    );
  }

  CindelQuery<CustomerOrder> sortByTotal({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return sortBy("total", order: order);
  }

  CindelQuery<CustomerOrder> sortByTotalDesc() {
    return sortBy("total", order: CindelSortOrder.descending);
  }

  CindelQuery<CustomerOrder> thenByTotal({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return thenBy("total", order: order);
  }

  CindelQuery<CustomerOrder> thenByTotalDesc() {
    return thenBy("total", order: CindelSortOrder.descending);
  }

  CindelQuery<CustomerOrder> distinctByTotal() {
    return distinctBy("total");
  }

  CindelPropertyQuery<CustomerOrder, double> totalProperty() {
    return property<double>("total");
  }

  CindelQuery<CustomerOrder> sortByPriority({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return sortBy("priority", order: order);
  }

  CindelQuery<CustomerOrder> sortByPriorityDesc() {
    return sortBy("priority", order: CindelSortOrder.descending);
  }

  CindelQuery<CustomerOrder> thenByPriority({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return thenBy("priority", order: order);
  }

  CindelQuery<CustomerOrder> thenByPriorityDesc() {
    return thenBy("priority", order: CindelSortOrder.descending);
  }

  CindelQuery<CustomerOrder> distinctByPriority() {
    return distinctBy("priority");
  }

  CindelPropertyQuery<CustomerOrder, bool> priorityProperty() {
    return property<bool>("priority");
  }

  CindelQuery<CustomerOrder> sortByShippingAddress({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return sortBy("shippingAddress", order: order);
  }

  CindelQuery<CustomerOrder> sortByShippingAddressDesc() {
    return sortBy("shippingAddress", order: CindelSortOrder.descending);
  }

  CindelQuery<CustomerOrder> thenByShippingAddress({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return thenBy("shippingAddress", order: order);
  }

  CindelQuery<CustomerOrder> thenByShippingAddressDesc() {
    return thenBy("shippingAddress", order: CindelSortOrder.descending);
  }

  CindelQuery<CustomerOrder> distinctByShippingAddress() {
    return distinctBy("shippingAddress");
  }

  CindelPropertyQuery<CustomerOrder, OrderAddress?> shippingAddressProperty() {
    return property<OrderAddress?>(
      "shippingAddress",
      decode: (value) => value == null
          ? null
          : _$OrderAddressFromCindelEmbedded(
              (value as Map).cast<String, Object?>(),
            ),
    );
  }

  CindelQuery<CustomerOrder> sortByItems({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return sortBy("items", order: order);
  }

  CindelQuery<CustomerOrder> sortByItemsDesc() {
    return sortBy("items", order: CindelSortOrder.descending);
  }

  CindelQuery<CustomerOrder> thenByItems({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return thenBy("items", order: order);
  }

  CindelQuery<CustomerOrder> thenByItemsDesc() {
    return thenBy("items", order: CindelSortOrder.descending);
  }

  CindelQuery<CustomerOrder> distinctByItems() {
    return distinctBy("items");
  }

  CindelPropertyQuery<CustomerOrder, List<OrderItem>> itemsProperty() {
    return property<List<OrderItem>>(
      "items",
      decode: (value) => (value as List<Object?>)
          .map(
            (value) => _$OrderItemFromCindelEmbedded(
              (value as Map).cast<String, Object?>(),
            ),
          )
          .toList(growable: false),
    );
  }

  CindelQuery<CustomerOrder> sortByNote({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return sortBy("note", order: order);
  }

  CindelQuery<CustomerOrder> sortByNoteDesc() {
    return sortBy("note", order: CindelSortOrder.descending);
  }

  CindelQuery<CustomerOrder> thenByNote({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return thenBy("note", order: order);
  }

  CindelQuery<CustomerOrder> thenByNoteDesc() {
    return thenBy("note", order: CindelSortOrder.descending);
  }

  CindelQuery<CustomerOrder> distinctByNote() {
    return distinctBy("note");
  }

  CindelPropertyQuery<CustomerOrder, String?> noteProperty() {
    return property<String?>("note");
  }
}

final class CustomerOrderQueryFilter {
  const CustomerOrderQueryFilter(this._query);

  final CindelQuery<CustomerOrder> _query;

  CindelQuery<CustomerOrder> dbIdEqualTo(int value) {
    return _query.whereMatches(CindelFilter.field("dbId").equalTo(value));
  }

  CindelQuery<CustomerOrder> dbIdGreaterThan(int value) {
    return _query.whereMatches(CindelFilter.field("dbId").greaterThan(value));
  }

  CindelQuery<CustomerOrder> dbIdGreaterThanOrEqualTo(int value) {
    return _query.whereMatches(
      CindelFilter.field("dbId").greaterThanOrEqualTo(value),
    );
  }

  CindelQuery<CustomerOrder> dbIdLessThan(int value) {
    return _query.whereMatches(CindelFilter.field("dbId").lessThan(value));
  }

  CindelQuery<CustomerOrder> dbIdLessThanOrEqualTo(int value) {
    return _query.whereMatches(
      CindelFilter.field("dbId").lessThanOrEqualTo(value),
    );
  }

  CindelQuery<CustomerOrder> dbIdBetween(int? lower, int? upper) {
    return _query.whereMatches(
      CindelFilter.field("dbId").between(lower, upper),
    );
  }

  CindelQuery<CustomerOrder> orderNumberEqualTo(String value) {
    return _query.whereMatches(
      CindelFilter.field("orderNumber").equalTo(value),
    );
  }

  CindelQuery<CustomerOrder> orderNumberContains(String value) {
    return _query.whereMatches(
      CindelFilter.field("orderNumber").contains(value),
    );
  }

  CindelQuery<CustomerOrder> orderNumberStartsWith(String value) {
    return _query.whereMatches(
      CindelFilter.field("orderNumber").startsWith(value),
    );
  }

  CindelQuery<CustomerOrder> orderNumberEndsWith(String value) {
    return _query.whereMatches(
      CindelFilter.field("orderNumber").endsWith(value),
    );
  }

  CindelQuery<CustomerOrder> statusEqualTo(OrderStatus value) {
    return _query.whereMatches(
      CindelFilter.field("status").equalTo(value.name),
    );
  }

  CindelQuery<CustomerOrder> createdAtEqualTo(DateTime value) {
    return _query.whereMatches(
      CindelFilter.field("createdAt").equalTo(value.microsecondsSinceEpoch),
    );
  }

  CindelQuery<CustomerOrder> createdAtGreaterThan(DateTime value) {
    return _query.whereMatches(
      CindelFilter.field("createdAt").greaterThan(value.microsecondsSinceEpoch),
    );
  }

  CindelQuery<CustomerOrder> createdAtGreaterThanOrEqualTo(DateTime value) {
    return _query.whereMatches(
      CindelFilter.field(
        "createdAt",
      ).greaterThanOrEqualTo(value.microsecondsSinceEpoch),
    );
  }

  CindelQuery<CustomerOrder> createdAtLessThan(DateTime value) {
    return _query.whereMatches(
      CindelFilter.field("createdAt").lessThan(value.microsecondsSinceEpoch),
    );
  }

  CindelQuery<CustomerOrder> createdAtLessThanOrEqualTo(DateTime value) {
    return _query.whereMatches(
      CindelFilter.field(
        "createdAt",
      ).lessThanOrEqualTo(value.microsecondsSinceEpoch),
    );
  }

  CindelQuery<CustomerOrder> createdAtBetween(
    DateTime? lower,
    DateTime? upper,
  ) {
    return _query.whereMatches(
      CindelFilter.field(
        "createdAt",
      ).between(lower?.microsecondsSinceEpoch, upper?.microsecondsSinceEpoch),
    );
  }

  CindelQuery<CustomerOrder> totalEqualTo(double value) {
    return _query.whereMatches(CindelFilter.field("total").equalTo(value));
  }

  CindelQuery<CustomerOrder> totalGreaterThan(double value) {
    return _query.whereMatches(CindelFilter.field("total").greaterThan(value));
  }

  CindelQuery<CustomerOrder> totalGreaterThanOrEqualTo(double value) {
    return _query.whereMatches(
      CindelFilter.field("total").greaterThanOrEqualTo(value),
    );
  }

  CindelQuery<CustomerOrder> totalLessThan(double value) {
    return _query.whereMatches(CindelFilter.field("total").lessThan(value));
  }

  CindelQuery<CustomerOrder> totalLessThanOrEqualTo(double value) {
    return _query.whereMatches(
      CindelFilter.field("total").lessThanOrEqualTo(value),
    );
  }

  CindelQuery<CustomerOrder> totalBetween(double? lower, double? upper) {
    return _query.whereMatches(
      CindelFilter.field("total").between(lower, upper),
    );
  }

  CindelQuery<CustomerOrder> priorityEqualTo(bool value) {
    return _query.whereMatches(CindelFilter.field("priority").equalTo(value));
  }

  CindelQuery<CustomerOrder> shippingAddressEqualTo(OrderAddress? value) {
    return _query.whereMatches(
      CindelFilter.field(
        "shippingAddress",
      ).equalTo(value == null ? null : _$OrderAddressToCindelEmbedded(value)),
    );
  }

  CindelQuery<CustomerOrder> shippingAddress(
    CindelFilterPredicate Function(
      CustomerOrderOrderAddressCindelEmbeddedFilter q,
    )
    filter,
  ) {
    return _query.whereMatches(
      filter(
        const CustomerOrderOrderAddressCindelEmbeddedFilter._(<String>[
          "shippingAddress",
        ]),
      ),
    );
  }

  CindelQuery<CustomerOrder> itemsEqualTo(List<OrderItem> value) {
    return _query.whereMatches(
      CindelFilter.field("items").equalTo(
        value
            .map((value) => _$OrderItemToCindelEmbedded(value))
            .toList(growable: false),
      ),
    );
  }

  CindelQuery<CustomerOrder> itemsElementEqualTo(OrderItem value) {
    return _query.whereMatches(
      CindelFilter.field("items").contains(_$OrderItemToCindelEmbedded(value)),
    );
  }

  CindelQuery<CustomerOrder> itemsIsEmpty() {
    return _query.whereMatches(CindelFilter.field("items").isEmpty());
  }

  CindelQuery<CustomerOrder> itemsIsNotEmpty() {
    return _query.whereMatches(CindelFilter.field("items").isNotEmpty());
  }

  CindelQuery<CustomerOrder> itemsLengthEqualTo(int length) {
    return _query.whereMatches(
      CindelFilter.field("items").lengthEqualTo(length),
    );
  }

  CindelQuery<CustomerOrder> itemsLengthLessThan(
    int length, {
    bool include = false,
  }) {
    return _query.whereMatches(
      CindelFilter.field("items").lengthLessThan(length, include: include),
    );
  }

  CindelQuery<CustomerOrder> itemsLengthGreaterThan(
    int length, {
    bool include = false,
  }) {
    return _query.whereMatches(
      CindelFilter.field("items").lengthGreaterThan(length, include: include),
    );
  }

  CindelQuery<CustomerOrder> itemsLengthBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return _query.whereMatches(
      CindelFilter.field("items").lengthBetween(
        lower,
        upper,
        includeLower: includeLower,
        includeUpper: includeUpper,
      ),
    );
  }

  CindelQuery<CustomerOrder> itemsElement(
    CindelFilterPredicate Function(CustomerOrderOrderItemCindelEmbeddedFilter q)
    filter,
  ) {
    return _query.whereMatches(
      filter(
        const CustomerOrderOrderItemCindelEmbeddedFilter._(<String>["items"]),
      ),
    );
  }

  CindelQuery<CustomerOrder> noteEqualTo(String? value) {
    return _query.whereMatches(CindelFilter.field("note").equalTo(value));
  }

  CindelQuery<CustomerOrder> noteContains(String value) {
    return _query.whereMatches(CindelFilter.field("note").contains(value));
  }

  CindelQuery<CustomerOrder> noteStartsWith(String value) {
    return _query.whereMatches(CindelFilter.field("note").startsWith(value));
  }

  CindelQuery<CustomerOrder> noteEndsWith(String value) {
    return _query.whereMatches(CindelFilter.field("note").endsWith(value));
  }

  CindelQuery<CustomerOrder> optional(
    bool enabled,
    CindelQuery<CustomerOrder> Function(CustomerOrderQueryFilter q) option,
  ) {
    return _query.optional(
      enabled,
      (query) => option(CustomerOrderQueryFilter(query)),
    );
  }

  CindelQuery<CustomerOrder> anyOf<E>(
    Iterable<E> items,
    CindelQuery<CustomerOrder> Function(CustomerOrderQueryFilter q, E item)
    option,
  ) {
    return _query.anyOf(
      items,
      (query, item) => option(CustomerOrderQueryFilter(query), item),
    );
  }

  CindelQuery<CustomerOrder> allOf<E>(
    Iterable<E> items,
    CindelQuery<CustomerOrder> Function(CustomerOrderQueryFilter q, E item)
    option,
  ) {
    return _query.allOf(
      items,
      (query, item) => option(CustomerOrderQueryFilter(query), item),
    );
  }
}

final class CustomerOrderQueryWhere {
  const CustomerOrderQueryWhere(this._collection);

  final CindelTypedCollection<CustomerOrder> _collection;

  CindelQuery<CustomerOrder> orderNumberEqualTo(String value) {
    return CindelQuery.equal(
      database: _collection.database,
      schema: CustomerOrderSchema,
      field: "orderNumber",
      value: value,
    );
  }

  CindelQuery<CustomerOrder> orderNumberStartsWith(String prefix) {
    return CindelQuery.stringStartsWith(
      database: _collection.database,
      schema: CustomerOrderSchema,
      field: "orderNumber",
      prefix: prefix,
    );
  }

  CindelQuery<CustomerOrder> orderNumberBetween(String? lower, String? upper) {
    return CindelQuery.range(
      database: _collection.database,
      schema: CustomerOrderSchema,
      field: "orderNumber",
      lower: lower,
      upper: upper,
    );
  }

  CindelQuery<CustomerOrder> statusEqualTo(OrderStatus value) {
    return CindelQuery.equal(
      database: _collection.database,
      schema: CustomerOrderSchema,
      field: "status",
      value: value.name,
    );
  }

  CindelQuery<CustomerOrder> createdAtEqualTo(DateTime value) {
    return CindelQuery.equal(
      database: _collection.database,
      schema: CustomerOrderSchema,
      field: "createdAt",
      value: value.microsecondsSinceEpoch,
    );
  }

  CindelQuery<CustomerOrder> createdAtBetween(
    DateTime? lower,
    DateTime? upper,
  ) {
    return CindelQuery.range(
      database: _collection.database,
      schema: CustomerOrderSchema,
      field: "createdAt",
      lower: lower?.microsecondsSinceEpoch,
      upper: upper?.microsecondsSinceEpoch,
    );
  }

  CindelQuery<CustomerOrder> totalEqualTo(double value) {
    return CindelQuery.equal(
      database: _collection.database,
      schema: CustomerOrderSchema,
      field: "total",
      value: value,
    );
  }

  CindelQuery<CustomerOrder> totalBetween(double? lower, double? upper) {
    return CindelQuery.range(
      database: _collection.database,
      schema: CustomerOrderSchema,
      field: "total",
      lower: lower,
      upper: upper,
    );
  }

  CindelQuery<CustomerOrder> statusCreatedAtEqualTo(
    OrderStatus status,
    DateTime createdAt,
  ) {
    return CindelQuery.compositeEqual(
      database: _collection.database,
      schema: CustomerOrderSchema,
      index: "status_createdAt",
      values: <Object>[status.name, createdAt.microsecondsSinceEpoch],
    );
  }
}

final class CustomerOrderOrderAddressCindelEmbeddedFilter {
  const CustomerOrderOrderAddressCindelEmbeddedFilter._(this._path);

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

  CindelFilterPredicate locationEqualTo(OrderGeoPoint? value) {
    return CindelFilter.path(<String>[
      ..._path,
      "location",
    ]).equalTo(value == null ? null : _$OrderGeoPointToCindelEmbedded(value));
  }

  CindelFilterPredicate location(
    CindelFilterPredicate Function(
      CustomerOrderOrderGeoPointCindelEmbeddedFilter q,
    )
    filter,
  ) {
    return filter(
      CustomerOrderOrderGeoPointCindelEmbeddedFilter._(<String>[
        ..._path,
        "location",
      ]),
    );
  }
}

final class CustomerOrderOrderGeoPointCindelEmbeddedFilter {
  const CustomerOrderOrderGeoPointCindelEmbeddedFilter._(this._path);

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

final class CustomerOrderOrderItemCindelEmbeddedFilter {
  const CustomerOrderOrderItemCindelEmbeddedFilter._(this._path);

  final List<String> _path;

  CindelFilterPredicate skuEqualTo(String value) {
    return CindelFilter.path(<String>[..._path, "sku"]).equalTo(value);
  }

  CindelFilterPredicate skuContains(String value) {
    return CindelFilter.path(<String>[..._path, "sku"]).contains(value);
  }

  CindelFilterPredicate skuStartsWith(String value) {
    return CindelFilter.path(<String>[..._path, "sku"]).startsWith(value);
  }

  CindelFilterPredicate skuEndsWith(String value) {
    return CindelFilter.path(<String>[..._path, "sku"]).endsWith(value);
  }

  CindelFilterPredicate productNameEqualTo(String value) {
    return CindelFilter.path(<String>[..._path, "productName"]).equalTo(value);
  }

  CindelFilterPredicate productNameContains(String value) {
    return CindelFilter.path(<String>[..._path, "productName"]).contains(value);
  }

  CindelFilterPredicate productNameStartsWith(String value) {
    return CindelFilter.path(<String>[
      ..._path,
      "productName",
    ]).startsWith(value);
  }

  CindelFilterPredicate productNameEndsWith(String value) {
    return CindelFilter.path(<String>[..._path, "productName"]).endsWith(value);
  }

  CindelFilterPredicate quantityEqualTo(int value) {
    return CindelFilter.path(<String>[..._path, "quantity"]).equalTo(value);
  }

  CindelFilterPredicate quantityGreaterThan(int value) {
    return CindelFilter.path(<String>[..._path, "quantity"]).greaterThan(value);
  }

  CindelFilterPredicate quantityGreaterThanOrEqualTo(int value) {
    return CindelFilter.path(<String>[
      ..._path,
      "quantity",
    ]).greaterThanOrEqualTo(value);
  }

  CindelFilterPredicate quantityLessThan(int value) {
    return CindelFilter.path(<String>[..._path, "quantity"]).lessThan(value);
  }

  CindelFilterPredicate quantityLessThanOrEqualTo(int value) {
    return CindelFilter.path(<String>[
      ..._path,
      "quantity",
    ]).lessThanOrEqualTo(value);
  }

  CindelFilterPredicate quantityBetween(int? lower, int? upper) {
    return CindelFilter.path(<String>[
      ..._path,
      "quantity",
    ]).between(lower, upper);
  }

  CindelFilterPredicate unitPriceEqualTo(double value) {
    return CindelFilter.path(<String>[..._path, "unitPrice"]).equalTo(value);
  }

  CindelFilterPredicate unitPriceGreaterThan(double value) {
    return CindelFilter.path(<String>[
      ..._path,
      "unitPrice",
    ]).greaterThan(value);
  }

  CindelFilterPredicate unitPriceGreaterThanOrEqualTo(double value) {
    return CindelFilter.path(<String>[
      ..._path,
      "unitPrice",
    ]).greaterThanOrEqualTo(value);
  }

  CindelFilterPredicate unitPriceLessThan(double value) {
    return CindelFilter.path(<String>[..._path, "unitPrice"]).lessThan(value);
  }

  CindelFilterPredicate unitPriceLessThanOrEqualTo(double value) {
    return CindelFilter.path(<String>[
      ..._path,
      "unitPrice",
    ]).lessThanOrEqualTo(value);
  }

  CindelFilterPredicate unitPriceBetween(double? lower, double? upper) {
    return CindelFilter.path(<String>[
      ..._path,
      "unitPrice",
    ]).between(lower, upper);
  }

  CindelFilterPredicate appliedCouponsEqualTo(List<String> value) {
    return CindelFilter.path(<String>[
      ..._path,
      "appliedCoupons",
    ]).equalTo(value.map((value) => value).toList(growable: false));
  }

  CindelFilterPredicate appliedCouponsElementEqualTo(String value) {
    return CindelFilter.path(<String>[
      ..._path,
      "appliedCoupons",
    ]).contains(value);
  }

  CindelFilterPredicate appliedCouponsIsEmpty() {
    return CindelFilter.path(<String>[..._path, "appliedCoupons"]).isEmpty();
  }

  CindelFilterPredicate appliedCouponsIsNotEmpty() {
    return CindelFilter.path(<String>[..._path, "appliedCoupons"]).isNotEmpty();
  }

  CindelFilterPredicate appliedCouponsLengthEqualTo(int length) {
    return CindelFilter.path(<String>[
      ..._path,
      "appliedCoupons",
    ]).lengthEqualTo(length);
  }

  CindelFilterPredicate appliedCouponsLengthLessThan(
    int length, {
    bool include = false,
  }) {
    return CindelFilter.path(<String>[
      ..._path,
      "appliedCoupons",
    ]).lengthLessThan(length, include: include);
  }

  CindelFilterPredicate appliedCouponsLengthGreaterThan(
    int length, {
    bool include = false,
  }) {
    return CindelFilter.path(<String>[
      ..._path,
      "appliedCoupons",
    ]).lengthGreaterThan(length, include: include);
  }

  CindelFilterPredicate appliedCouponsLengthBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return CindelFilter.path(<String>[
      ..._path,
      "appliedCoupons",
    ]).lengthBetween(
      lower,
      upper,
      includeLower: includeLower,
      includeUpper: includeUpper,
    );
  }
}

Map<String, Object?> _$CustomerOrderToCindelDocument(CustomerOrder object) {
  return <String, Object?>{
    "orderNumber": object.orderNumber,
    "status": object.status.name,
    "createdAt": object.createdAt.microsecondsSinceEpoch,
    "total": object.total,
    "priority": object.priority,
    "shippingAddress": object.shippingAddress == null
        ? null
        : _$OrderAddressToCindelEmbedded(
            object.shippingAddress as OrderAddress,
          ),
    "items": object.items
        .map((value) => _$OrderItemToCindelEmbedded(value))
        .toList(growable: false),
    "note": object.note,
  };
}

CustomerOrder _$CustomerOrderFromCindelDocument(Map<String, Object?> document) {
  final object = CustomerOrder();
  object.dbId = document["dbId"] as int;
  object.orderNumber = document["orderNumber"] as String;
  object.status = OrderStatus.values.byName(document["status"] as String);
  object.createdAt = DateTime.fromMicrosecondsSinceEpoch(
    document["createdAt"] as int,
    isUtc: true,
  );
  object.total = document["total"] as double;
  object.priority = document["priority"] as bool;
  object.shippingAddress = document["shippingAddress"] == null
      ? null
      : _$OrderAddressFromCindelEmbedded(
          (document["shippingAddress"] as Map).cast<String, Object?>(),
        );
  object.items = (document["items"] as List<Object?>)
      .map(
        (value) => _$OrderItemFromCindelEmbedded(
          (value as Map).cast<String, Object?>(),
        ),
      )
      .toList(growable: false);
  object.note = document["note"] == null ? null : document["note"] as String?;
  return object;
}

CindelBinaryDocumentBytes _$CustomerOrderToCindelBinaryDocument(
  CustomerOrder object,
) {
  return cindelEncodeSchemaBinaryDocument(
    <Object?>[
      object.createdAt.microsecondsSinceEpoch,
      object.items
          .map((value) => _$OrderItemToCindelEmbedded(value))
          .toList(growable: false),
      object.note,
      object.orderNumber,
      object.priority,
      object.shippingAddress == null
          ? null
          : _$OrderAddressToCindelEmbedded(
              object.shippingAddress as OrderAddress,
            ),
      object.status.name,
      object.total,
    ],
    const <CindelBinaryFieldType>[
      CindelBinaryFieldType.intValue,
      CindelBinaryFieldType.listValue,
      CindelBinaryFieldType.stringValue,
      CindelBinaryFieldType.stringValue,
      CindelBinaryFieldType.boolValue,
      CindelBinaryFieldType.objectValue,
      CindelBinaryFieldType.stringValue,
      CindelBinaryFieldType.doubleValue,
    ],
  );
}

CustomerOrder _$CustomerOrderFromCindelBinaryDocument(
  CindelBinaryDocumentBytes bytes,
) {
  final reader = CindelSchemaBinaryDocumentReader(bytes, staticSize: 32);
  final Object? field0 = reader.readInt(0, 0);
  final Object? field1 = reader.readList(1, 8);
  final Object? field2 = reader.readString(2, 11);
  final Object? field3 = reader.readString(3, 14);
  final Object? field4 = reader.readBool(4, 17);
  final Object? field5 = reader.readObject(5, 18);
  final Object? field6 = reader.readString(6, 21);
  final Object? field7 = reader.readDouble(7, 24);
  final object = CustomerOrder();
  object.dbId = autoIncrement;
  object.orderNumber = field3 as String;
  object.status = OrderStatus.values.byName(field6 as String);
  object.createdAt = DateTime.fromMicrosecondsSinceEpoch(
    field0 as int,
    isUtc: true,
  );
  object.total = field7 as double;
  object.priority = field4 as bool;
  object.shippingAddress = field5 == null
      ? null
      : _$OrderAddressFromCindelEmbedded(
          (field5 as Map).cast<String, Object?>(),
        );
  object.items = (field1 as List<Object?>)
      .map(
        (value) => _$OrderItemFromCindelEmbedded(
          (value as Map).cast<String, Object?>(),
        ),
      )
      .toList(growable: false);
  object.note = field2 == null ? null : field2 as String?;
  return object;
}

void _$CustomerOrderWriteCindelNativeDocument(
  CindelNativeDocumentWriter writer,
  CustomerOrder object,
) {
  writer.writeInt(0, object.createdAt.microsecondsSinceEpoch);
  {
    final list = object.items;
    cindelWriteNativeObjectList<OrderItem>(
      writer,
      1,
      _$OrderItemCindelNativeFieldNames,
      list,
      _$OrderItemWriteCindelNativeEmbedded,
      _$OrderItemToCindelEmbedded,
    );
  }
  {
    final value = object.note;
    if (value == null) {
      writer.writeNull(2);
    } else {
      writer.writeString(2, value);
    }
  }
  writer.writeString(3, object.orderNumber);
  writer.writeBool(4, object.priority);
  {
    final value = object.shippingAddress;
    if (value == null) {
      writer.writeNull(5);
    } else {
      cindelWriteNativeObject<OrderAddress>(
        writer,
        5,
        _$OrderAddressCindelNativeFieldNames,
        value,
        _$OrderAddressWriteCindelNativeEmbedded,
        _$OrderAddressToCindelEmbedded,
      );
    }
  }
  writer.writeString(6, object.status.name);
  writer.writeDouble(7, object.total);
}

CustomerOrder _$CustomerOrderReadCindelNativeDocument(
  CindelNativeDocumentReader reader,
  int documentIndex,
) {
  final object = CustomerOrder();
  object.dbId = reader.readId(documentIndex);
  object.orderNumber = reader.readString(documentIndex, 3) as String;
  object.status = OrderStatus.values.byName(
    reader.readString(documentIndex, 6) as String,
  );
  object.createdAt = DateTime.fromMicrosecondsSinceEpoch(
    reader.readInt(documentIndex, 0) as int,
    isUtc: true,
  );
  object.total = reader.readDouble(documentIndex, 7) as double;
  object.priority = reader.readBool(documentIndex, 4) as bool;
  object.shippingAddress = cindelReadNativeObject<OrderAddress>(
    reader,
    documentIndex,
    5,
    _$OrderAddressCindelNativeFieldNames,
    _$OrderAddressReadCindelNativeEmbedded,
    _$OrderAddressFromCindelEmbedded,
  );
  object.items =
      (cindelReadNativeObjectList<OrderItem>(
                reader,
                documentIndex,
                1,
                _$OrderItemCindelNativeFieldNames,
                _$OrderItemReadCindelNativeEmbedded,
                _$OrderItemFromCindelEmbedded,
              ) ??
              const <OrderItem?>[])
          .cast<OrderItem>();
  object.note = reader.readString(documentIndex, 2);
  return object;
}

int _$CustomerOrderGetCindelId(CustomerOrder object) {
  return object.dbId;
}

void _$CustomerOrderSetCindelId(CustomerOrder object, int id) {
  object.dbId = id;
}

const _$OrderAddressCindelNativeFieldNames = <String>[
  "line1",
  "city",
  "country",
  "postalCode",
  "location",
];

Map<String, Object?> _$OrderAddressToCindelEmbedded(OrderAddress object) {
  return <String, Object?>{
    "line1": object.line1,
    "city": object.city,
    "country": object.country,
    "postalCode": object.postalCode,
    "location": object.location == null
        ? null
        : _$OrderGeoPointToCindelEmbedded(object.location as OrderGeoPoint),
  };
}

OrderAddress _$OrderAddressFromCindelEmbedded(Map<String, Object?> document) {
  final object = OrderAddress();
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
      : _$OrderGeoPointFromCindelEmbedded(
          (document["location"] as Map).cast<String, Object?>(),
        );
  return object;
}

void _$OrderAddressWriteCindelNativeEmbedded(
  CindelNativeDocumentWriter writer,
  OrderAddress object,
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
      cindelWriteNativeObject<OrderGeoPoint>(
        writer,
        4,
        _$OrderGeoPointCindelNativeFieldNames,
        value,
        _$OrderGeoPointWriteCindelNativeEmbedded,
        _$OrderGeoPointToCindelEmbedded,
      );
    }
  }
}

OrderAddress _$OrderAddressReadCindelNativeEmbedded(
  CindelNativeDocumentReader reader,
  int documentIndex,
) {
  final object = OrderAddress();
  object.line1 = reader.readString(documentIndex, 0);
  object.city = reader.readString(documentIndex, 1);
  object.country = reader.readString(documentIndex, 2);
  object.postalCode = reader.readString(documentIndex, 3);
  object.location = cindelReadNativeObject<OrderGeoPoint>(
    reader,
    documentIndex,
    4,
    _$OrderGeoPointCindelNativeFieldNames,
    _$OrderGeoPointReadCindelNativeEmbedded,
    _$OrderGeoPointFromCindelEmbedded,
  );
  return object;
}

const _$OrderGeoPointCindelNativeFieldNames = <String>["latitude", "longitude"];

Map<String, Object?> _$OrderGeoPointToCindelEmbedded(OrderGeoPoint object) {
  return <String, Object?>{
    "latitude": object.latitude,
    "longitude": object.longitude,
  };
}

OrderGeoPoint _$OrderGeoPointFromCindelEmbedded(Map<String, Object?> document) {
  final object = OrderGeoPoint();
  object.latitude = document["latitude"] as double;
  object.longitude = document["longitude"] as double;
  return object;
}

void _$OrderGeoPointWriteCindelNativeEmbedded(
  CindelNativeDocumentWriter writer,
  OrderGeoPoint object,
) {
  writer.writeDouble(0, object.latitude);
  writer.writeDouble(1, object.longitude);
}

OrderGeoPoint _$OrderGeoPointReadCindelNativeEmbedded(
  CindelNativeDocumentReader reader,
  int documentIndex,
) {
  final object = OrderGeoPoint();
  object.latitude = reader.readDouble(documentIndex, 0) as double;
  object.longitude = reader.readDouble(documentIndex, 1) as double;
  return object;
}

const _$OrderItemCindelNativeFieldNames = <String>[
  "sku",
  "productName",
  "quantity",
  "unitPrice",
  "appliedCoupons",
];

Map<String, Object?> _$OrderItemToCindelEmbedded(OrderItem object) {
  return <String, Object?>{
    "sku": object.sku,
    "productName": object.productName,
    "quantity": object.quantity,
    "unitPrice": object.unitPrice,
    "appliedCoupons": object.appliedCoupons
        .map((value) => value)
        .toList(growable: false),
  };
}

OrderItem _$OrderItemFromCindelEmbedded(Map<String, Object?> document) {
  final object = OrderItem();
  object.sku = document["sku"] as String;
  object.productName = document["productName"] as String;
  object.quantity = document["quantity"] as int;
  object.unitPrice = document["unitPrice"] as double;
  object.appliedCoupons = (document["appliedCoupons"] as List<Object?>)
      .map((value) => value as String)
      .toList(growable: false);
  return object;
}

void _$OrderItemWriteCindelNativeEmbedded(
  CindelNativeDocumentWriter writer,
  OrderItem object,
) {
  writer.writeString(0, object.sku);
  writer.writeString(1, object.productName);
  writer.writeInt(2, object.quantity);
  writer.writeDouble(3, object.unitPrice);
  cindelWriteNativeStringList(writer, 4, object.appliedCoupons);
}

OrderItem _$OrderItemReadCindelNativeEmbedded(
  CindelNativeDocumentReader reader,
  int documentIndex,
) {
  final object = OrderItem();
  object.sku = reader.readString(documentIndex, 0) as String;
  object.productName = reader.readString(documentIndex, 1) as String;
  object.quantity = reader.readInt(documentIndex, 2) as int;
  object.unitPrice = reader.readDouble(documentIndex, 3) as double;
  object.appliedCoupons =
      reader.readStringList(documentIndex, 4) ?? const <String>[];
  return object;
}
