// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'payment.dart';

// **************************************************************************
// CindelGenerator
// **************************************************************************

// ignore_for_file: non_constant_identifier_names

final PaymentSchema = CindelCollectionSchema<Payment>(
  name: "payments",
  dartName: "Payment",
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
      name: "transactionId",
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
      name: "method",
      dartType: "PaymentMethod",
      binaryType: "string",
      isId: false,
      isIndexed: false,
      isIndexUnique: false,
      isIndexReplace: false,
      indexCaseSensitive: true,
      indexType: CindelIndexType.value,
    ),
    CindelFieldSchema(
      name: "status",
      dartType: "PaymentStatus",
      binaryType: "string",
      isId: false,
      isIndexed: true,
      isIndexUnique: false,
      isIndexReplace: false,
      indexCaseSensitive: true,
      indexType: CindelIndexType.value,
    ),
    CindelFieldSchema(
      name: "amount",
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
      name: "authorizedAt",
      dartType: "DateTime",
      binaryType: "int",
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
      backlinkTo: "payment",
    ),
  ],
  compositeIndexes: <CindelCompositeIndexSchema>[],
  toDocument: _$PaymentToCindelDocument,
  fromDocument: _$PaymentFromCindelDocument,
  toBinaryDocument: _$PaymentToCindelBinaryDocument,
  fromBinaryDocument: _$PaymentFromCindelBinaryDocument,
  writeNativeDocument: _$PaymentWriteCindelNativeDocument,
  readNativeDocument: _$PaymentReadCindelNativeDocument,
  getId: _$PaymentGetCindelId,
  setId: _$PaymentSetCindelId,
  bindLinks: _$PaymentBindCindelLinks,
);

void _$PaymentBindCindelLinks(
  Object database,
  CindelCollectionSchema<Payment> schema,
  Payment object,
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

extension PaymentCindelCollectionAccess on CindelDatabase {
  CindelTypedCollection<Payment> get payments => typedCollection(PaymentSchema);
}

extension PaymentCindelQueryAccess on CindelTypedCollection<Payment> {
  PaymentQueryWhere where() => PaymentQueryWhere(this);

  PaymentQueryFilter filter() => PaymentQueryFilter(
    CindelQuery.all(database: database, schema: PaymentSchema),
  );

  Future<void> putByTransactionId(Payment object) {
    return putByUniqueIndex(
      object,
      indexName: "transactionId",
      values: <Object?>[object.transactionId],
      isComposite: false,
    );
  }

  Future<void> putAllByTransactionId(Iterable<Payment> objects) {
    return putAllByUniqueIndex(
      objects,
      indexName: "transactionId",
      values: (object) => <Object?>[object.transactionId],
      isComposite: false,
    );
  }
}

extension PaymentCindelQueryFilterAccess on CindelQuery<Payment> {
  PaymentQueryFilter filter() => PaymentQueryFilter(this);
}

extension PaymentCindelQueryModifierAccess on CindelQuery<Payment> {
  CindelQuery<Payment> sortByDbId({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return sortBy("dbId", order: order);
  }

  CindelQuery<Payment> sortByDbIdDesc() {
    return sortBy("dbId", order: CindelSortOrder.descending);
  }

  CindelQuery<Payment> thenByDbId({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return thenBy("dbId", order: order);
  }

  CindelQuery<Payment> thenByDbIdDesc() {
    return thenBy("dbId", order: CindelSortOrder.descending);
  }

  CindelQuery<Payment> distinctByDbId() {
    return distinctBy("dbId");
  }

  CindelPropertyQuery<Payment, int> dbIdProperty() {
    return property<int>("dbId");
  }

  CindelQuery<Payment> sortByTransactionId({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return sortBy("transactionId", order: order);
  }

  CindelQuery<Payment> sortByTransactionIdDesc() {
    return sortBy("transactionId", order: CindelSortOrder.descending);
  }

  CindelQuery<Payment> thenByTransactionId({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return thenBy("transactionId", order: order);
  }

  CindelQuery<Payment> thenByTransactionIdDesc() {
    return thenBy("transactionId", order: CindelSortOrder.descending);
  }

  CindelQuery<Payment> distinctByTransactionId() {
    return distinctBy("transactionId");
  }

  CindelPropertyQuery<Payment, String> transactionIdProperty() {
    return property<String>("transactionId");
  }

  CindelQuery<Payment> sortByMethod({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return sortBy("method", order: order);
  }

  CindelQuery<Payment> sortByMethodDesc() {
    return sortBy("method", order: CindelSortOrder.descending);
  }

  CindelQuery<Payment> thenByMethod({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return thenBy("method", order: order);
  }

  CindelQuery<Payment> thenByMethodDesc() {
    return thenBy("method", order: CindelSortOrder.descending);
  }

  CindelQuery<Payment> distinctByMethod() {
    return distinctBy("method");
  }

  CindelPropertyQuery<Payment, PaymentMethod> methodProperty() {
    return property<PaymentMethod>(
      "method",
      decode: (value) => PaymentMethod.values.byName(value as String),
    );
  }

  CindelQuery<Payment> sortByStatus({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return sortBy("status", order: order);
  }

  CindelQuery<Payment> sortByStatusDesc() {
    return sortBy("status", order: CindelSortOrder.descending);
  }

  CindelQuery<Payment> thenByStatus({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return thenBy("status", order: order);
  }

  CindelQuery<Payment> thenByStatusDesc() {
    return thenBy("status", order: CindelSortOrder.descending);
  }

  CindelQuery<Payment> distinctByStatus() {
    return distinctBy("status");
  }

  CindelPropertyQuery<Payment, PaymentStatus> statusProperty() {
    return property<PaymentStatus>(
      "status",
      decode: (value) => PaymentStatus.values.byName(value as String),
    );
  }

  CindelQuery<Payment> sortByAmount({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return sortBy("amount", order: order);
  }

  CindelQuery<Payment> sortByAmountDesc() {
    return sortBy("amount", order: CindelSortOrder.descending);
  }

  CindelQuery<Payment> thenByAmount({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return thenBy("amount", order: order);
  }

  CindelQuery<Payment> thenByAmountDesc() {
    return thenBy("amount", order: CindelSortOrder.descending);
  }

  CindelQuery<Payment> distinctByAmount() {
    return distinctBy("amount");
  }

  CindelPropertyQuery<Payment, double> amountProperty() {
    return property<double>("amount");
  }

  CindelQuery<Payment> sortByAuthorizedAt({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return sortBy("authorizedAt", order: order);
  }

  CindelQuery<Payment> sortByAuthorizedAtDesc() {
    return sortBy("authorizedAt", order: CindelSortOrder.descending);
  }

  CindelQuery<Payment> thenByAuthorizedAt({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return thenBy("authorizedAt", order: order);
  }

  CindelQuery<Payment> thenByAuthorizedAtDesc() {
    return thenBy("authorizedAt", order: CindelSortOrder.descending);
  }

  CindelQuery<Payment> distinctByAuthorizedAt() {
    return distinctBy("authorizedAt");
  }

  CindelPropertyQuery<Payment, DateTime> authorizedAtProperty() {
    return property<DateTime>(
      "authorizedAt",
      decode: (value) =>
          DateTime.fromMicrosecondsSinceEpoch(value as int, isUtc: true),
    );
  }
}

final class PaymentQueryFilter {
  const PaymentQueryFilter(this._query);

  final CindelQuery<Payment> _query;

  CindelQuery<Payment> dbIdEqualTo(int value) {
    return _query.whereMatches(CindelFilter.field("dbId").equalTo(value));
  }

  CindelQuery<Payment> dbIdGreaterThan(int value) {
    return _query.whereMatches(CindelFilter.field("dbId").greaterThan(value));
  }

  CindelQuery<Payment> dbIdGreaterThanOrEqualTo(int value) {
    return _query.whereMatches(
      CindelFilter.field("dbId").greaterThanOrEqualTo(value),
    );
  }

  CindelQuery<Payment> dbIdLessThan(int value) {
    return _query.whereMatches(CindelFilter.field("dbId").lessThan(value));
  }

  CindelQuery<Payment> dbIdLessThanOrEqualTo(int value) {
    return _query.whereMatches(
      CindelFilter.field("dbId").lessThanOrEqualTo(value),
    );
  }

  CindelQuery<Payment> dbIdBetween(int? lower, int? upper) {
    return _query.whereMatches(
      CindelFilter.field("dbId").between(lower, upper),
    );
  }

  CindelQuery<Payment> transactionIdEqualTo(String value) {
    return _query.whereMatches(
      CindelFilter.field("transactionId").equalTo(value),
    );
  }

  CindelQuery<Payment> transactionIdContains(String value) {
    return _query.whereMatches(
      CindelFilter.field("transactionId").contains(value),
    );
  }

  CindelQuery<Payment> transactionIdStartsWith(String value) {
    return _query.whereMatches(
      CindelFilter.field("transactionId").startsWith(value),
    );
  }

  CindelQuery<Payment> transactionIdEndsWith(String value) {
    return _query.whereMatches(
      CindelFilter.field("transactionId").endsWith(value),
    );
  }

  CindelQuery<Payment> methodEqualTo(PaymentMethod value) {
    return _query.whereMatches(
      CindelFilter.field("method").equalTo(value.name),
    );
  }

  CindelQuery<Payment> statusEqualTo(PaymentStatus value) {
    return _query.whereMatches(
      CindelFilter.field("status").equalTo(value.name),
    );
  }

  CindelQuery<Payment> amountEqualTo(double value) {
    return _query.whereMatches(CindelFilter.field("amount").equalTo(value));
  }

  CindelQuery<Payment> amountGreaterThan(double value) {
    return _query.whereMatches(CindelFilter.field("amount").greaterThan(value));
  }

  CindelQuery<Payment> amountGreaterThanOrEqualTo(double value) {
    return _query.whereMatches(
      CindelFilter.field("amount").greaterThanOrEqualTo(value),
    );
  }

  CindelQuery<Payment> amountLessThan(double value) {
    return _query.whereMatches(CindelFilter.field("amount").lessThan(value));
  }

  CindelQuery<Payment> amountLessThanOrEqualTo(double value) {
    return _query.whereMatches(
      CindelFilter.field("amount").lessThanOrEqualTo(value),
    );
  }

  CindelQuery<Payment> amountBetween(double? lower, double? upper) {
    return _query.whereMatches(
      CindelFilter.field("amount").between(lower, upper),
    );
  }

  CindelQuery<Payment> authorizedAtEqualTo(DateTime value) {
    return _query.whereMatches(
      CindelFilter.field("authorizedAt").equalTo(value.microsecondsSinceEpoch),
    );
  }

  CindelQuery<Payment> authorizedAtGreaterThan(DateTime value) {
    return _query.whereMatches(
      CindelFilter.field(
        "authorizedAt",
      ).greaterThan(value.microsecondsSinceEpoch),
    );
  }

  CindelQuery<Payment> authorizedAtGreaterThanOrEqualTo(DateTime value) {
    return _query.whereMatches(
      CindelFilter.field(
        "authorizedAt",
      ).greaterThanOrEqualTo(value.microsecondsSinceEpoch),
    );
  }

  CindelQuery<Payment> authorizedAtLessThan(DateTime value) {
    return _query.whereMatches(
      CindelFilter.field("authorizedAt").lessThan(value.microsecondsSinceEpoch),
    );
  }

  CindelQuery<Payment> authorizedAtLessThanOrEqualTo(DateTime value) {
    return _query.whereMatches(
      CindelFilter.field(
        "authorizedAt",
      ).lessThanOrEqualTo(value.microsecondsSinceEpoch),
    );
  }

  CindelQuery<Payment> authorizedAtBetween(DateTime? lower, DateTime? upper) {
    return _query.whereMatches(
      CindelFilter.field(
        "authorizedAt",
      ).between(lower?.microsecondsSinceEpoch, upper?.microsecondsSinceEpoch),
    );
  }

  CindelQuery<Payment> optional(
    bool enabled,
    CindelQuery<Payment> Function(PaymentQueryFilter q) option,
  ) {
    return _query.optional(
      enabled,
      (query) => option(PaymentQueryFilter(query)),
    );
  }

  CindelQuery<Payment> anyOf<E>(
    Iterable<E> items,
    CindelQuery<Payment> Function(PaymentQueryFilter q, E item) option,
  ) {
    return _query.anyOf(
      items,
      (query, item) => option(PaymentQueryFilter(query), item),
    );
  }

  CindelQuery<Payment> allOf<E>(
    Iterable<E> items,
    CindelQuery<Payment> Function(PaymentQueryFilter q, E item) option,
  ) {
    return _query.allOf(
      items,
      (query, item) => option(PaymentQueryFilter(query), item),
    );
  }
}

final class PaymentQueryWhere {
  const PaymentQueryWhere(this._collection);

  final CindelTypedCollection<Payment> _collection;

  CindelQuery<Payment> transactionIdEqualTo(String value) {
    return CindelQuery.equal(
      database: _collection.database,
      schema: PaymentSchema,
      field: "transactionId",
      value: value,
    );
  }

  CindelQuery<Payment> transactionIdStartsWith(String prefix) {
    return CindelQuery.stringStartsWith(
      database: _collection.database,
      schema: PaymentSchema,
      field: "transactionId",
      prefix: prefix,
    );
  }

  CindelQuery<Payment> transactionIdBetween(String? lower, String? upper) {
    return CindelQuery.range(
      database: _collection.database,
      schema: PaymentSchema,
      field: "transactionId",
      lower: lower,
      upper: upper,
    );
  }

  CindelQuery<Payment> statusEqualTo(PaymentStatus value) {
    return CindelQuery.equal(
      database: _collection.database,
      schema: PaymentSchema,
      field: "status",
      value: value.name,
    );
  }
}

Map<String, Object?> _$PaymentToCindelDocument(Payment object) {
  return <String, Object?>{
    "transactionId": object.transactionId,
    "method": object.method.name,
    "status": object.status.name,
    "amount": object.amount,
    "authorizedAt": object.authorizedAt.microsecondsSinceEpoch,
  };
}

Payment _$PaymentFromCindelDocument(Map<String, Object?> document) {
  final object = Payment();
  object.dbId = document["dbId"] as int;
  object.transactionId = document["transactionId"] as String;
  object.method = PaymentMethod.values.byName(document["method"] as String);
  object.status = PaymentStatus.values.byName(document["status"] as String);
  object.amount = document["amount"] as double;
  object.authorizedAt = DateTime.fromMicrosecondsSinceEpoch(
    document["authorizedAt"] as int,
    isUtc: true,
  );
  return object;
}

CindelBinaryDocumentBytes _$PaymentToCindelBinaryDocument(Payment object) {
  return cindelEncodeSchemaBinaryDocument(
    <Object?>[
      object.amount,
      object.authorizedAt.microsecondsSinceEpoch,
      object.method.name,
      object.status.name,
      object.transactionId,
    ],
    const <CindelBinaryFieldType>[
      CindelBinaryFieldType.doubleValue,
      CindelBinaryFieldType.intValue,
      CindelBinaryFieldType.stringValue,
      CindelBinaryFieldType.stringValue,
      CindelBinaryFieldType.stringValue,
    ],
  );
}

Payment _$PaymentFromCindelBinaryDocument(CindelBinaryDocumentBytes bytes) {
  final reader = CindelSchemaBinaryDocumentReader(bytes, staticSize: 25);
  final Object? field0 = reader.readDouble(0, 0);
  final Object? field1 = reader.readInt(1, 8);
  final Object? field2 = reader.readString(2, 16);
  final Object? field3 = reader.readString(3, 19);
  final Object? field4 = reader.readString(4, 22);
  final object = Payment();
  object.dbId = autoIncrement;
  object.transactionId = field4 as String;
  object.method = PaymentMethod.values.byName(field2 as String);
  object.status = PaymentStatus.values.byName(field3 as String);
  object.amount = field0 as double;
  object.authorizedAt = DateTime.fromMicrosecondsSinceEpoch(
    field1 as int,
    isUtc: true,
  );
  return object;
}

void _$PaymentWriteCindelNativeDocument(
  CindelNativeDocumentWriter writer,
  Payment object,
) {
  writer.writeDouble(0, object.amount);
  writer.writeInt(1, object.authorizedAt.microsecondsSinceEpoch);
  writer.writeString(2, object.method.name);
  writer.writeString(3, object.status.name);
  writer.writeString(4, object.transactionId);
}

Payment _$PaymentReadCindelNativeDocument(
  CindelNativeDocumentReader reader,
  int documentIndex,
) {
  final object = Payment();
  object.dbId = reader.readId(documentIndex);
  object.transactionId = reader.readString(documentIndex, 4) as String;
  object.method = PaymentMethod.values.byName(
    reader.readString(documentIndex, 2) as String,
  );
  object.status = PaymentStatus.values.byName(
    reader.readString(documentIndex, 3) as String,
  );
  object.amount = reader.readDouble(documentIndex, 0) as double;
  object.authorizedAt = DateTime.fromMicrosecondsSinceEpoch(
    reader.readInt(documentIndex, 1) as int,
    isUtc: true,
  );
  return object;
}

int _$PaymentGetCindelId(Payment object) {
  return object.dbId;
}

void _$PaymentSetCindelId(Payment object, int id) {
  object.dbId = id;
}
