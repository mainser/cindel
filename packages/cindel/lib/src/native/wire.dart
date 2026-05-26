import 'dart:convert';
import 'dart:typed_data';

const int wireTagNull = 0;
const int wireTagBool = 1;
const int wireTagInt = 2;
const int wireTagDouble = 3;
const int wireTagString = 4;
const int wireTagList = 5;
const int wireTagObject = 6;

const int wireFilterTagField = 1;
const int wireFilterTagAll = 2;
const int wireFilterTagAny = 3;
const int wireFilterTagNot = 4;

const int wireFilterOpEqual = 1;
const int wireFilterOpLessThan = 2;
const int wireFilterOpLessThanOrEqual = 3;
const int wireFilterOpGreaterThan = 4;
const int wireFilterOpGreaterThanOrEqual = 5;
const int wireFilterOpContains = 6;
const int wireFilterOpStartsWith = 7;
const int wireFilterOpEndsWith = 8;
const int wireFilterOpIsNull = 9;

const int wireQuerySourceAll = 1;
const int wireQuerySourceIndexEqual = 2;
const int wireQuerySourceIndexRange = 3;

sealed class WireIndexValue {
  const WireIndexValue();

  const factory WireIndexValue.nullValue() = WireIndexNull;
  const factory WireIndexValue.bool(bool value) = WireIndexBool;
  const factory WireIndexValue.int(int value) = WireIndexInt;
  const factory WireIndexValue.double(double value) = WireIndexDouble;
  const factory WireIndexValue.string(String value) = WireIndexString;
  const factory WireIndexValue.list(List<WireIndexValue> values) =
      WireIndexList;
}

final class WireIndexNull extends WireIndexValue {
  const WireIndexNull();

  @override
  bool operator ==(Object other) => other is WireIndexNull;

  @override
  int get hashCode => 0;
}

final class WireIndexBool extends WireIndexValue {
  const WireIndexBool(this.value);

  final bool value;

  @override
  bool operator ==(Object other) =>
      other is WireIndexBool && other.value == value;

  @override
  int get hashCode => Object.hash(WireIndexBool, value);
}

final class WireIndexInt extends WireIndexValue {
  const WireIndexInt(this.value);

  final int value;

  @override
  bool operator ==(Object other) =>
      other is WireIndexInt && other.value == value;

  @override
  int get hashCode => Object.hash(WireIndexInt, value);
}

final class WireIndexDouble extends WireIndexValue {
  const WireIndexDouble(this.value);

  final double value;

  @override
  bool operator ==(Object other) =>
      other is WireIndexDouble && other.value == value;

  @override
  int get hashCode => Object.hash(WireIndexDouble, value);
}

final class WireIndexString extends WireIndexValue {
  const WireIndexString(this.value);

  final String value;

  @override
  bool operator ==(Object other) =>
      other is WireIndexString && other.value == value;

  @override
  int get hashCode => Object.hash(WireIndexString, value);
}

final class WireIndexList extends WireIndexValue {
  const WireIndexList(this.values);

  final List<WireIndexValue> values;

  @override
  bool operator ==(Object other) =>
      other is WireIndexList && listEquals(other.values, values);

  @override
  int get hashCode => Object.hashAll(values);
}

sealed class WireScalar {
  const WireScalar();

  const factory WireScalar.nullValue() = WireScalarNull;
  const factory WireScalar.bool(bool value) = WireScalarBool;
  const factory WireScalar.int(int value) = WireScalarInt;
  const factory WireScalar.double(double value) = WireScalarDouble;
  const factory WireScalar.string(String value) = WireScalarString;
}

final class WireScalarNull extends WireScalar {
  const WireScalarNull();

  @override
  bool operator ==(Object other) => other is WireScalarNull;

  @override
  int get hashCode => 0;
}

final class WireScalarBool extends WireScalar {
  const WireScalarBool(this.value);

  final bool value;

  @override
  bool operator ==(Object other) =>
      other is WireScalarBool && other.value == value;

  @override
  int get hashCode => Object.hash(WireScalarBool, value);
}

final class WireScalarInt extends WireScalar {
  const WireScalarInt(this.value);

  final int value;

  @override
  bool operator ==(Object other) =>
      other is WireScalarInt && other.value == value;

  @override
  int get hashCode => Object.hash(WireScalarInt, value);
}

final class WireScalarDouble extends WireScalar {
  const WireScalarDouble(this.value);

  final double value;

  @override
  bool operator ==(Object other) =>
      other is WireScalarDouble && other.value == value;

  @override
  int get hashCode => Object.hash(WireScalarDouble, value);
}

final class WireScalarString extends WireScalar {
  const WireScalarString(this.value);

  final String value;

  @override
  bool operator ==(Object other) =>
      other is WireScalarString && other.value == value;

  @override
  int get hashCode => Object.hash(WireScalarString, value);
}

sealed class WireValue {
  const WireValue();

  const factory WireValue.nullValue() = WireNullValue;
  const factory WireValue.bool(bool value) = WireBoolValue;
  const factory WireValue.int(int value) = WireIntValue;
  const factory WireValue.double(double value) = WireDoubleValue;
  const factory WireValue.string(String value) = WireStringValue;
  const factory WireValue.list(List<WireValue> values) = WireListValue;
  const factory WireValue.object(List<WireObjectEntry> fields) =
      WireObjectValue;
}

final class WireNullValue extends WireValue {
  const WireNullValue();

  @override
  bool operator ==(Object other) => other is WireNullValue;

  @override
  int get hashCode => 0;
}

final class WireBoolValue extends WireValue {
  const WireBoolValue(this.value);

  final bool value;

  @override
  bool operator ==(Object other) =>
      other is WireBoolValue && other.value == value;

  @override
  int get hashCode => Object.hash(WireBoolValue, value);
}

final class WireIntValue extends WireValue {
  const WireIntValue(this.value);

  final int value;

  @override
  bool operator ==(Object other) =>
      other is WireIntValue && other.value == value;

  @override
  int get hashCode => Object.hash(WireIntValue, value);
}

final class WireDoubleValue extends WireValue {
  const WireDoubleValue(this.value);

  final double value;

  @override
  bool operator ==(Object other) =>
      other is WireDoubleValue && other.value == value;

  @override
  int get hashCode => Object.hash(WireDoubleValue, value);
}

final class WireStringValue extends WireValue {
  const WireStringValue(this.value);

  final String value;

  @override
  bool operator ==(Object other) =>
      other is WireStringValue && other.value == value;

  @override
  int get hashCode => Object.hash(WireStringValue, value);
}

final class WireListValue extends WireValue {
  const WireListValue(this.values);

  final List<WireValue> values;

  @override
  bool operator ==(Object other) =>
      other is WireListValue && listEquals(other.values, values);

  @override
  int get hashCode => Object.hashAll(values);
}

final class WireObjectValue extends WireValue {
  const WireObjectValue(this.fields);

  final List<WireObjectEntry> fields;

  @override
  bool operator ==(Object other) =>
      other is WireObjectValue && listEquals(other.fields, fields);

  @override
  int get hashCode => Object.hashAll(fields);
}

final class WireObjectEntry {
  const WireObjectEntry(this.name, this.value);

  final String name;
  final WireValue value;

  @override
  bool operator ==(Object other) =>
      other is WireObjectEntry && other.name == name && other.value == value;

  @override
  int get hashCode => Object.hash(name, value);
}

sealed class WireFilter {
  const WireFilter();

  const factory WireFilter.field({
    required String field,
    required WireFilterOperation operation,
    required WireValue value,
  }) = WireFieldFilter;
  const factory WireFilter.all(List<WireFilter> predicates) = WireAllFilter;
  const factory WireFilter.any(List<WireFilter> predicates) = WireAnyFilter;
  const factory WireFilter.not(WireFilter predicate) = WireNotFilter;
}

enum WireFilterOperation {
  equal,
  lessThan,
  lessThanOrEqual,
  greaterThan,
  greaterThanOrEqual,
  contains,
  startsWith,
  endsWith,
  isNull,
}

final class WireFieldFilter extends WireFilter {
  const WireFieldFilter({
    required this.field,
    required this.operation,
    required this.value,
  });

  final String field;
  final WireFilterOperation operation;
  final WireValue value;

  @override
  bool operator ==(Object other) =>
      other is WireFieldFilter &&
      other.field == field &&
      other.operation == operation &&
      other.value == value;

  @override
  int get hashCode => Object.hash(field, operation, value);
}

final class WireAllFilter extends WireFilter {
  const WireAllFilter(this.predicates);

  final List<WireFilter> predicates;

  @override
  bool operator ==(Object other) =>
      other is WireAllFilter && listEquals(other.predicates, predicates);

  @override
  int get hashCode => Object.hashAll(predicates);
}

final class WireAnyFilter extends WireFilter {
  const WireAnyFilter(this.predicates);

  final List<WireFilter> predicates;

  @override
  bool operator ==(Object other) =>
      other is WireAnyFilter && listEquals(other.predicates, predicates);

  @override
  int get hashCode => Object.hashAll(predicates);
}

final class WireNotFilter extends WireFilter {
  const WireNotFilter(this.predicate);

  final WireFilter predicate;

  @override
  bool operator ==(Object other) =>
      other is WireNotFilter && other.predicate == predicate;

  @override
  int get hashCode => Object.hash(WireNotFilter, predicate);
}

final class WireDocumentWrite {
  const WireDocumentWrite({required this.id, required this.bytes});

  final int id;
  final Uint8List bytes;

  @override
  bool operator ==(Object other) =>
      other is WireDocumentWrite &&
      other.id == id &&
      listEquals(other.bytes, bytes);

  @override
  int get hashCode => Object.hash(id, Object.hashAll(bytes));
}

final class WireIndexedDocumentWrite {
  const WireIndexedDocumentWrite({
    required this.id,
    required this.bytes,
    required this.indexes,
  });

  final int id;
  final Uint8List bytes;
  final List<WireIndexEntry> indexes;

  @override
  bool operator ==(Object other) {
    return other is WireIndexedDocumentWrite &&
        other.id == id &&
        listEquals(other.bytes, bytes) &&
        listEquals(other.indexes, indexes);
  }

  @override
  int get hashCode =>
      Object.hash(id, Object.hashAll(bytes), Object.hashAll(indexes));
}

final class WireProjectionRows {
  const WireProjectionRows({
    required this.rowCount,
    required this.columnCount,
    required this.cells,
  });

  final int rowCount;
  final int columnCount;
  final List<WireValue> cells;

  @override
  bool operator ==(Object other) =>
      other is WireProjectionRows &&
      other.rowCount == rowCount &&
      other.columnCount == columnCount &&
      listEquals(other.cells, cells);

  @override
  int get hashCode => Object.hash(rowCount, columnCount, Object.hashAll(cells));
}

final class WireSchemaManifest {
  const WireSchemaManifest({required this.version, required this.collections});

  final int version;
  final List<WireCollectionSchema> collections;

  @override
  bool operator ==(Object other) =>
      other is WireSchemaManifest &&
      other.version == version &&
      listEquals(other.collections, collections);

  @override
  int get hashCode => Object.hash(version, Object.hashAll(collections));
}

final class WireCollectionSchema {
  const WireCollectionSchema({
    required this.name,
    required this.idField,
    required this.fields,
    required this.indexes,
  });

  final String name;
  final String idField;
  final List<WireFieldSchema> fields;
  final List<WireIndexSchema> indexes;

  @override
  bool operator ==(Object other) =>
      other is WireCollectionSchema &&
      other.name == name &&
      other.idField == idField &&
      listEquals(other.fields, fields) &&
      listEquals(other.indexes, indexes);

  @override
  int get hashCode => Object.hash(
    name,
    idField,
    Object.hashAll(fields),
    Object.hashAll(indexes),
  );
}

final class WireFieldSchema {
  const WireFieldSchema({
    required this.name,
    required this.typeName,
    required this.binaryType,
    required this.indexType,
    required this.isId,
    required this.isIndexed,
    required this.isUnique,
    required this.isNullable,
    required this.caseSensitive,
  });

  final String name;
  final String typeName;
  final String binaryType;
  final String indexType;
  final bool isId;
  final bool isIndexed;
  final bool isUnique;
  final bool isNullable;
  final bool caseSensitive;

  @override
  bool operator ==(Object other) =>
      other is WireFieldSchema &&
      other.name == name &&
      other.typeName == typeName &&
      other.binaryType == binaryType &&
      other.indexType == indexType &&
      other.isId == isId &&
      other.isIndexed == isIndexed &&
      other.isUnique == isUnique &&
      other.isNullable == isNullable &&
      other.caseSensitive == caseSensitive;

  @override
  int get hashCode => Object.hash(
    name,
    typeName,
    binaryType,
    indexType,
    isId,
    isIndexed,
    isUnique,
    isNullable,
    caseSensitive,
  );
}

final class WireIndexSchema {
  const WireIndexSchema({
    required this.name,
    required this.fields,
    required this.isUnique,
    required this.caseSensitive,
  });

  final String name;
  final List<String> fields;
  final bool isUnique;
  final bool caseSensitive;

  @override
  bool operator ==(Object other) =>
      other is WireIndexSchema &&
      other.name == name &&
      listEquals(other.fields, fields) &&
      other.isUnique == isUnique &&
      other.caseSensitive == caseSensitive;

  @override
  int get hashCode =>
      Object.hash(name, Object.hashAll(fields), isUnique, caseSensitive);
}

final class WireIndexEntry {
  const WireIndexEntry({
    required this.documentId,
    required this.indexName,
    required this.value,
  });

  final int documentId;
  final String indexName;
  final WireIndexValue value;

  @override
  bool operator ==(Object other) =>
      other is WireIndexEntry &&
      other.documentId == documentId &&
      other.indexName == indexName &&
      other.value == value;

  @override
  int get hashCode => Object.hash(documentId, indexName, value);
}

sealed class WireQuerySource {
  const WireQuerySource({required this.dedupe});

  const factory WireQuerySource.all({bool dedupe}) = WireQueryAllSource;

  const factory WireQuerySource.indexEqual({
    required String indexName,
    required WireIndexValue value,
    bool dedupe,
  }) = WireQueryIndexEqualSource;

  const factory WireQuerySource.indexRange({
    required String indexName,
    required WireIndexValue? lower,
    required WireIndexValue? upper,
    bool dedupe,
  }) = WireQueryIndexRangeSource;

  final bool dedupe;
}

final class WireQueryAllSource extends WireQuerySource {
  const WireQueryAllSource({bool dedupe = false}) : super(dedupe: dedupe);

  @override
  bool operator ==(Object other) =>
      other is WireQueryAllSource && other.dedupe == dedupe;

  @override
  int get hashCode => Object.hash(WireQueryAllSource, dedupe);
}

final class WireQueryIndexEqualSource extends WireQuerySource {
  const WireQueryIndexEqualSource({
    required this.indexName,
    required this.value,
    bool dedupe = false,
  }) : super(dedupe: dedupe);

  final String indexName;
  final WireIndexValue value;

  @override
  bool operator ==(Object other) =>
      other is WireQueryIndexEqualSource &&
      other.indexName == indexName &&
      other.value == value &&
      other.dedupe == dedupe;

  @override
  int get hashCode =>
      Object.hash(WireQueryIndexEqualSource, indexName, value, dedupe);
}

final class WireQueryIndexRangeSource extends WireQuerySource {
  const WireQueryIndexRangeSource({
    required this.indexName,
    required this.lower,
    required this.upper,
    bool dedupe = false,
  }) : super(dedupe: dedupe);

  final String indexName;
  final WireIndexValue? lower;
  final WireIndexValue? upper;

  @override
  bool operator ==(Object other) =>
      other is WireQueryIndexRangeSource &&
      other.indexName == indexName &&
      other.lower == lower &&
      other.upper == upper &&
      other.dedupe == dedupe;

  @override
  int get hashCode =>
      Object.hash(WireQueryIndexRangeSource, indexName, lower, upper, dedupe);
}

final class WireQuerySort {
  const WireQuerySort({required this.field, required this.ascending});

  final String field;
  final bool ascending;

  @override
  bool operator ==(Object other) =>
      other is WireQuerySort &&
      other.field == field &&
      other.ascending == ascending;

  @override
  int get hashCode => Object.hash(field, ascending);
}

final class WireQueryPlan {
  const WireQueryPlan({
    required this.source,
    required this.filter,
    required this.sorts,
    required this.distinctFields,
    required this.offset,
    required this.limit,
  });

  final WireQuerySource source;
  final Uint8List? filter;
  final List<WireQuerySort> sorts;
  final List<String> distinctFields;
  final int offset;
  final int? limit;

  @override
  bool operator ==(Object other) =>
      other is WireQueryPlan &&
      other.source == source &&
      _nullableBytesEqual(other.filter, filter) &&
      listEquals(other.sorts, sorts) &&
      listEquals(other.distinctFields, distinctFields) &&
      other.offset == offset &&
      other.limit == limit;

  @override
  int get hashCode => Object.hash(
    source,
    filter == null ? null : Object.hashAll(filter!),
    Object.hashAll(sorts),
    Object.hashAll(distinctFields),
    offset,
    limit,
  );
}

final class WireChangeSet {
  const WireChangeSet({
    required this.collection,
    required this.revision,
    required this.documentIds,
  });

  final String collection;
  final int revision;
  final List<int> documentIds;

  @override
  bool operator ==(Object other) =>
      other is WireChangeSet &&
      other.collection == collection &&
      other.revision == revision &&
      listEquals(other.documentIds, documentIds);

  @override
  int get hashCode =>
      Object.hash(collection, revision, Object.hashAll(documentIds));
}

Uint8List encodeIdList(List<int> ids) {
  final writer = CindelWireWriter();
  writer.writeLength(ids.length);
  for (final id in ids) {
    writer.writeUint64(id);
  }
  return writer.finish();
}

List<int> decodeIdList(Uint8List bytes) {
  final reader = CindelWireReader(bytes);
  final count = reader.readLength();
  final ids = <int>[];
  for (var i = 0; i < count; i++) {
    ids.add(reader.readUint64());
  }
  reader.finish();
  return ids;
}

Uint8List encodeIndexValue(WireIndexValue value) {
  final writer = CindelWireWriter();
  writer.writeIndexValue(value);
  return writer.finish();
}

WireIndexValue decodeIndexValue(Uint8List bytes) {
  final reader = CindelWireReader(bytes);
  final value = reader.readIndexValue();
  reader.finish();
  return value;
}

Uint8List encodeScalar(WireScalar value) {
  final writer = CindelWireWriter();
  writer.writeScalar(value);
  return writer.finish();
}

WireScalar decodeScalar(Uint8List bytes) {
  final reader = CindelWireReader(bytes);
  final value = reader.readScalar();
  reader.finish();
  return value;
}

Uint8List encodeFilter(WireFilter filter) {
  final writer = CindelWireWriter();
  writer.writeFilter(filter);
  return writer.finish();
}

WireFilter decodeFilter(Uint8List bytes) {
  final reader = CindelWireReader(bytes);
  final filter = reader.readFilter();
  reader.finish();
  return filter;
}

Uint8List encodeDocumentWriteBatch(List<WireDocumentWrite> documents) {
  final writer = CindelWireWriter();
  writer.writeLength(documents.length);
  for (final document in documents) {
    writer.writeUint64(document.id);
    writer.writeBytes(document.bytes);
  }
  return writer.finish();
}

List<WireDocumentWrite> decodeDocumentWriteBatch(Uint8List bytes) {
  final reader = CindelWireReader(bytes);
  final count = reader.readLength();
  final documents = <WireDocumentWrite>[];
  for (var i = 0; i < count; i++) {
    documents.add(
      WireDocumentWrite(id: reader.readUint64(), bytes: reader.readBytes()),
    );
  }
  reader.finish();
  return documents;
}

Uint8List encodeIndexedDocumentWriteBatch(
  List<WireIndexedDocumentWrite> documents,
) {
  final writer = CindelWireWriter();
  writer.writeLength(documents.length);
  for (final document in documents) {
    writer.writeUint64(document.id);
    writer.writeBytes(document.bytes);
    writer.writeLength(document.indexes.length);
    for (final index in document.indexes) {
      writer.writeString(index.indexName);
      writer.writeIndexValue(index.value);
    }
  }
  return writer.finish();
}

List<WireIndexedDocumentWrite> decodeIndexedDocumentWriteBatch(
  Uint8List bytes,
) {
  final reader = CindelWireReader(bytes);
  final count = reader.readLength();
  final documents = <WireIndexedDocumentWrite>[];
  for (var i = 0; i < count; i++) {
    final id = reader.readUint64();
    final bytes = reader.readBytes();
    final indexCount = reader.readLength();
    final indexes = <WireIndexEntry>[];
    for (var index = 0; index < indexCount; index++) {
      indexes.add(
        WireIndexEntry(
          documentId: id,
          indexName: reader.readString(),
          value: reader.readIndexValue(),
        ),
      );
    }
    documents.add(
      WireIndexedDocumentWrite(id: id, bytes: bytes, indexes: indexes),
    );
  }
  reader.finish();
  return documents;
}

Uint8List encodeProjectionRows(WireProjectionRows rows) {
  final expectedCells = rows.rowCount * rows.columnCount;
  if (rows.cells.length != expectedCells) {
    throw const FormatException(
      'projection cells do not match rowCount * columnCount',
    );
  }
  final writer = CindelWireWriter();
  writer.writeUint32(rows.rowCount);
  writer.writeUint32(rows.columnCount);
  for (final cell in rows.cells) {
    writer.writeValue(cell);
  }
  return writer.finish();
}

WireProjectionRows decodeProjectionRows(Uint8List bytes) {
  final reader = CindelWireReader(bytes);
  final rowCount = reader.readUint32();
  final columnCount = reader.readUint32();
  final cellCount = rowCount * columnCount;
  final cells = <WireValue>[];
  for (var i = 0; i < cellCount; i++) {
    cells.add(reader.readValue());
  }
  reader.finish();
  return WireProjectionRows(
    rowCount: rowCount,
    columnCount: columnCount,
    cells: cells,
  );
}

Uint8List encodeFieldUpdates(Map<String, WireValue> updates) {
  final entries = updates.entries.toList(growable: false)
    ..sort((left, right) => left.key.compareTo(right.key));
  final writer = CindelWireWriter();
  writer.writeLength(entries.length);
  for (final entry in entries) {
    writer.writeString(entry.key);
    writer.writeValue(entry.value);
  }
  return writer.finish();
}

Uint8List encodeSchemaManifest(WireSchemaManifest manifest) {
  final writer = CindelWireWriter();
  writer.writeUint32(manifest.version);
  writer.writeLength(manifest.collections.length);
  for (final collection in manifest.collections) {
    writer.writeString(collection.name);
    writer.writeString(collection.idField);
    writer.writeLength(collection.fields.length);
    for (final field in collection.fields) {
      writer.writeString(field.name);
      writer.writeString(field.typeName);
      writer.writeString(field.binaryType);
      writer.writeString(field.indexType);
      writer.writeBool(field.isId);
      writer.writeBool(field.isIndexed);
      writer.writeBool(field.isUnique);
      writer.writeBool(field.isNullable);
      writer.writeBool(field.caseSensitive);
    }
    writer.writeLength(collection.indexes.length);
    for (final index in collection.indexes) {
      writer.writeString(index.name);
      writer.writeLength(index.fields.length);
      for (final field in index.fields) {
        writer.writeString(field);
      }
      writer.writeBool(index.isUnique);
      writer.writeBool(index.caseSensitive);
    }
  }
  return writer.finish();
}

WireSchemaManifest decodeSchemaManifest(Uint8List bytes) {
  final reader = CindelWireReader(bytes);
  final version = reader.readUint32();
  final collectionCount = reader.readLength();
  final collections = <WireCollectionSchema>[];
  for (var c = 0; c < collectionCount; c++) {
    final name = reader.readString();
    final idField = reader.readString();
    final fieldCount = reader.readLength();
    final fields = <WireFieldSchema>[];
    for (var f = 0; f < fieldCount; f++) {
      fields.add(
        WireFieldSchema(
          name: reader.readString(),
          typeName: reader.readString(),
          binaryType: reader.readString(),
          indexType: reader.readString(),
          isId: reader.readBool(),
          isIndexed: reader.readBool(),
          isUnique: reader.readBool(),
          isNullable: reader.readBool(),
          caseSensitive: reader.readBool(),
        ),
      );
    }
    final indexCount = reader.readLength();
    final indexes = <WireIndexSchema>[];
    for (var i = 0; i < indexCount; i++) {
      final indexName = reader.readString();
      final indexFieldCount = reader.readLength();
      final indexFields = <String>[];
      for (var f = 0; f < indexFieldCount; f++) {
        indexFields.add(reader.readString());
      }
      indexes.add(
        WireIndexSchema(
          name: indexName,
          fields: indexFields,
          isUnique: reader.readBool(),
          caseSensitive: reader.readBool(),
        ),
      );
    }
    collections.add(
      WireCollectionSchema(
        name: name,
        idField: idField,
        fields: fields,
        indexes: indexes,
      ),
    );
  }
  reader.finish();
  return WireSchemaManifest(version: version, collections: collections);
}

Uint8List encodeIndexEntryList(List<WireIndexEntry> entries) {
  final writer = CindelWireWriter();
  writer.writeLength(entries.length);
  for (final entry in entries) {
    writer.writeUint64(entry.documentId);
    writer.writeString(entry.indexName);
    writer.writeIndexValue(entry.value);
  }
  return writer.finish();
}

List<WireIndexEntry> decodeIndexEntryList(Uint8List bytes) {
  final reader = CindelWireReader(bytes);
  final count = reader.readLength();
  final entries = <WireIndexEntry>[];
  for (var i = 0; i < count; i++) {
    entries.add(
      WireIndexEntry(
        documentId: reader.readUint64(),
        indexName: reader.readString(),
        value: reader.readIndexValue(),
      ),
    );
  }
  reader.finish();
  return entries;
}

Uint8List encodeQueryPlan(WireQueryPlan plan) {
  final writer = CindelWireWriter();
  writer.writeQuerySource(plan.source);
  writer.writeBool(plan.filter != null);
  if (plan.filter != null) {
    writer.writeBytes(plan.filter!);
  }
  writer.writeLength(plan.sorts.length);
  for (final sort in plan.sorts) {
    writer.writeString(sort.field);
    writer.writeBool(sort.ascending);
  }
  writer.writeLength(plan.distinctFields.length);
  for (final field in plan.distinctFields) {
    writer.writeString(field);
  }
  writer.writeUint32(plan.offset);
  writer.writeBool(plan.limit != null);
  if (plan.limit != null) {
    writer.writeUint32(plan.limit!);
  }
  return writer.finish();
}

WireQueryPlan decodeQueryPlan(Uint8List bytes) {
  final reader = CindelWireReader(bytes);
  final source = reader.readQuerySource();
  final hasFilter = reader.readBool();
  final filter = hasFilter ? reader.readBytes() : null;
  final sorts = <WireQuerySort>[];
  for (var i = 0, count = reader.readLength(); i < count; i++) {
    sorts.add(
      WireQuerySort(field: reader.readString(), ascending: reader.readBool()),
    );
  }
  final distinctFields = <String>[];
  for (var i = 0, count = reader.readLength(); i < count; i++) {
    distinctFields.add(reader.readString());
  }
  final offset = reader.readUint32();
  final hasLimit = reader.readBool();
  final limit = hasLimit ? reader.readUint32() : null;
  reader.finish();
  return WireQueryPlan(
    source: source,
    filter: filter,
    sorts: sorts,
    distinctFields: distinctFields,
    offset: offset,
    limit: limit,
  );
}

Uint8List encodeChangeSetList(List<WireChangeSet> changes) {
  final writer = CindelWireWriter();
  writer.writeLength(changes.length);
  for (final change in changes) {
    writer.writeString(change.collection);
    writer.writeUint64(change.revision);
    writer.writeLength(change.documentIds.length);
    for (final id in change.documentIds) {
      writer.writeUint64(id);
    }
  }
  return writer.finish();
}

List<WireChangeSet> decodeChangeSetList(Uint8List bytes) {
  final reader = CindelWireReader(bytes);
  final count = reader.readLength();
  final changes = <WireChangeSet>[];
  for (var i = 0; i < count; i++) {
    final collection = reader.readString();
    final revision = reader.readUint64();
    final idCount = reader.readLength();
    final ids = <int>[];
    for (var idIndex = 0; idIndex < idCount; idIndex++) {
      ids.add(reader.readUint64());
    }
    changes.add(
      WireChangeSet(
        collection: collection,
        revision: revision,
        documentIds: ids,
      ),
    );
  }
  reader.finish();
  return changes;
}

final class CindelWireWriter {
  CindelWireWriter();

  final BytesBuilder _bytes = BytesBuilder(copy: false);

  Uint8List finish() => _bytes.takeBytes();

  void writeUint8(int value) {
    _bytes.addByte(value & 0xff);
  }

  void writeUint32(int value) {
    if (value < 0 || value > 0xffffffff) {
      throw RangeError.range(value, 0, 0xffffffff, 'value');
    }
    final data = ByteData(4)..setUint32(0, value, Endian.little);
    _bytes.add(data.buffer.asUint8List());
  }

  void writeUint64(int value) {
    if (value < 0) {
      throw RangeError.range(value, 0, null, 'value');
    }
    final data = ByteData(8)..setUint64(0, value, Endian.little);
    _bytes.add(data.buffer.asUint8List());
  }

  void writeInt64(int value) {
    final data = ByteData(8)..setInt64(0, value, Endian.little);
    _bytes.add(data.buffer.asUint8List());
  }

  void writeFloat64(double value) {
    final normalized = value == 0.0 ? 0.0 : value;
    final data = ByteData(8)..setFloat64(0, normalized, Endian.little);
    _bytes.add(data.buffer.asUint8List());
  }

  void writeBool(bool value) {
    writeUint8(value ? 1 : 0);
  }

  void writeLength(int length) {
    writeUint32(length);
  }

  void writeBytes(Uint8List bytes) {
    writeLength(bytes.length);
    _bytes.add(bytes);
  }

  void writeString(String value) {
    writeBytes(Uint8List.fromList(utf8.encode(value)));
  }

  void writeIndexValue(WireIndexValue value) {
    switch (value) {
      case WireIndexNull():
        writeUint8(wireTagNull);
      case WireIndexBool(:final value):
        writeUint8(wireTagBool);
        writeBool(value);
      case WireIndexInt(:final value):
        writeUint8(wireTagInt);
        writeInt64(value);
      case WireIndexDouble(:final value):
        writeUint8(wireTagDouble);
        writeFloat64(value);
      case WireIndexString(:final value):
        writeUint8(wireTagString);
        writeString(value);
      case WireIndexList(:final values):
        writeUint8(wireTagList);
        writeLength(values.length);
        for (final value in values) {
          writeIndexValue(value);
        }
    }
  }

  void writeScalar(WireScalar value) {
    switch (value) {
      case WireScalarNull():
        writeUint8(wireTagNull);
      case WireScalarBool(:final value):
        writeUint8(wireTagBool);
        writeBool(value);
      case WireScalarInt(:final value):
        writeUint8(wireTagInt);
        writeInt64(value);
      case WireScalarDouble(:final value):
        writeUint8(wireTagDouble);
        writeFloat64(value);
      case WireScalarString(:final value):
        writeUint8(wireTagString);
        writeString(value);
    }
  }

  void writeValue(WireValue value) {
    switch (value) {
      case WireNullValue():
        writeUint8(wireTagNull);
      case WireBoolValue(:final value):
        writeUint8(wireTagBool);
        writeBool(value);
      case WireIntValue(:final value):
        writeUint8(wireTagInt);
        writeInt64(value);
      case WireDoubleValue(:final value):
        writeUint8(wireTagDouble);
        writeFloat64(value);
      case WireStringValue(:final value):
        writeUint8(wireTagString);
        writeString(value);
      case WireListValue(:final values):
        writeUint8(wireTagList);
        writeLength(values.length);
        for (final value in values) {
          writeValue(value);
        }
      case WireObjectValue(:final fields):
        writeUint8(wireTagObject);
        writeLength(fields.length);
        for (final field in fields) {
          writeString(field.name);
          writeValue(field.value);
        }
    }
  }

  void writeFilter(WireFilter filter) {
    switch (filter) {
      case WireFieldFilter(:final field, :final operation, :final value):
        writeUint8(wireFilterTagField);
        writeString(field);
        writeUint8(_filterOperationTag(operation));
        writeValue(value);
      case WireAllFilter(:final predicates):
        writeUint8(wireFilterTagAll);
        writeLength(predicates.length);
        for (final predicate in predicates) {
          writeFilter(predicate);
        }
      case WireAnyFilter(:final predicates):
        writeUint8(wireFilterTagAny);
        writeLength(predicates.length);
        for (final predicate in predicates) {
          writeFilter(predicate);
        }
      case WireNotFilter(:final predicate):
        writeUint8(wireFilterTagNot);
        writeFilter(predicate);
    }
  }

  void writeQuerySource(WireQuerySource source) {
    switch (source) {
      case WireQueryAllSource(:final dedupe):
        writeUint8(wireQuerySourceAll);
        writeBool(dedupe);
      case WireQueryIndexEqualSource(
        :final indexName,
        :final value,
        :final dedupe,
      ):
        writeUint8(wireQuerySourceIndexEqual);
        writeBool(dedupe);
        writeString(indexName);
        writeIndexValue(value);
      case WireQueryIndexRangeSource(
        :final indexName,
        :final lower,
        :final upper,
        :final dedupe,
      ):
        writeUint8(wireQuerySourceIndexRange);
        writeBool(dedupe);
        writeString(indexName);
        writeBool(lower != null);
        if (lower != null) {
          writeIndexValue(lower);
        }
        writeBool(upper != null);
        if (upper != null) {
          writeIndexValue(upper);
        }
    }
  }
}

final class CindelWireReader {
  CindelWireReader(this._bytes);

  final Uint8List _bytes;
  int _offset = 0;

  void finish() {
    if (_offset != _bytes.length) {
      throw const FormatException('wire payload has trailing bytes');
    }
  }

  Uint8List readExact(int length) {
    final end = _offset + length;
    if (end > _bytes.length) {
      throw const FormatException('wire payload is truncated');
    }
    final result = Uint8List.sublistView(_bytes, _offset, end);
    _offset = end;
    return result;
  }

  int readUint8() => readExact(1)[0];

  int readUint32() =>
      ByteData.sublistView(readExact(4)).getUint32(0, Endian.little);

  int readUint64() =>
      ByteData.sublistView(readExact(8)).getUint64(0, Endian.little);

  int readInt64() =>
      ByteData.sublistView(readExact(8)).getInt64(0, Endian.little);

  double readFloat64() =>
      ByteData.sublistView(readExact(8)).getFloat64(0, Endian.little);

  bool readBool() {
    return switch (readUint8()) {
      0 => false,
      1 => true,
      _ => throw const FormatException('wire bool tag must be 0 or 1'),
    };
  }

  int readLength() => readUint32();

  Uint8List readBytes() => readExact(readLength());

  String readString() => utf8.decode(readBytes(), allowMalformed: false);

  WireIndexValue readIndexValue() {
    return switch (readUint8()) {
      wireTagNull => const WireIndexValue.nullValue(),
      wireTagBool => WireIndexValue.bool(readBool()),
      wireTagInt => WireIndexValue.int(readInt64()),
      wireTagDouble => WireIndexValue.double(readFloat64()),
      wireTagString => WireIndexValue.string(readString()),
      wireTagList => WireIndexValue.list([
        for (var i = 0, count = readLength(); i < count; i++) readIndexValue(),
      ]),
      final tag => throw FormatException('unknown wire index value tag $tag'),
    };
  }

  WireScalar readScalar() {
    return switch (readUint8()) {
      wireTagNull => const WireScalar.nullValue(),
      wireTagBool => WireScalar.bool(readBool()),
      wireTagInt => WireScalar.int(readInt64()),
      wireTagDouble => WireScalar.double(readFloat64()),
      wireTagString => WireScalar.string(readString()),
      final tag => throw FormatException('unknown wire scalar tag $tag'),
    };
  }

  WireValue readValue() {
    return switch (readUint8()) {
      wireTagNull => const WireValue.nullValue(),
      wireTagBool => WireValue.bool(readBool()),
      wireTagInt => WireValue.int(readInt64()),
      wireTagDouble => WireValue.double(readFloat64()),
      wireTagString => WireValue.string(readString()),
      wireTagList => WireValue.list([
        for (var i = 0, count = readLength(); i < count; i++) readValue(),
      ]),
      wireTagObject => WireValue.object([
        for (var i = 0, count = readLength(); i < count; i++)
          WireObjectEntry(readString(), readValue()),
      ]),
      final tag => throw FormatException('unknown wire value tag $tag'),
    };
  }

  WireFilter readFilter() {
    return switch (readUint8()) {
      wireFilterTagField => WireFilter.field(
        field: readString(),
        operation: _readFilterOperation(),
        value: readValue(),
      ),
      wireFilterTagAll => WireFilter.all([
        for (var i = 0, count = readLength(); i < count; i++) readFilter(),
      ]),
      wireFilterTagAny => WireFilter.any([
        for (var i = 0, count = readLength(); i < count; i++) readFilter(),
      ]),
      wireFilterTagNot => WireFilter.not(readFilter()),
      final tag => throw FormatException('unknown wire filter tag $tag'),
    };
  }

  WireQuerySource readQuerySource() {
    final tag = readUint8();
    final dedupe = readBool();
    return switch (tag) {
      wireQuerySourceAll => WireQuerySource.all(dedupe: dedupe),
      wireQuerySourceIndexEqual => WireQuerySource.indexEqual(
        indexName: readString(),
        value: readIndexValue(),
        dedupe: dedupe,
      ),
      wireQuerySourceIndexRange => WireQuerySource.indexRange(
        indexName: readString(),
        lower: readBool() ? readIndexValue() : null,
        upper: readBool() ? readIndexValue() : null,
        dedupe: dedupe,
      ),
      _ => throw FormatException('unknown wire query source tag $tag'),
    };
  }

  WireFilterOperation _readFilterOperation() {
    return switch (readUint8()) {
      wireFilterOpEqual => WireFilterOperation.equal,
      wireFilterOpLessThan => WireFilterOperation.lessThan,
      wireFilterOpLessThanOrEqual => WireFilterOperation.lessThanOrEqual,
      wireFilterOpGreaterThan => WireFilterOperation.greaterThan,
      wireFilterOpGreaterThanOrEqual => WireFilterOperation.greaterThanOrEqual,
      wireFilterOpContains => WireFilterOperation.contains,
      wireFilterOpStartsWith => WireFilterOperation.startsWith,
      wireFilterOpEndsWith => WireFilterOperation.endsWith,
      wireFilterOpIsNull => WireFilterOperation.isNull,
      final tag => throw FormatException('unknown wire filter operation $tag'),
    };
  }
}

int _filterOperationTag(WireFilterOperation operation) {
  return switch (operation) {
    WireFilterOperation.equal => wireFilterOpEqual,
    WireFilterOperation.lessThan => wireFilterOpLessThan,
    WireFilterOperation.lessThanOrEqual => wireFilterOpLessThanOrEqual,
    WireFilterOperation.greaterThan => wireFilterOpGreaterThan,
    WireFilterOperation.greaterThanOrEqual => wireFilterOpGreaterThanOrEqual,
    WireFilterOperation.contains => wireFilterOpContains,
    WireFilterOperation.startsWith => wireFilterOpStartsWith,
    WireFilterOperation.endsWith => wireFilterOpEndsWith,
    WireFilterOperation.isNull => wireFilterOpIsNull,
  };
}

bool listEquals<T>(List<T> left, List<T> right) {
  if (identical(left, right)) {
    return true;
  }
  if (left.length != right.length) {
    return false;
  }
  for (var i = 0; i < left.length; i++) {
    if (left[i] != right[i]) {
      return false;
    }
  }
  return true;
}

bool _nullableBytesEqual(Uint8List? left, Uint8List? right) {
  if (left == null || right == null) {
    return left == right;
  }
  return listEquals(left, right);
}
