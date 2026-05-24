import 'dart:convert';
import 'dart:typed_data';

const int wireTagNull = 0;
const int wireTagBool = 1;
const int wireTagInt = 2;
const int wireTagDouble = 3;
const int wireTagString = 4;
const int wireTagList = 5;
const int wireTagObject = 6;

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
    required this.isId,
    required this.isIndexed,
    required this.isUnique,
    required this.isNullable,
    required this.caseSensitive,
  });

  final String name;
  final String typeName;
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
      other.isId == isId &&
      other.isIndexed == isIndexed &&
      other.isUnique == isUnique &&
      other.isNullable == isNullable &&
      other.caseSensitive == caseSensitive;

  @override
  int get hashCode => Object.hash(
    name,
    typeName,
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
