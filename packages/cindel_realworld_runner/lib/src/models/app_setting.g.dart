// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_setting.dart';

// **************************************************************************
// CindelGenerator
// **************************************************************************

// ignore_for_file: non_constant_identifier_names

final AppSettingSchema = CindelCollectionSchema<AppSetting>(
  name: "appSettings",
  dartName: "AppSetting",
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
      name: "key",
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
      name: "value",
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
      name: "enabled",
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
      name: "updatedAt",
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
  links: <CindelLinkSchema>[],
  compositeIndexes: <CindelCompositeIndexSchema>[],
  toDocument: _$AppSettingToCindelDocument,
  fromDocument: _$AppSettingFromCindelDocument,
  toBinaryDocument: _$AppSettingToCindelBinaryDocument,
  fromBinaryDocument: _$AppSettingFromCindelBinaryDocument,
  writeNativeDocument: _$AppSettingWriteCindelNativeDocument,
  readNativeDocument: _$AppSettingReadCindelNativeDocument,
  getId: _$AppSettingGetCindelId,
  setId: _$AppSettingSetCindelId,
);

extension AppSettingCindelCollectionAccess on CindelDatabase {
  CindelTypedCollection<AppSetting> get appSettings =>
      typedCollection(AppSettingSchema);
}

extension AppSettingCindelQueryAccess on CindelTypedCollection<AppSetting> {
  AppSettingQueryWhere where() => AppSettingQueryWhere(this);

  AppSettingQueryFilter filter() => AppSettingQueryFilter(
    CindelQuery.all(database: database, schema: AppSettingSchema),
  );

  Future<void> putByKey(AppSetting object) {
    return putByUniqueIndex(
      object,
      indexName: "key",
      values: <Object?>[object.key],
      isComposite: false,
    );
  }

  Future<void> putAllByKey(Iterable<AppSetting> objects) {
    return putAllByUniqueIndex(
      objects,
      indexName: "key",
      values: (object) => <Object?>[object.key],
      isComposite: false,
    );
  }
}

extension AppSettingCindelQueryFilterAccess on CindelQuery<AppSetting> {
  AppSettingQueryFilter filter() => AppSettingQueryFilter(this);
}

extension AppSettingCindelQueryModifierAccess on CindelQuery<AppSetting> {
  CindelQuery<AppSetting> sortByDbId({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return sortBy("dbId", order: order);
  }

  CindelQuery<AppSetting> sortByDbIdDesc() {
    return sortBy("dbId", order: CindelSortOrder.descending);
  }

  CindelQuery<AppSetting> thenByDbId({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return thenBy("dbId", order: order);
  }

  CindelQuery<AppSetting> thenByDbIdDesc() {
    return thenBy("dbId", order: CindelSortOrder.descending);
  }

  CindelQuery<AppSetting> distinctByDbId() {
    return distinctBy("dbId");
  }

  CindelPropertyQuery<AppSetting, int> dbIdProperty() {
    return property<int>("dbId");
  }

  CindelQuery<AppSetting> sortByKey({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return sortBy("key", order: order);
  }

  CindelQuery<AppSetting> sortByKeyDesc() {
    return sortBy("key", order: CindelSortOrder.descending);
  }

  CindelQuery<AppSetting> thenByKey({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return thenBy("key", order: order);
  }

  CindelQuery<AppSetting> thenByKeyDesc() {
    return thenBy("key", order: CindelSortOrder.descending);
  }

  CindelQuery<AppSetting> distinctByKey() {
    return distinctBy("key");
  }

  CindelPropertyQuery<AppSetting, String> keyProperty() {
    return property<String>("key");
  }

  CindelQuery<AppSetting> sortByValue({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return sortBy("value", order: order);
  }

  CindelQuery<AppSetting> sortByValueDesc() {
    return sortBy("value", order: CindelSortOrder.descending);
  }

  CindelQuery<AppSetting> thenByValue({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return thenBy("value", order: order);
  }

  CindelQuery<AppSetting> thenByValueDesc() {
    return thenBy("value", order: CindelSortOrder.descending);
  }

  CindelQuery<AppSetting> distinctByValue() {
    return distinctBy("value");
  }

  CindelPropertyQuery<AppSetting, String> valueProperty() {
    return property<String>("value");
  }

  CindelQuery<AppSetting> sortByEnabled({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return sortBy("enabled", order: order);
  }

  CindelQuery<AppSetting> sortByEnabledDesc() {
    return sortBy("enabled", order: CindelSortOrder.descending);
  }

  CindelQuery<AppSetting> thenByEnabled({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return thenBy("enabled", order: order);
  }

  CindelQuery<AppSetting> thenByEnabledDesc() {
    return thenBy("enabled", order: CindelSortOrder.descending);
  }

  CindelQuery<AppSetting> distinctByEnabled() {
    return distinctBy("enabled");
  }

  CindelPropertyQuery<AppSetting, bool> enabledProperty() {
    return property<bool>("enabled");
  }

  CindelQuery<AppSetting> sortByUpdatedAt({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return sortBy("updatedAt", order: order);
  }

  CindelQuery<AppSetting> sortByUpdatedAtDesc() {
    return sortBy("updatedAt", order: CindelSortOrder.descending);
  }

  CindelQuery<AppSetting> thenByUpdatedAt({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return thenBy("updatedAt", order: order);
  }

  CindelQuery<AppSetting> thenByUpdatedAtDesc() {
    return thenBy("updatedAt", order: CindelSortOrder.descending);
  }

  CindelQuery<AppSetting> distinctByUpdatedAt() {
    return distinctBy("updatedAt");
  }

  CindelPropertyQuery<AppSetting, DateTime> updatedAtProperty() {
    return property<DateTime>(
      "updatedAt",
      decode: (value) =>
          DateTime.fromMicrosecondsSinceEpoch(value as int, isUtc: true),
    );
  }
}

final class AppSettingQueryFilter {
  const AppSettingQueryFilter(this._query);

  final CindelQuery<AppSetting> _query;

  CindelQuery<AppSetting> dbIdEqualTo(int value) {
    return _query.whereMatches(CindelFilter.field("dbId").equalTo(value));
  }

  CindelQuery<AppSetting> dbIdGreaterThan(int value) {
    return _query.whereMatches(CindelFilter.field("dbId").greaterThan(value));
  }

  CindelQuery<AppSetting> dbIdGreaterThanOrEqualTo(int value) {
    return _query.whereMatches(
      CindelFilter.field("dbId").greaterThanOrEqualTo(value),
    );
  }

  CindelQuery<AppSetting> dbIdLessThan(int value) {
    return _query.whereMatches(CindelFilter.field("dbId").lessThan(value));
  }

  CindelQuery<AppSetting> dbIdLessThanOrEqualTo(int value) {
    return _query.whereMatches(
      CindelFilter.field("dbId").lessThanOrEqualTo(value),
    );
  }

  CindelQuery<AppSetting> dbIdBetween(int? lower, int? upper) {
    return _query.whereMatches(
      CindelFilter.field("dbId").between(lower, upper),
    );
  }

  CindelQuery<AppSetting> keyEqualTo(String value) {
    return _query.whereMatches(CindelFilter.field("key").equalTo(value));
  }

  CindelQuery<AppSetting> keyContains(String value) {
    return _query.whereMatches(CindelFilter.field("key").contains(value));
  }

  CindelQuery<AppSetting> keyStartsWith(String value) {
    return _query.whereMatches(CindelFilter.field("key").startsWith(value));
  }

  CindelQuery<AppSetting> keyEndsWith(String value) {
    return _query.whereMatches(CindelFilter.field("key").endsWith(value));
  }

  CindelQuery<AppSetting> valueEqualTo(String value) {
    return _query.whereMatches(CindelFilter.field("value").equalTo(value));
  }

  CindelQuery<AppSetting> valueContains(String value) {
    return _query.whereMatches(CindelFilter.field("value").contains(value));
  }

  CindelQuery<AppSetting> valueStartsWith(String value) {
    return _query.whereMatches(CindelFilter.field("value").startsWith(value));
  }

  CindelQuery<AppSetting> valueEndsWith(String value) {
    return _query.whereMatches(CindelFilter.field("value").endsWith(value));
  }

  CindelQuery<AppSetting> enabledEqualTo(bool value) {
    return _query.whereMatches(CindelFilter.field("enabled").equalTo(value));
  }

  CindelQuery<AppSetting> updatedAtEqualTo(DateTime value) {
    return _query.whereMatches(
      CindelFilter.field("updatedAt").equalTo(value.microsecondsSinceEpoch),
    );
  }

  CindelQuery<AppSetting> updatedAtGreaterThan(DateTime value) {
    return _query.whereMatches(
      CindelFilter.field("updatedAt").greaterThan(value.microsecondsSinceEpoch),
    );
  }

  CindelQuery<AppSetting> updatedAtGreaterThanOrEqualTo(DateTime value) {
    return _query.whereMatches(
      CindelFilter.field(
        "updatedAt",
      ).greaterThanOrEqualTo(value.microsecondsSinceEpoch),
    );
  }

  CindelQuery<AppSetting> updatedAtLessThan(DateTime value) {
    return _query.whereMatches(
      CindelFilter.field("updatedAt").lessThan(value.microsecondsSinceEpoch),
    );
  }

  CindelQuery<AppSetting> updatedAtLessThanOrEqualTo(DateTime value) {
    return _query.whereMatches(
      CindelFilter.field(
        "updatedAt",
      ).lessThanOrEqualTo(value.microsecondsSinceEpoch),
    );
  }

  CindelQuery<AppSetting> updatedAtBetween(DateTime? lower, DateTime? upper) {
    return _query.whereMatches(
      CindelFilter.field(
        "updatedAt",
      ).between(lower?.microsecondsSinceEpoch, upper?.microsecondsSinceEpoch),
    );
  }

  CindelQuery<AppSetting> optional(
    bool enabled,
    CindelQuery<AppSetting> Function(AppSettingQueryFilter q) option,
  ) {
    return _query.optional(
      enabled,
      (query) => option(AppSettingQueryFilter(query)),
    );
  }

  CindelQuery<AppSetting> anyOf<E>(
    Iterable<E> items,
    CindelQuery<AppSetting> Function(AppSettingQueryFilter q, E item) option,
  ) {
    return _query.anyOf(
      items,
      (query, item) => option(AppSettingQueryFilter(query), item),
    );
  }

  CindelQuery<AppSetting> allOf<E>(
    Iterable<E> items,
    CindelQuery<AppSetting> Function(AppSettingQueryFilter q, E item) option,
  ) {
    return _query.allOf(
      items,
      (query, item) => option(AppSettingQueryFilter(query), item),
    );
  }
}

final class AppSettingQueryWhere {
  const AppSettingQueryWhere(this._collection);

  final CindelTypedCollection<AppSetting> _collection;

  CindelQuery<AppSetting> keyEqualTo(String value) {
    return CindelQuery.equal(
      database: _collection.database,
      schema: AppSettingSchema,
      field: "key",
      value: value,
    );
  }

  CindelQuery<AppSetting> keyStartsWith(String prefix) {
    return CindelQuery.stringStartsWith(
      database: _collection.database,
      schema: AppSettingSchema,
      field: "key",
      prefix: prefix,
    );
  }

  CindelQuery<AppSetting> keyBetween(String? lower, String? upper) {
    return CindelQuery.range(
      database: _collection.database,
      schema: AppSettingSchema,
      field: "key",
      lower: lower,
      upper: upper,
    );
  }
}

Map<String, Object?> _$AppSettingToCindelDocument(AppSetting object) {
  return <String, Object?>{
    "key": object.key,
    "value": object.value,
    "enabled": object.enabled,
    "updatedAt": object.updatedAt.microsecondsSinceEpoch,
  };
}

AppSetting _$AppSettingFromCindelDocument(Map<String, Object?> document) {
  final object = AppSetting();
  object.dbId = document["dbId"] as int;
  object.key = document["key"] as String;
  object.value = document["value"] as String;
  object.enabled = document["enabled"] as bool;
  object.updatedAt = DateTime.fromMicrosecondsSinceEpoch(
    document["updatedAt"] as int,
    isUtc: true,
  );
  return object;
}

CindelBinaryDocumentBytes _$AppSettingToCindelBinaryDocument(
  AppSetting object,
) {
  return cindelEncodeSchemaBinaryDocument(
    <Object?>[
      object.enabled,
      object.key,
      object.updatedAt.microsecondsSinceEpoch,
      object.value,
    ],
    const <CindelBinaryFieldType>[
      CindelBinaryFieldType.boolValue,
      CindelBinaryFieldType.stringValue,
      CindelBinaryFieldType.intValue,
      CindelBinaryFieldType.stringValue,
    ],
  );
}

AppSetting _$AppSettingFromCindelBinaryDocument(
  CindelBinaryDocumentBytes bytes,
) {
  final reader = CindelSchemaBinaryDocumentReader(bytes, staticSize: 15);
  final Object? field0 = reader.readBool(0, 0);
  final Object? field1 = reader.readString(1, 1);
  final Object? field2 = reader.readInt(2, 4);
  final Object? field3 = reader.readString(3, 12);
  final object = AppSetting();
  object.dbId = autoIncrement;
  object.key = field1 as String;
  object.value = field3 as String;
  object.enabled = field0 as bool;
  object.updatedAt = DateTime.fromMicrosecondsSinceEpoch(
    field2 as int,
    isUtc: true,
  );
  return object;
}

void _$AppSettingWriteCindelNativeDocument(
  CindelNativeDocumentWriter writer,
  AppSetting object,
) {
  writer.writeBool(0, object.enabled);
  writer.writeString(1, object.key);
  writer.writeInt(2, object.updatedAt.microsecondsSinceEpoch);
  writer.writeString(3, object.value);
}

AppSetting _$AppSettingReadCindelNativeDocument(
  CindelNativeDocumentReader reader,
  int documentIndex,
) {
  final object = AppSetting();
  object.dbId = reader.readId(documentIndex);
  object.key = reader.readString(documentIndex, 1) as String;
  object.value = reader.readString(documentIndex, 3) as String;
  object.enabled = reader.readBool(documentIndex, 0) as bool;
  object.updatedAt = DateTime.fromMicrosecondsSinceEpoch(
    reader.readInt(documentIndex, 2) as int,
    isUtc: true,
  );
  return object;
}

int _$AppSettingGetCindelId(AppSetting object) {
  return object.dbId;
}

void _$AppSettingSetCindelId(AppSetting object, int id) {
  object.dbId = id;
}
