// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'inventory_movement.dart';

// **************************************************************************
// CindelGenerator
// **************************************************************************

// ignore_for_file: non_constant_identifier_names

final InventoryMovementSchema = CindelCollectionSchema<InventoryMovement>(
  name: "inventoryMovements",
  dartName: "InventoryMovement",
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
      name: "reference",
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
      name: "quantity",
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
      name: "type",
      dartType: "MovementType",
      binaryType: "string",
      isId: false,
      isIndexed: false,
      isIndexUnique: false,
      isIndexReplace: false,
      indexCaseSensitive: true,
      indexType: CindelIndexType.value,
    ),
    CindelFieldSchema(
      name: "reason",
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
      name: "product",
      dartName: "product",
      targetCollection: "products",
      isToMany: false,
      isBacklink: false,
      backlinkTo: null,
    ),
  ],
  compositeIndexes: <CindelCompositeIndexSchema>[],
  toDocument: _$InventoryMovementToCindelDocument,
  fromDocument: _$InventoryMovementFromCindelDocument,
  toBinaryDocument: _$InventoryMovementToCindelBinaryDocument,
  fromBinaryDocument: _$InventoryMovementFromCindelBinaryDocument,
  writeNativeDocument: _$InventoryMovementWriteCindelNativeDocument,
  readNativeDocument: _$InventoryMovementReadCindelNativeDocument,
  getId: _$InventoryMovementGetCindelId,
  setId: _$InventoryMovementSetCindelId,
  bindLinks: _$InventoryMovementBindCindelLinks,
);

void _$InventoryMovementBindCindelLinks(
  Object database,
  CindelCollectionSchema<InventoryMovement> schema,
  InventoryMovement object,
) {
  final cindelDatabase = database as CindelDatabase;
  final ownerSchema = schema as dynamic;
  object.product.bind(
    cindelDatabase,
    ownerSchema,
    object,
    schema.links.firstWhere((link) => link.dartName == "product"),
  );
}

extension InventoryMovementCindelCollectionAccess on CindelDatabase {
  CindelTypedCollection<InventoryMovement> get inventoryMovements =>
      typedCollection(InventoryMovementSchema);
}

extension InventoryMovementCindelQueryAccess
    on CindelTypedCollection<InventoryMovement> {
  InventoryMovementQueryWhere where() => InventoryMovementQueryWhere(this);

  InventoryMovementQueryFilter filter() => InventoryMovementQueryFilter(
    CindelQuery.all(database: database, schema: InventoryMovementSchema),
  );

  Future<void> putByReference(InventoryMovement object) {
    return putByUniqueIndex(
      object,
      indexName: "reference",
      values: <Object?>[object.reference],
      isComposite: false,
    );
  }

  Future<void> putAllByReference(Iterable<InventoryMovement> objects) {
    return putAllByUniqueIndex(
      objects,
      indexName: "reference",
      values: (object) => <Object?>[object.reference],
      isComposite: false,
    );
  }
}

extension InventoryMovementCindelQueryFilterAccess
    on CindelQuery<InventoryMovement> {
  InventoryMovementQueryFilter filter() => InventoryMovementQueryFilter(this);
}

extension InventoryMovementCindelQueryModifierAccess
    on CindelQuery<InventoryMovement> {
  CindelQuery<InventoryMovement> sortByDbId({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return sortBy("dbId", order: order);
  }

  CindelQuery<InventoryMovement> sortByDbIdDesc() {
    return sortBy("dbId", order: CindelSortOrder.descending);
  }

  CindelQuery<InventoryMovement> thenByDbId({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return thenBy("dbId", order: order);
  }

  CindelQuery<InventoryMovement> thenByDbIdDesc() {
    return thenBy("dbId", order: CindelSortOrder.descending);
  }

  CindelQuery<InventoryMovement> distinctByDbId() {
    return distinctBy("dbId");
  }

  CindelPropertyQuery<InventoryMovement, int> dbIdProperty() {
    return property<int>("dbId");
  }

  CindelQuery<InventoryMovement> sortByReference({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return sortBy("reference", order: order);
  }

  CindelQuery<InventoryMovement> sortByReferenceDesc() {
    return sortBy("reference", order: CindelSortOrder.descending);
  }

  CindelQuery<InventoryMovement> thenByReference({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return thenBy("reference", order: order);
  }

  CindelQuery<InventoryMovement> thenByReferenceDesc() {
    return thenBy("reference", order: CindelSortOrder.descending);
  }

  CindelQuery<InventoryMovement> distinctByReference() {
    return distinctBy("reference");
  }

  CindelPropertyQuery<InventoryMovement, String> referenceProperty() {
    return property<String>("reference");
  }

  CindelQuery<InventoryMovement> sortByCreatedAt({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return sortBy("createdAt", order: order);
  }

  CindelQuery<InventoryMovement> sortByCreatedAtDesc() {
    return sortBy("createdAt", order: CindelSortOrder.descending);
  }

  CindelQuery<InventoryMovement> thenByCreatedAt({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return thenBy("createdAt", order: order);
  }

  CindelQuery<InventoryMovement> thenByCreatedAtDesc() {
    return thenBy("createdAt", order: CindelSortOrder.descending);
  }

  CindelQuery<InventoryMovement> distinctByCreatedAt() {
    return distinctBy("createdAt");
  }

  CindelPropertyQuery<InventoryMovement, DateTime> createdAtProperty() {
    return property<DateTime>(
      "createdAt",
      decode: (value) =>
          DateTime.fromMicrosecondsSinceEpoch(value as int, isUtc: true),
    );
  }

  CindelQuery<InventoryMovement> sortByQuantity({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return sortBy("quantity", order: order);
  }

  CindelQuery<InventoryMovement> sortByQuantityDesc() {
    return sortBy("quantity", order: CindelSortOrder.descending);
  }

  CindelQuery<InventoryMovement> thenByQuantity({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return thenBy("quantity", order: order);
  }

  CindelQuery<InventoryMovement> thenByQuantityDesc() {
    return thenBy("quantity", order: CindelSortOrder.descending);
  }

  CindelQuery<InventoryMovement> distinctByQuantity() {
    return distinctBy("quantity");
  }

  CindelPropertyQuery<InventoryMovement, int> quantityProperty() {
    return property<int>("quantity");
  }

  CindelQuery<InventoryMovement> sortByType({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return sortBy("type", order: order);
  }

  CindelQuery<InventoryMovement> sortByTypeDesc() {
    return sortBy("type", order: CindelSortOrder.descending);
  }

  CindelQuery<InventoryMovement> thenByType({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return thenBy("type", order: order);
  }

  CindelQuery<InventoryMovement> thenByTypeDesc() {
    return thenBy("type", order: CindelSortOrder.descending);
  }

  CindelQuery<InventoryMovement> distinctByType() {
    return distinctBy("type");
  }

  CindelPropertyQuery<InventoryMovement, MovementType> typeProperty() {
    return property<MovementType>(
      "type",
      decode: (value) => MovementType.values.byName(value as String),
    );
  }

  CindelQuery<InventoryMovement> sortByReason({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return sortBy("reason", order: order);
  }

  CindelQuery<InventoryMovement> sortByReasonDesc() {
    return sortBy("reason", order: CindelSortOrder.descending);
  }

  CindelQuery<InventoryMovement> thenByReason({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return thenBy("reason", order: order);
  }

  CindelQuery<InventoryMovement> thenByReasonDesc() {
    return thenBy("reason", order: CindelSortOrder.descending);
  }

  CindelQuery<InventoryMovement> distinctByReason() {
    return distinctBy("reason");
  }

  CindelPropertyQuery<InventoryMovement, String?> reasonProperty() {
    return property<String?>("reason");
  }
}

final class InventoryMovementQueryFilter {
  const InventoryMovementQueryFilter(this._query);

  final CindelQuery<InventoryMovement> _query;

  CindelQuery<InventoryMovement> dbIdEqualTo(int value) {
    return _query.whereMatches(CindelFilter.field("dbId").equalTo(value));
  }

  CindelQuery<InventoryMovement> dbIdGreaterThan(int value) {
    return _query.whereMatches(CindelFilter.field("dbId").greaterThan(value));
  }

  CindelQuery<InventoryMovement> dbIdGreaterThanOrEqualTo(int value) {
    return _query.whereMatches(
      CindelFilter.field("dbId").greaterThanOrEqualTo(value),
    );
  }

  CindelQuery<InventoryMovement> dbIdLessThan(int value) {
    return _query.whereMatches(CindelFilter.field("dbId").lessThan(value));
  }

  CindelQuery<InventoryMovement> dbIdLessThanOrEqualTo(int value) {
    return _query.whereMatches(
      CindelFilter.field("dbId").lessThanOrEqualTo(value),
    );
  }

  CindelQuery<InventoryMovement> dbIdBetween(int? lower, int? upper) {
    return _query.whereMatches(
      CindelFilter.field("dbId").between(lower, upper),
    );
  }

  CindelQuery<InventoryMovement> referenceEqualTo(String value) {
    return _query.whereMatches(CindelFilter.field("reference").equalTo(value));
  }

  CindelQuery<InventoryMovement> referenceContains(String value) {
    return _query.whereMatches(CindelFilter.field("reference").contains(value));
  }

  CindelQuery<InventoryMovement> referenceStartsWith(String value) {
    return _query.whereMatches(
      CindelFilter.field("reference").startsWith(value),
    );
  }

  CindelQuery<InventoryMovement> referenceEndsWith(String value) {
    return _query.whereMatches(CindelFilter.field("reference").endsWith(value));
  }

  CindelQuery<InventoryMovement> createdAtEqualTo(DateTime value) {
    return _query.whereMatches(
      CindelFilter.field("createdAt").equalTo(value.microsecondsSinceEpoch),
    );
  }

  CindelQuery<InventoryMovement> createdAtGreaterThan(DateTime value) {
    return _query.whereMatches(
      CindelFilter.field("createdAt").greaterThan(value.microsecondsSinceEpoch),
    );
  }

  CindelQuery<InventoryMovement> createdAtGreaterThanOrEqualTo(DateTime value) {
    return _query.whereMatches(
      CindelFilter.field(
        "createdAt",
      ).greaterThanOrEqualTo(value.microsecondsSinceEpoch),
    );
  }

  CindelQuery<InventoryMovement> createdAtLessThan(DateTime value) {
    return _query.whereMatches(
      CindelFilter.field("createdAt").lessThan(value.microsecondsSinceEpoch),
    );
  }

  CindelQuery<InventoryMovement> createdAtLessThanOrEqualTo(DateTime value) {
    return _query.whereMatches(
      CindelFilter.field(
        "createdAt",
      ).lessThanOrEqualTo(value.microsecondsSinceEpoch),
    );
  }

  CindelQuery<InventoryMovement> createdAtBetween(
    DateTime? lower,
    DateTime? upper,
  ) {
    return _query.whereMatches(
      CindelFilter.field(
        "createdAt",
      ).between(lower?.microsecondsSinceEpoch, upper?.microsecondsSinceEpoch),
    );
  }

  CindelQuery<InventoryMovement> quantityEqualTo(int value) {
    return _query.whereMatches(CindelFilter.field("quantity").equalTo(value));
  }

  CindelQuery<InventoryMovement> quantityGreaterThan(int value) {
    return _query.whereMatches(
      CindelFilter.field("quantity").greaterThan(value),
    );
  }

  CindelQuery<InventoryMovement> quantityGreaterThanOrEqualTo(int value) {
    return _query.whereMatches(
      CindelFilter.field("quantity").greaterThanOrEqualTo(value),
    );
  }

  CindelQuery<InventoryMovement> quantityLessThan(int value) {
    return _query.whereMatches(CindelFilter.field("quantity").lessThan(value));
  }

  CindelQuery<InventoryMovement> quantityLessThanOrEqualTo(int value) {
    return _query.whereMatches(
      CindelFilter.field("quantity").lessThanOrEqualTo(value),
    );
  }

  CindelQuery<InventoryMovement> quantityBetween(int? lower, int? upper) {
    return _query.whereMatches(
      CindelFilter.field("quantity").between(lower, upper),
    );
  }

  CindelQuery<InventoryMovement> typeEqualTo(MovementType value) {
    return _query.whereMatches(CindelFilter.field("type").equalTo(value.name));
  }

  CindelQuery<InventoryMovement> reasonEqualTo(String? value) {
    return _query.whereMatches(CindelFilter.field("reason").equalTo(value));
  }

  CindelQuery<InventoryMovement> reasonContains(String value) {
    return _query.whereMatches(CindelFilter.field("reason").contains(value));
  }

  CindelQuery<InventoryMovement> reasonStartsWith(String value) {
    return _query.whereMatches(CindelFilter.field("reason").startsWith(value));
  }

  CindelQuery<InventoryMovement> reasonEndsWith(String value) {
    return _query.whereMatches(CindelFilter.field("reason").endsWith(value));
  }

  CindelQuery<InventoryMovement> optional(
    bool enabled,
    CindelQuery<InventoryMovement> Function(InventoryMovementQueryFilter q)
    option,
  ) {
    return _query.optional(
      enabled,
      (query) => option(InventoryMovementQueryFilter(query)),
    );
  }

  CindelQuery<InventoryMovement> anyOf<E>(
    Iterable<E> items,
    CindelQuery<InventoryMovement> Function(
      InventoryMovementQueryFilter q,
      E item,
    )
    option,
  ) {
    return _query.anyOf(
      items,
      (query, item) => option(InventoryMovementQueryFilter(query), item),
    );
  }

  CindelQuery<InventoryMovement> allOf<E>(
    Iterable<E> items,
    CindelQuery<InventoryMovement> Function(
      InventoryMovementQueryFilter q,
      E item,
    )
    option,
  ) {
    return _query.allOf(
      items,
      (query, item) => option(InventoryMovementQueryFilter(query), item),
    );
  }
}

final class InventoryMovementQueryWhere {
  const InventoryMovementQueryWhere(this._collection);

  final CindelTypedCollection<InventoryMovement> _collection;

  CindelQuery<InventoryMovement> referenceEqualTo(String value) {
    return CindelQuery.equal(
      database: _collection.database,
      schema: InventoryMovementSchema,
      field: "reference",
      value: value,
    );
  }

  CindelQuery<InventoryMovement> referenceStartsWith(String prefix) {
    return CindelQuery.stringStartsWith(
      database: _collection.database,
      schema: InventoryMovementSchema,
      field: "reference",
      prefix: prefix,
    );
  }

  CindelQuery<InventoryMovement> referenceBetween(
    String? lower,
    String? upper,
  ) {
    return CindelQuery.range(
      database: _collection.database,
      schema: InventoryMovementSchema,
      field: "reference",
      lower: lower,
      upper: upper,
    );
  }

  CindelQuery<InventoryMovement> createdAtEqualTo(DateTime value) {
    return CindelQuery.equal(
      database: _collection.database,
      schema: InventoryMovementSchema,
      field: "createdAt",
      value: value.microsecondsSinceEpoch,
    );
  }

  CindelQuery<InventoryMovement> createdAtBetween(
    DateTime? lower,
    DateTime? upper,
  ) {
    return CindelQuery.range(
      database: _collection.database,
      schema: InventoryMovementSchema,
      field: "createdAt",
      lower: lower?.microsecondsSinceEpoch,
      upper: upper?.microsecondsSinceEpoch,
    );
  }
}

Map<String, Object?> _$InventoryMovementToCindelDocument(
  InventoryMovement object,
) {
  return <String, Object?>{
    "reference": object.reference,
    "createdAt": object.createdAt.microsecondsSinceEpoch,
    "quantity": object.quantity,
    "type": object.type.name,
    "reason": object.reason,
  };
}

InventoryMovement _$InventoryMovementFromCindelDocument(
  Map<String, Object?> document,
) {
  final object = InventoryMovement();
  object.dbId = document["dbId"] as int;
  object.reference = document["reference"] as String;
  object.createdAt = DateTime.fromMicrosecondsSinceEpoch(
    document["createdAt"] as int,
    isUtc: true,
  );
  object.quantity = document["quantity"] as int;
  object.type = MovementType.values.byName(document["type"] as String);
  object.reason = document["reason"] == null
      ? null
      : document["reason"] as String?;
  return object;
}

CindelBinaryDocumentBytes _$InventoryMovementToCindelBinaryDocument(
  InventoryMovement object,
) {
  return cindelEncodeSchemaBinaryDocument(
    <Object?>[
      object.createdAt.microsecondsSinceEpoch,
      object.quantity,
      object.reason,
      object.reference,
      object.type.name,
    ],
    const <CindelBinaryFieldType>[
      CindelBinaryFieldType.intValue,
      CindelBinaryFieldType.intValue,
      CindelBinaryFieldType.stringValue,
      CindelBinaryFieldType.stringValue,
      CindelBinaryFieldType.stringValue,
    ],
  );
}

InventoryMovement _$InventoryMovementFromCindelBinaryDocument(
  CindelBinaryDocumentBytes bytes,
) {
  final reader = CindelSchemaBinaryDocumentReader(bytes, staticSize: 25);
  final Object? field0 = reader.readInt(0, 0);
  final Object? field1 = reader.readInt(1, 8);
  final Object? field2 = reader.readString(2, 16);
  final Object? field3 = reader.readString(3, 19);
  final Object? field4 = reader.readString(4, 22);
  final object = InventoryMovement();
  object.dbId = autoIncrement;
  object.reference = field3 as String;
  object.createdAt = DateTime.fromMicrosecondsSinceEpoch(
    field0 as int,
    isUtc: true,
  );
  object.quantity = field1 as int;
  object.type = MovementType.values.byName(field4 as String);
  object.reason = field2 == null ? null : field2 as String?;
  return object;
}

void _$InventoryMovementWriteCindelNativeDocument(
  CindelNativeDocumentWriter writer,
  InventoryMovement object,
) {
  writer.writeInt(0, object.createdAt.microsecondsSinceEpoch);
  writer.writeInt(1, object.quantity);
  {
    final value = object.reason;
    if (value == null) {
      writer.writeNull(2);
    } else {
      writer.writeString(2, value);
    }
  }
  writer.writeString(3, object.reference);
  writer.writeString(4, object.type.name);
}

InventoryMovement _$InventoryMovementReadCindelNativeDocument(
  CindelNativeDocumentReader reader,
  int documentIndex,
) {
  final object = InventoryMovement();
  object.dbId = reader.readId(documentIndex);
  object.reference = reader.readString(documentIndex, 3) as String;
  object.createdAt = DateTime.fromMicrosecondsSinceEpoch(
    reader.readInt(documentIndex, 0) as int,
    isUtc: true,
  );
  object.quantity = reader.readInt(documentIndex, 1) as int;
  object.type = MovementType.values.byName(
    reader.readString(documentIndex, 4) as String,
  );
  object.reason = reader.readString(documentIndex, 2);
  return object;
}

int _$InventoryMovementGetCindelId(InventoryMovement object) {
  return object.dbId;
}

void _$InventoryMovementSetCindelId(InventoryMovement object, int id) {
  object.dbId = id;
}
