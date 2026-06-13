import 'dart:convert';
import 'dart:typed_data';

import '../schema.dart';

/// CindelWireV1 value tags shared by Dart and Rust.
///
/// These numeric values are part of the native ABI. Do not reorder or reuse a
/// tag without updating the Rust codec and its byte-for-byte fixture tests.
const int wireTagNull = 0;
const int wireTagBool = 1;
const int wireTagInt = 2;
const int wireTagDouble = 3;
const int wireTagString = 4;
const int wireTagList = 5;
const int wireTagObject = 6;

/// Filter AST tags used by native query filtering.
const int wireFilterTagField = 1;
const int wireFilterTagAll = 2;
const int wireFilterTagAny = 3;
const int wireFilterTagNot = 4;

/// Field filter operation tags used by native SQLite/MDBX query execution.
const int wireFilterOpEqual = 1;
const int wireFilterOpLessThan = 2;
const int wireFilterOpLessThanOrEqual = 3;
const int wireFilterOpGreaterThan = 4;
const int wireFilterOpGreaterThanOrEqual = 5;
const int wireFilterOpContains = 6;
const int wireFilterOpStartsWith = 7;
const int wireFilterOpEndsWith = 8;
const int wireFilterOpIsNull = 9;
const int wireFilterOpLengthEqual = 10;
const int wireFilterOpLengthLessThan = 11;
const int wireFilterOpLengthLessThanOrEqual = 12;
const int wireFilterOpLengthGreaterThan = 13;
const int wireFilterOpLengthGreaterThanOrEqual = 14;

/// Query source tags for the compact native query-plan format.
const int wireQuerySourceAll = 1;
const int wireQuerySourceIndexEqual = 2;
const int wireQuerySourceIndexRange = 3;

const int _minInt64 = -0x8000000000000000;
const int _maxInt64 = 0x7fffffffffffffff;
const int _maxUint64 = _maxInt64;

/// Value stored inside a native index entry.
///
/// Index values are narrower than document values because indexes only support
/// scalar values and nested composite-index lists. Object values belong to
/// [WireValue], not to index entries.
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

/// Explicit null index value.
final class WireIndexNull extends WireIndexValue {
  const WireIndexNull();

  @override
  bool operator ==(Object other) => other is WireIndexNull;

  @override
  int get hashCode => 0;
}

/// Boolean index value.
final class WireIndexBool extends WireIndexValue {
  const WireIndexBool(this.value);

  final bool value;

  @override
  bool operator ==(Object other) =>
      other is WireIndexBool && other.value == value;

  @override
  int get hashCode => Object.hash(WireIndexBool, value);
}

/// Signed 64-bit integer index value.
final class WireIndexInt extends WireIndexValue {
  const WireIndexInt(this.value);

  final int value;

  @override
  bool operator ==(Object other) =>
      other is WireIndexInt && other.value == value;

  @override
  int get hashCode => Object.hash(WireIndexInt, value);
}

/// 64-bit floating point index value.
final class WireIndexDouble extends WireIndexValue {
  const WireIndexDouble(this.value);

  final double value;

  @override
  bool operator ==(Object other) =>
      other is WireIndexDouble && other.value == value;

  @override
  int get hashCode => Object.hash(WireIndexDouble, value);
}

/// UTF-8 string index value.
final class WireIndexString extends WireIndexValue {
  const WireIndexString(this.value);

  final String value;

  @override
  bool operator ==(Object other) =>
      other is WireIndexString && other.value == value;

  @override
  int get hashCode => Object.hash(WireIndexString, value);
}

/// Composite index value made from ordered nested index values.
final class WireIndexList extends WireIndexValue {
  const WireIndexList(this.values);

  final List<WireIndexValue> values;

  @override
  bool operator ==(Object other) =>
      other is WireIndexList && listEquals(other.values, values);

  @override
  int get hashCode => Object.hashAll(values);
}

/// Scalar value returned by native aggregate and count operations.
///
/// Scalars intentionally exclude lists and objects so aggregate payloads stay
/// simple and unambiguous.
sealed class WireScalar {
  const WireScalar();

  const factory WireScalar.nullValue() = WireScalarNull;
  const factory WireScalar.bool(bool value) = WireScalarBool;
  const factory WireScalar.int(int value) = WireScalarInt;
  const factory WireScalar.double(double value) = WireScalarDouble;
  const factory WireScalar.string(String value) = WireScalarString;
}

/// Explicit null scalar result.
final class WireScalarNull extends WireScalar {
  const WireScalarNull();

  @override
  bool operator ==(Object other) => other is WireScalarNull;

  @override
  int get hashCode => 0;
}

/// Boolean scalar result.
final class WireScalarBool extends WireScalar {
  const WireScalarBool(this.value);

  final bool value;

  @override
  bool operator ==(Object other) =>
      other is WireScalarBool && other.value == value;

  @override
  int get hashCode => Object.hash(WireScalarBool, value);
}

/// Signed 64-bit integer scalar result.
final class WireScalarInt extends WireScalar {
  const WireScalarInt(this.value);

  final int value;

  @override
  bool operator ==(Object other) =>
      other is WireScalarInt && other.value == value;

  @override
  int get hashCode => Object.hash(WireScalarInt, value);
}

/// 64-bit floating point scalar result.
final class WireScalarDouble extends WireScalar {
  const WireScalarDouble(this.value);

  final double value;

  @override
  bool operator ==(Object other) =>
      other is WireScalarDouble && other.value == value;

  @override
  int get hashCode => Object.hash(WireScalarDouble, value);
}

/// UTF-8 string scalar result.
final class WireScalarString extends WireScalar {
  const WireScalarString(this.value);

  final String value;

  @override
  bool operator ==(Object other) =>
      other is WireScalarString && other.value == value;

  @override
  int get hashCode => Object.hash(WireScalarString, value);
}

/// Generic projected or update value exchanged with native query code.
///
/// This is the broadest CindelWireV1 value family and can represent nested
/// lists and objects. Stored documents themselves still use the document binary
/// format; [WireValue] is for query filters, projections, and update payloads.
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

  /// Field name as persisted in the native payload.
  final String name;

  /// Field value encoded under [name].
  final WireValue value;

  @override
  bool operator ==(Object other) =>
      other is WireObjectEntry && other.name == name && other.value == value;

  @override
  int get hashCode => Object.hash(name, value);
}

/// Native filter AST sent from Dart query predicates to Rust storage engines.
///
/// Field names must be persisted/native names, because Rust evaluates filters
/// against the stored schema and index metadata.
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

/// Operation applied by [WireFieldFilter].
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
  lengthEqual,
  lengthLessThan,
  lengthLessThanOrEqual,
  lengthGreaterThan,
  lengthGreaterThanOrEqual,
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

/// Stored document bytes queued for a native batch write.
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

/// Stored document bytes plus the index entries generated for that document.
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

/// Value written into the SQLite-native generated document table.
///
/// Strings, enum names, list payloads, and embedded object payloads are carried
/// as bytes because generated document writers already know the compact field
/// encoding for each persisted field.
sealed class WireNativeDocumentValue {
  const WireNativeDocumentValue();

  const factory WireNativeDocumentValue.nullValue() = WireNativeDocumentNull;
  const factory WireNativeDocumentValue.bool(bool value) =
      WireNativeDocumentBool;
  const factory WireNativeDocumentValue.int(int value) = WireNativeDocumentInt;
  const factory WireNativeDocumentValue.double(double value) =
      WireNativeDocumentDouble;
  const factory WireNativeDocumentValue.bytes(Uint8List value) =
      WireNativeDocumentBytes;
}

/// Null native document field value.
final class WireNativeDocumentNull extends WireNativeDocumentValue {
  const WireNativeDocumentNull();

  @override
  bool operator ==(Object other) => other is WireNativeDocumentNull;

  @override
  int get hashCode => 0;
}

/// Boolean native document field value.
final class WireNativeDocumentBool extends WireNativeDocumentValue {
  const WireNativeDocumentBool(this.value);

  final bool value;

  @override
  bool operator ==(Object other) =>
      other is WireNativeDocumentBool && other.value == value;

  @override
  int get hashCode => Object.hash(WireNativeDocumentBool, value);
}

/// Signed 64-bit integer native document field value.
final class WireNativeDocumentInt extends WireNativeDocumentValue {
  const WireNativeDocumentInt(this.value);

  final int value;

  @override
  bool operator ==(Object other) =>
      other is WireNativeDocumentInt && other.value == value;

  @override
  int get hashCode => Object.hash(WireNativeDocumentInt, value);
}

/// 64-bit floating point native document field value.
final class WireNativeDocumentDouble extends WireNativeDocumentValue {
  const WireNativeDocumentDouble(this.value);

  final double value;

  @override
  bool operator ==(Object other) =>
      other is WireNativeDocumentDouble && other.value == value;

  @override
  int get hashCode => Object.hash(WireNativeDocumentDouble, value);
}

/// Byte payload native document field value.
final class WireNativeDocumentBytes extends WireNativeDocumentValue {
  const WireNativeDocumentBytes(this.value);

  final Uint8List value;

  @override
  bool operator ==(Object other) =>
      other is WireNativeDocumentBytes && listEquals(other.value, value);

  @override
  int get hashCode =>
      Object.hash(WireNativeDocumentBytes, Object.hashAll(value));
}

/// SQLite-native generated document row queued for a batch write.
final class WireNativeDocumentWrite {
  const WireNativeDocumentWrite({required this.id, required this.values});

  final int id;
  final List<WireNativeDocumentValue> values;

  @override
  bool operator ==(Object other) =>
      other is WireNativeDocumentWrite &&
      other.id == id &&
      listEquals(other.values, values);

  @override
  int get hashCode => Object.hash(id, Object.hashAll(values));
}

/// Writes one ordered SQLite-native generated document into a wire batch.
///
/// Generated serializers can use this writer to avoid constructing
/// [WireNativeDocumentWrite] and [WireNativeDocumentValue] objects for every
/// row. Fields must be written in the same order as the registered native
/// schema. This preserves the existing CindelWireV1 payload shape used by
/// [encodeNativeDocumentWriteBatch].
final class CindelNativeDocumentWireWriter
    implements CindelNativeStringListDocumentWriter {
  CindelNativeDocumentWireWriter._(this._writer, this._fieldCount);

  final _CindelGrowableWireWriter _writer;
  final int _fieldCount;
  int _nextFieldIndex = 0;

  void _beginDocument(int id) {
    _nextFieldIndex = 0;
    _writer.writeUint64(id);
    _writer.writeLength(_fieldCount);
  }

  void _finishDocument() {
    if (_nextFieldIndex != _fieldCount) {
      throw StateError(
        'native document wrote $_nextFieldIndex fields, expected $_fieldCount',
      );
    }
  }

  void _checkFieldIndex(int fieldIndex) {
    if (fieldIndex != _nextFieldIndex) {
      throw StateError(
        'native wire fields must be written in order; expected '
        '$_nextFieldIndex, got $fieldIndex',
      );
    }
    _nextFieldIndex += 1;
  }

  /// Writes a null value to [fieldIndex].
  @override
  void writeNull(int fieldIndex) {
    _checkFieldIndex(fieldIndex);
    _writer.writeUint8(wireTagNull);
  }

  /// Writes a boolean value to [fieldIndex].
  @override
  void writeBool(int fieldIndex, bool value) {
    _checkFieldIndex(fieldIndex);
    _writer.writeUint8(wireTagBool);
    _writer.writeBool(value);
  }

  /// Writes an integer value to [fieldIndex].
  @override
  void writeInt(int fieldIndex, int value) {
    _checkFieldIndex(fieldIndex);
    _writer.writeUint8(wireTagInt);
    _writer.writeInt64(value);
  }

  /// Writes a finite double value to [fieldIndex].
  @override
  void writeDouble(int fieldIndex, double value) {
    if (!value.isFinite) {
      throw const FormatException(
        'native document double values must be finite',
      );
    }
    _checkFieldIndex(fieldIndex);
    _writer.writeUint8(wireTagDouble);
    _writer.writeFloat64(value);
  }

  /// Writes raw native bytes to [fieldIndex].
  void writeBytes(int fieldIndex, Uint8List value) {
    _checkFieldIndex(fieldIndex);
    _writer.writeUint8(wireTagString);
    _writer.writeBytes(value);
  }

  /// Writes [value] as UTF-8 bytes to [fieldIndex].
  @override
  void writeString(int fieldIndex, String value) {
    _checkFieldIndex(fieldIndex);
    _writer.writeUint8(wireTagString);
    _writer.writeUtf8StringBytes(value);
  }

  /// Writes a JSON string-list payload to [fieldIndex].
  ///
  /// SQLite stores native list columns as JSON text for query support. This
  /// method writes the JSON payload directly into the wire buffer, escaping
  /// UTF-8 strings without allocating an intermediate JSON string.
  void writeStringListJson(int fieldIndex, List<String> values) {
    _checkFieldIndex(fieldIndex);
    _writer.writeUint8(wireTagString);
    _writer.writeJsonStringListBytes(values);
  }

  @override
  void writeStringList(int fieldIndex, List<String> value) {
    writeStringListJson(fieldIndex, value);
  }

  @override
  void writeObject(int fieldIndex, Map<String, Object?> value) {
    throw UnsupportedError(
      'Cindel native embedded object writes are not available yet.',
    );
  }

  @override
  void writeObjectList(int fieldIndex, List<Map<String, Object?>?> value) {
    throw UnsupportedError(
      'Cindel native embedded object-list writes are not available yet.',
    );
  }

  @override
  CindelNativeDocumentWriter beginList(int fieldIndex, int length) {
    throw UnsupportedError('Nested native list writers are not supported.');
  }

  @override
  void endList(CindelNativeDocumentWriter listWriter) {}
}

/// Callback used by [encodeNativeDocumentWriteBatchDirect].
typedef CindelWriteNativeWireDocument<T> =
    void Function(CindelNativeDocumentWireWriter writer, T object);

/// Tabular projection result returned by native query projection APIs.
///
/// [cells] is row-major and must contain exactly `rowCount * columnCount`
/// values. The encoder validates this because Rust and Dart both rely on the
/// dimensions to slice the flat cell list.
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

/// Schema manifest registered with the native database.
///
/// The manifest is part of migration compatibility. Collection and field names
/// here are the persisted names understood by the native validators.
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

/// Persisted schema for one collection.
final class WireCollectionSchema {
  const WireCollectionSchema({
    required this.name,
    required this.idField,
    required this.fields,
    required this.indexes,
  });

  final String name;

  /// Persisted id field name.
  final String idField;

  /// Persisted fields known to native storage.
  final List<WireFieldSchema> fields;

  /// Index definitions owned by this collection.
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
    required this.isReplace,
    required this.isNullable,
    required this.caseSensitive,
  });

  /// Persisted field name used by native compatibility checks and queries.
  final String name;

  /// Dart-level type name kept for diagnostics and schema comparison.
  final String typeName;

  /// Binary document field type used by the compact document codec.
  final String binaryType;

  /// Native index value family for this field.
  final String indexType;

  /// Whether this field is the collection id.
  final bool isId;

  /// Whether this field has a native index.
  final bool isIndexed;

  /// Whether the index enforces uniqueness.
  final bool isUnique;

  /// Whether the index replaces conflicting documents.
  final bool isReplace;

  /// Whether null values are accepted.
  final bool isNullable;

  /// Whether string comparison/indexing keeps case sensitivity.
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
      other.isReplace == isReplace &&
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
    isReplace,
    isNullable,
    caseSensitive,
  );
}

/// Persisted schema for a native index.
final class WireIndexSchema {
  const WireIndexSchema({
    required this.name,
    required this.fields,
    required this.isUnique,
    required this.isReplace,
    required this.caseSensitive,
  });

  /// Persisted index name.
  final String name;

  /// Ordered persisted field names that make up the index.
  final List<String> fields;

  /// Whether the index enforces uniqueness.
  final bool isUnique;

  /// Whether the index replaces conflicting documents.
  final bool isReplace;

  /// Whether string comparison/indexing keeps case sensitivity.
  final bool caseSensitive;

  @override
  bool operator ==(Object other) =>
      other is WireIndexSchema &&
      other.name == name &&
      listEquals(other.fields, fields) &&
      other.isUnique == isUnique &&
      other.isReplace == isReplace &&
      other.caseSensitive == caseSensitive;

  @override
  int get hashCode => Object.hash(
    name,
    Object.hashAll(fields),
    isUnique,
    isReplace,
    caseSensitive,
  );
}

/// One generated index value for a document.
final class WireIndexEntry {
  const WireIndexEntry({
    required this.documentId,
    required this.indexName,
    required this.value,
  });

  /// Document id that owns this index entry.
  final int documentId;

  /// Persisted index name.
  final String indexName;

  /// Encoded index key value.
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

/// Source stage for a native query plan.
///
/// Sources select the initial id stream before optional filter, sort, distinct,
/// offset, and limit stages are applied.
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

  /// Whether duplicate ids from this source should be removed by native code.
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

  /// Persisted index name used to seek the initial id stream.
  final String indexName;

  /// Exact index key to match.
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

  /// Persisted index name used to seek the initial id stream.
  final String indexName;

  /// Optional inclusive lower bound.
  final WireIndexValue? lower;

  /// Optional inclusive upper bound.
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

/// One native sort stage in a query plan.
final class WireQuerySort {
  const WireQuerySort({required this.field, required this.ascending});

  /// Persisted field name used for comparison.
  final String field;

  /// Sort direction. `false` means descending.
  final bool ascending;

  @override
  bool operator ==(Object other) =>
      other is WireQuerySort &&
      other.field == field &&
      other.ascending == ascending;

  @override
  int get hashCode => Object.hash(field, ascending);
}

/// Compact query plan executed by native storage engines.
///
/// Dart query builders encode the plan once, then Rust can use the same payload
/// for ids, documents, counts, projections, aggregates, deletes, or updates.
final class WireQueryPlan {
  const WireQueryPlan({
    required this.source,
    required this.filter,
    required this.sorts,
    required this.distinctFields,
    required this.offset,
    required this.limit,
  });

  /// Initial id source.
  final WireQuerySource source;

  /// Optional [WireFilter] payload encoded with [encodeFilter].
  final Uint8List? filter;

  /// Sort stages applied after filtering.
  final List<WireQuerySort> sorts;

  /// Persisted field names used for native distinct.
  final List<String> distinctFields;

  /// Number of matching rows to skip.
  final int offset;

  /// Optional maximum number of rows to return.
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

/// Native watcher change-set payload for one collection revision.
final class WireChangeSet {
  const WireChangeSet({
    required this.collection,
    required this.revision,
    required this.documentIds,
  });

  /// Collection name that changed.
  final String collection;

  /// Native collection revision after the change.
  final int revision;

  /// Changed document ids reported by native storage.
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

/// Encodes a native id-list payload.
///
/// The payload is a u32 count followed by that many little-endian u64 ids.
Uint8List encodeIdList(List<int> ids) {
  final writer = CindelWireWriter();
  writer.writeLength(ids.length);
  for (final id in ids) {
    writer.writeUint64(id);
  }
  return writer.finish();
}

/// Decodes a native id-list payload.
///
/// The payload is a u32 count followed by that many little-endian u64 ids.
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

/// Encodes an index key value used by index writes and index query sources.
Uint8List encodeIndexValue(WireIndexValue value) {
  final writer = CindelWireWriter();
  writer.writeIndexValue(value);
  return writer.finish();
}

/// Decodes an index key value.
WireIndexValue decodeIndexValue(Uint8List bytes) {
  final reader = CindelWireReader(bytes);
  final value = reader.readIndexValue();
  reader.finish();
  return value;
}

/// Encodes a scalar native query result.
Uint8List encodeScalar(WireScalar value) {
  final writer = CindelWireWriter();
  writer.writeScalar(value);
  return writer.finish();
}

/// Decodes a scalar native query result.
WireScalar decodeScalar(Uint8List bytes) {
  final reader = CindelWireReader(bytes);
  final value = reader.readScalar();
  reader.finish();
  return value;
}

/// Encodes a native filter AST.
Uint8List encodeFilter(WireFilter filter) {
  final writer = CindelWireWriter();
  writer.writeFilter(filter);
  return writer.finish();
}

/// Decodes a native filter AST.
WireFilter decodeFilter(Uint8List bytes) {
  final reader = CindelWireReader(bytes);
  final filter = reader.readFilter();
  reader.finish();
  return filter;
}

/// Encodes stored document bytes for batch writes.
Uint8List encodeDocumentWriteBatch(List<WireDocumentWrite> documents) {
  final writer = CindelWireWriter();
  writer.writeLength(documents.length);
  for (final document in documents) {
    writer.writeUint64(document.id);
    writer.writeBytes(document.bytes);
  }
  return writer.finish();
}

/// Decodes stored document bytes from a batch-write payload.
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

/// Encodes stored document bytes and generated index entries for batch writes.
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

/// Decodes stored document bytes and generated index entries.
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

/// Encodes ordered optional document bytes returned by Web get/getAll calls.
Uint8List encodeOptionalDocumentBatch(List<Uint8List?> documents) {
  final writer = CindelWireWriter();
  writer.writeLength(documents.length);
  for (final document in documents) {
    writer.writeBool(document != null);
    if (document != null) {
      writer.writeBytes(document);
    }
  }
  return writer.finish();
}

/// Decodes ordered optional document bytes returned by Web get/getAll calls.
List<Uint8List?> decodeOptionalDocumentBatch(Uint8List bytes) {
  final reader = CindelWireReader(bytes);
  final count = reader.readLength();
  final documents = <Uint8List?>[];
  for (var i = 0; i < count; i++) {
    documents.add(reader.readBool() ? reader.readBytes() : null);
  }
  reader.finish();
  return documents;
}

/// Encodes SQLite-native generated document rows for batch writes.
Uint8List encodeNativeDocumentWriteBatch(
  List<WireNativeDocumentWrite> documents,
) {
  final writer = CindelWireWriter();
  writer.writeLength(documents.length);
  for (final document in documents) {
    writer.writeUint64(document.id);
    writer.writeLength(document.values.length);
    for (final value in document.values) {
      writer.writeNativeDocumentValue(value);
    }
  }
  return writer.finish();
}

/// Encodes SQLite-native generated document rows without per-row wire objects.
///
/// [writeDocument] is called once per object with a
/// [CindelNativeDocumentWireWriter]. The callback must write exactly
/// [fieldCount] fields in schema order. The resulting bytes are the same
/// CindelWireV1 payload produced by [encodeNativeDocumentWriteBatch].
Uint8List encodeNativeDocumentWriteBatchDirect<T>({
  required List<int> ids,
  required List<T> objects,
  required int fieldCount,
  required CindelWriteNativeWireDocument<T> writeDocument,
}) {
  if (ids.length != objects.length) {
    throw ArgumentError.value(
      ids.length,
      'ids',
      'Must match the object count.',
    );
  }
  if (fieldCount < 0) {
    throw RangeError.range(fieldCount, 0, null, 'fieldCount');
  }

  final writer = _CindelGrowableWireWriter(
    4 + objects.length * (12 + fieldCount),
  );
  final documentWriter = CindelNativeDocumentWireWriter._(writer, fieldCount);
  writer.writeLength(objects.length);
  for (var i = 0; i < objects.length; i += 1) {
    documentWriter._beginDocument(ids[i]);
    writeDocument(documentWriter, objects[i]);
    documentWriter._finishDocument();
  }
  return writer.finish();
}

/// Decodes SQLite-native generated document rows from a batch payload.
List<WireNativeDocumentWrite> decodeNativeDocumentWriteBatch(Uint8List bytes) {
  final reader = CindelWireReader(bytes);
  final count = reader.readLength();
  final documents = <WireNativeDocumentWrite>[];
  for (var i = 0; i < count; i++) {
    final id = reader.readUint64();
    final valueCount = reader.readLength();
    final values = <WireNativeDocumentValue>[];
    for (var value = 0; value < valueCount; value++) {
      values.add(reader.readNativeDocumentValue());
    }
    documents.add(WireNativeDocumentWrite(id: id, values: values));
  }
  reader.finish();
  return documents;
}

/// Encodes native projection rows in row-major order.
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

/// Decodes native projection rows.
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

/// Encodes field updates for native query-plan update operations.
///
/// Entries are sorted by field name to keep the payload deterministic.
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

/// Encodes the schema manifest registered with native storage.
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
      writer.writeBool(field.isReplace);
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
      writer.writeBool(index.isReplace);
      writer.writeBool(index.caseSensitive);
    }
  }
  return writer.finish();
}

/// Decodes a schema manifest returned or validated by native storage.
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
          isReplace: reader.readBool(),
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
          isReplace: reader.readBool(),
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

/// Encodes generated index entries.
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

/// Decodes generated index entries.
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

/// Encodes a compact native query plan.
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

/// Decodes a compact native query plan.
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

/// Encodes watcher change sets returned by native storage.
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

/// Decodes watcher change sets returned by native storage.
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

/// Low-level writer for CindelWireV1 payloads.
///
/// All multi-byte numeric values are little-endian. Strings are UTF-8 encoded
/// as length-prefixed byte arrays. Callers should normally use the top-level
/// encode functions unless they are adding a new wire payload family.
final class CindelWireWriter {
  CindelWireWriter();

  final BytesBuilder _bytes = BytesBuilder(copy: false);

  /// Returns the accumulated bytes and clears the internal builder.
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
    if (value < 0 || value > _maxUint64) {
      throw RangeError.range(value, 0, _maxUint64, 'value');
    }
    final data = ByteData(8)..setUint64(0, value, Endian.little);
    _bytes.add(data.buffer.asUint8List());
  }

  void writeInt64(int value) {
    if (value < _minInt64 || value > _maxInt64) {
      throw RangeError.range(value, _minInt64, _maxInt64, 'value');
    }
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

  /// Writes a UTF-8 string as length-prefixed bytes.
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

  void writeNativeDocumentValue(WireNativeDocumentValue value) {
    switch (value) {
      case WireNativeDocumentNull():
        writeUint8(wireTagNull);
      case WireNativeDocumentBool(:final value):
        writeUint8(wireTagBool);
        writeBool(value);
      case WireNativeDocumentInt(:final value):
        writeUint8(wireTagInt);
        writeInt64(value);
      case WireNativeDocumentDouble(:final value):
        if (!value.isFinite) {
          throw const FormatException(
            'native document double values must be finite',
          );
        }
        writeUint8(wireTagDouble);
        writeFloat64(value);
      case WireNativeDocumentBytes(:final value):
        writeUint8(wireTagString);
        writeBytes(value);
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

final class _CindelGrowableWireWriter {
  _CindelGrowableWireWriter(int capacity)
    : _bytes = Uint8List(capacity < 32 ? 32 : capacity) {
    _data = ByteData.view(_bytes.buffer);
  }

  late Uint8List _bytes;
  late ByteData _data;
  int _offset = 0;

  Uint8List finish() => Uint8List.sublistView(_bytes, 0, _offset);

  void _ensure(int length) {
    final required = _offset + length;
    if (required <= _bytes.length) {
      return;
    }
    var capacity = _bytes.length;
    while (capacity < required) {
      capacity *= 2;
    }
    final next = Uint8List(capacity)..setAll(0, _bytes);
    _bytes = next;
    _data = ByteData.view(next.buffer);
  }

  void writeUint8(int value) {
    _ensure(1);
    _bytes[_offset] = value & 0xff;
    _offset += 1;
  }

  void writeUint32(int value) {
    if (value < 0 || value > 0xffffffff) {
      throw RangeError.range(value, 0, 0xffffffff, 'value');
    }
    _ensure(4);
    _data.setUint32(_offset, value, Endian.little);
    _offset += 4;
  }

  void writeUint32At(int offset, int value) {
    if (value < 0 || value > 0xffffffff) {
      throw RangeError.range(value, 0, 0xffffffff, 'value');
    }
    _data.setUint32(offset, value, Endian.little);
  }

  void writeUint64(int value) {
    if (value < 0 || value > _maxUint64) {
      throw RangeError.range(value, 0, _maxUint64, 'value');
    }
    _ensure(8);
    _data.setUint64(_offset, value, Endian.little);
    _offset += 8;
  }

  void writeInt64(int value) {
    if (value < _minInt64 || value > _maxInt64) {
      throw RangeError.range(value, _minInt64, _maxInt64, 'value');
    }
    _ensure(8);
    _data.setInt64(_offset, value, Endian.little);
    _offset += 8;
  }

  void writeFloat64(double value) {
    _ensure(8);
    _data.setFloat64(_offset, value == 0.0 ? 0.0 : value, Endian.little);
    _offset += 8;
  }

  void writeBool(bool value) {
    writeUint8(value ? 1 : 0);
  }

  void writeLength(int length) {
    writeUint32(length);
  }

  void writeBytes(Uint8List bytes) {
    writeLength(bytes.length);
    _ensure(bytes.length);
    _bytes.setRange(_offset, _offset + bytes.length, bytes);
    _offset += bytes.length;
  }

  void writeUtf8StringBytes(String value) {
    final lengthOffset = _offset;
    writeLength(0);
    final start = _offset;
    _writeUtf8(value);
    writeUint32At(lengthOffset, _offset - start);
  }

  void writeJsonStringListBytes(List<String> values) {
    final lengthOffset = _offset;
    writeLength(0);
    final start = _offset;
    writeUint8(0x5b);
    for (var i = 0; i < values.length; i += 1) {
      if (i > 0) {
        writeUint8(0x2c);
      }
      writeUint8(0x22);
      _writeJsonStringContent(values[i]);
      writeUint8(0x22);
    }
    writeUint8(0x5d);
    writeUint32At(lengthOffset, _offset - start);
  }

  void _writeJsonStringContent(String value) {
    for (final rune in value.runes) {
      switch (rune) {
        case 0x22:
          writeUint8(0x5c);
          writeUint8(0x22);
        case 0x5c:
          writeUint8(0x5c);
          writeUint8(0x5c);
        case 0x08:
          writeUint8(0x5c);
          writeUint8(0x62);
        case 0x0c:
          writeUint8(0x5c);
          writeUint8(0x66);
        case 0x0a:
          writeUint8(0x5c);
          writeUint8(0x6e);
        case 0x0d:
          writeUint8(0x5c);
          writeUint8(0x72);
        case 0x09:
          writeUint8(0x5c);
          writeUint8(0x74);
        default:
          if (rune < 0x20) {
            writeUint8(0x5c);
            writeUint8(0x75);
            writeUint8(0x30);
            writeUint8(0x30);
            _writeHexNibble(rune >> 4);
            _writeHexNibble(rune);
          } else {
            _writeUtf8Rune(rune);
          }
      }
    }
  }

  void _writeHexNibble(int value) {
    final nibble = value & 0x0f;
    writeUint8(nibble < 10 ? 0x30 + nibble : 0x61 + nibble - 10);
  }

  void _writeUtf8(String value) {
    for (final rune in value.runes) {
      _writeUtf8Rune(rune);
    }
  }

  void _writeUtf8Rune(int rune) {
    if (rune <= 0x7f) {
      writeUint8(rune);
    } else if (rune <= 0x7ff) {
      writeUint8(0xc0 | (rune >> 6));
      writeUint8(0x80 | (rune & 0x3f));
    } else if (rune <= 0xffff) {
      writeUint8(0xe0 | (rune >> 12));
      writeUint8(0x80 | ((rune >> 6) & 0x3f));
      writeUint8(0x80 | (rune & 0x3f));
    } else {
      writeUint8(0xf0 | (rune >> 18));
      writeUint8(0x80 | ((rune >> 12) & 0x3f));
      writeUint8(0x80 | ((rune >> 6) & 0x3f));
      writeUint8(0x80 | (rune & 0x3f));
    }
  }
}

/// Low-level reader for CindelWireV1 payloads.
///
/// The reader fails fast on truncated input, invalid bool tags, invalid UTF-8,
/// unknown tags, and trailing bytes once [finish] is called.
final class CindelWireReader {
  CindelWireReader(this._bytes);

  final Uint8List _bytes;
  int _offset = 0;

  /// Verifies that the entire payload was consumed.
  void finish() {
    if (_offset != _bytes.length) {
      throw const FormatException('wire payload has trailing bytes');
    }
  }

  /// Reads exactly [length] bytes from the current offset.
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

  /// Reads a length-prefixed byte slice.
  Uint8List readBytes() => readExact(readLength());

  /// Reads a length-prefixed UTF-8 string.
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

  WireNativeDocumentValue readNativeDocumentValue() {
    return switch (readUint8()) {
      wireTagNull => const WireNativeDocumentValue.nullValue(),
      wireTagBool => WireNativeDocumentValue.bool(readBool()),
      wireTagInt => WireNativeDocumentValue.int(readInt64()),
      wireTagDouble => WireNativeDocumentValue.double(readFloat64()),
      wireTagString => WireNativeDocumentValue.bytes(readBytes()),
      final tag => throw FormatException(
        'unknown native document value tag $tag',
      ),
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
      wireFilterOpLengthEqual => WireFilterOperation.lengthEqual,
      wireFilterOpLengthLessThan => WireFilterOperation.lengthLessThan,
      wireFilterOpLengthLessThanOrEqual =>
        WireFilterOperation.lengthLessThanOrEqual,
      wireFilterOpLengthGreaterThan => WireFilterOperation.lengthGreaterThan,
      wireFilterOpLengthGreaterThanOrEqual =>
        WireFilterOperation.lengthGreaterThanOrEqual,
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
    WireFilterOperation.lengthEqual => wireFilterOpLengthEqual,
    WireFilterOperation.lengthLessThan => wireFilterOpLengthLessThan,
    WireFilterOperation.lengthLessThanOrEqual =>
      wireFilterOpLengthLessThanOrEqual,
    WireFilterOperation.lengthGreaterThan => wireFilterOpLengthGreaterThan,
    WireFilterOperation.lengthGreaterThanOrEqual =>
      wireFilterOpLengthGreaterThanOrEqual,
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
