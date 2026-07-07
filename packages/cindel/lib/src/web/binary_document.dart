import 'dart:convert';
import 'dart:typed_data';

/// Raw bytes encoded with Cindel's generated binary document format.
typedef CindelBinaryDocumentBytes = Uint8List;

const _nullFlag = 0x01;
const _uint32Range = 4294967296;
const _int32SignBit = 0x80000000;
const _maxSafeInteger = 0x1FFFFFFFFFFFFF;

/// Field type metadata used by generated binary document codecs.
enum CindelBinaryFieldType {
  /// Boolean field.
  boolValue,

  /// Integer field.
  intValue,

  /// Double field.
  doubleValue,

  /// String field.
  stringValue,

  /// List field.
  listValue,

  /// Object field.
  objectValue,
}

/// Web-safe placeholder for the native binary document reader.
///
/// Generated code imports these symbols through `package:cindel/cindel.dart`.
/// On Web, supported typed storage uses SQLite native rows through the Worker;
/// the native binary-document codec is intentionally unavailable so Web code
/// does not silently drift onto an unsupported MDBX-style hydration path.
final class CindelSchemaBinaryDocumentReader {
  /// Creates a reader placeholder.
  CindelSchemaBinaryDocumentReader(Uint8List bytes, {required int staticSize});

  /// Binary document decoding is not part of the Web SQLite facade.
  int readId(int documentIndex) => _unsupported();

  /// Binary document decoding is not part of the Web SQLite facade.
  bool? readBool(int fieldIndex, int staticOffset) => _unsupported();

  /// Binary document decoding is not part of the Web SQLite facade.
  int? readInt(int fieldIndex, int staticOffset) => _unsupported();

  /// Binary document decoding is not part of the Web SQLite facade.
  double? readDouble(int fieldIndex, int staticOffset) => _unsupported();

  /// Binary document decoding is not part of the Web SQLite facade.
  String? readString(int fieldIndex, int staticOffset) => _unsupported();

  /// Binary document decoding is not part of the Web SQLite facade.
  List<String>? readStringList(int fieldIndex, int staticOffset) =>
      _unsupported();

  /// Binary document decoding is not part of the Web SQLite facade.
  Object? readList(int fieldIndex, int staticOffset) => _unsupported();

  /// Binary document decoding is not part of the Web SQLite facade.
  Object? readObject(int fieldIndex, int staticOffset) => _unsupported();
}

/// Binary document encoding is not part of the Web SQLite facade.
Uint8List cindelEncodeSchemaBinaryDocument(
  List<Object?> values,
  List<CindelBinaryFieldType> fieldTypes,
) {
  throw UnsupportedError(
    'Cindel Web uses SQLite native documents instead of binary documents.',
  );
}

/// Binary document decoding is not part of the Web SQLite facade.
List<Object?> cindelDecodeSchemaBinaryDocument(Uint8List bytes) {
  throw UnsupportedError(
    'Cindel Web uses SQLite native documents instead of binary documents.',
  );
}

/// Binary object encoding is not part of the Web SQLite facade.
Uint8List cindelEncodeBinaryObject(Map<String, Object?> value) {
  return _encodeObject(value);
}

/// Binary object decoding is not part of the Web SQLite facade.
Map<String, Object?> cindelDecodeBinaryObject(Uint8List bytes) {
  return _decodeObject(bytes);
}

/// Binary list encoding is not part of the Web SQLite facade.
Uint8List cindelEncodeBinaryList(List<Object?> value) {
  return _encodeList(value);
}

/// Binary list decoding is not part of the Web SQLite facade.
List<Object?> cindelDecodeBinaryList(Uint8List bytes) {
  return _decodeList(bytes);
}

Never _unsupported() {
  throw UnsupportedError(
    'Cindel Web uses SQLite native documents instead of binary documents.',
  );
}

enum _BinaryKind {
  nullValue(0),
  boolValue(1),
  intValue(2),
  doubleValue(3),
  stringValue(4),
  dateTime(5),
  duration(6),
  list(7),
  enumValue(8),
  object(10);

  const _BinaryKind(this.tag);

  final int tag;

  static _BinaryKind fromTag(int tag) {
    return _BinaryKind.values.firstWhere(
      (kind) => kind.tag == tag,
      orElse: () => throw StateError('Unknown binary field kind `$tag`.'),
    );
  }
}

final class _BinaryValue {
  const _BinaryValue(this.kind, this.value);

  factory _BinaryValue.from(Object value) {
    return switch (value) {
      bool() => _BinaryValue(_BinaryKind.boolValue, value),
      int() => _BinaryValue(_BinaryKind.intValue, value),
      double() => _BinaryValue(_BinaryKind.doubleValue, value),
      String() => _BinaryValue(_BinaryKind.stringValue, value),
      DateTime() => _BinaryValue(
        _BinaryKind.dateTime,
        value.microsecondsSinceEpoch,
      ),
      Duration() => _BinaryValue(_BinaryKind.duration, value.inMicroseconds),
      List<Object?>() => _BinaryValue(_BinaryKind.list, value),
      Map() => _BinaryValue(_BinaryKind.object, value.cast<String, Object?>()),
      _ => throw ArgumentError.value(
        value,
        'fields',
        'Unsupported Cindel binary field value.',
      ),
    };
  }

  final _BinaryKind kind;
  final Object value;
}

Uint8List _encodeList(List<Object?> values) {
  final writer = _BytesWriter();
  writer.addUint32(values.length);
  for (final value in values) {
    writer.addBytes(_encodeValueRecord(value));
  }
  return writer.takeBytes();
}

List<Object?> _decodeList(Uint8List bytes) {
  final reader = _BytesReader(bytes);
  final count = reader.readUint32();
  return [
    for (var index = 0; index < count; index += 1) reader.readValueRecord(),
  ];
}

Uint8List _encodeObject(Map<String, Object?> values) {
  final entries = values.entries.toList(growable: false)
    ..sort((left, right) => left.key.compareTo(right.key));
  final writer = _BytesWriter();
  writer.addUint32(entries.length);
  for (final entry in entries) {
    final name = utf8.encode(entry.key);
    writer
      ..addUint32(name.length)
      ..addBytes(name)
      ..addBytes(_encodeValueRecord(entry.value));
  }
  return writer.takeBytes();
}

Map<String, Object?> _decodeObject(Uint8List bytes) {
  final reader = _BytesReader(bytes);
  final count = reader.readUint32();
  return <String, Object?>{
    for (var index = 0; index < count; index += 1)
      reader.readString(): reader.readValueRecord(),
  };
}

Uint8List _encodeValueRecord(Object? value) {
  final writer = _BytesWriter();
  if (value == null) {
    writer
      ..addUint8(_BinaryKind.nullValue.tag)
      ..addUint8(_nullFlag)
      ..addUint16(0)
      ..addUint32(0);
    return writer.takeBytes();
  }

  final binary = _BinaryValue.from(value);
  final payload = switch (binary.kind) {
    _BinaryKind.boolValue => Uint8List.fromList([binary.value as bool ? 1 : 0]),
    _BinaryKind.intValue ||
    _BinaryKind.dateTime ||
    _BinaryKind.duration => _int64Bytes(binary.value as int),
    _BinaryKind.doubleValue => _float64Bytes(binary.value as double),
    _BinaryKind.stringValue || _BinaryKind.enumValue => Uint8List.fromList(
      utf8.encode(binary.value as String),
    ),
    _BinaryKind.list => _encodeList(binary.value as List<Object?>),
    _BinaryKind.object => _encodeObject(binary.value as Map<String, Object?>),
    _BinaryKind.nullValue => throw StateError(
      'Unsupported generated binary value record kind.',
    ),
  };

  writer
    ..addUint8(binary.kind.tag)
    ..addUint8(0)
    ..addUint16(0)
    ..addUint32(payload.length)
    ..addBytes(payload);
  return writer.takeBytes();
}

final class _BytesReader {
  _BytesReader(this.bytes);

  final Uint8List bytes;
  int _offset = 0;

  int readUint32() {
    final value = _readUint32(bytes, _offset);
    _offset += 4;
    return value;
  }

  String readString() {
    final length = readUint32();
    final value = utf8.decode(
      Uint8List.sublistView(bytes, _offset, _offset + length),
    );
    _offset += length;
    return value;
  }

  Object? readValueRecord() {
    final kind = _BinaryKind.fromTag(bytes[_offset]);
    final flags = bytes[_offset + 1];
    final length = _readUint32(bytes, _offset + 4);
    _offset += 8;
    final payload = Uint8List.sublistView(bytes, _offset, _offset + length);
    _offset += length;
    if (flags & _nullFlag != 0 || kind == _BinaryKind.nullValue) {
      return null;
    }
    return switch (kind) {
      _BinaryKind.boolValue => payload[0] != 0,
      _BinaryKind.intValue ||
      _BinaryKind.dateTime ||
      _BinaryKind.duration => _readInt64(payload, 0),
      _BinaryKind.doubleValue => _readFloat64(payload, 0),
      _BinaryKind.stringValue || _BinaryKind.enumValue => utf8.decode(payload),
      _BinaryKind.list => _decodeList(payload),
      _BinaryKind.object => _decodeObject(payload),
      _BinaryKind.nullValue => null,
    };
  }
}

final class _BytesWriter {
  _BytesWriter() : _builder = BytesBuilder(copy: false);

  final BytesBuilder _builder;

  void addUint8(int value) {
    _builder.add([value]);
  }

  void addUint16(int value) {
    addBytes(_uint16Bytes(value));
  }

  void addUint32(int value) {
    addBytes(_uint32Bytes(value));
  }

  void addBytes(List<int> value) {
    _builder.add(value);
  }

  Uint8List takeBytes() {
    return _builder.toBytes();
  }
}

Uint8List _uint16Bytes(int value) {
  return Uint8List(2)..buffer.asByteData().setUint16(0, value, Endian.little);
}

Uint8List _uint32Bytes(int value) {
  return Uint8List(4)..buffer.asByteData().setUint32(0, value, Endian.little);
}

Uint8List _int64Bytes(int value) {
  if (value < -_maxSafeInteger || value > _maxSafeInteger) {
    throw UnsupportedError(
      'Cindel Web cannot encode embedded int64 values outside '
      'JavaScript safe integer range.',
    );
  }
  final low = value % _uint32Range;
  final high = (value - low) ~/ _uint32Range;
  final bytes = Uint8List(8);
  _writeUint32(bytes, 0, low);
  _writeUint32(bytes, 4, high % _uint32Range);
  return bytes;
}

Uint8List _float64Bytes(double value) {
  return Uint8List(8)..buffer.asByteData().setFloat64(0, value, Endian.little);
}

int _readUint32(Uint8List bytes, int offset) {
  return bytes.buffer
      .asByteData(bytes.offsetInBytes, bytes.lengthInBytes)
      .getUint32(offset, Endian.little);
}

int _readInt64(Uint8List bytes, int offset) {
  final low = _readUint32(bytes, offset);
  final high = _readUint32(bytes, offset + 4);
  final signedHigh = high >= _int32SignBit ? high - _uint32Range : high;
  final value = signedHigh * _uint32Range + low;
  if (value < -_maxSafeInteger || value > _maxSafeInteger) {
    throw UnsupportedError(
      'Cindel Web cannot decode embedded int64 values outside '
      'JavaScript safe integer range.',
    );
  }
  return value;
}

double _readFloat64(Uint8List bytes, int offset) {
  return bytes.buffer
      .asByteData(bytes.offsetInBytes, bytes.lengthInBytes)
      .getFloat64(offset, Endian.little);
}

void _writeUint32(Uint8List bytes, int offset, int value) {
  bytes[offset] = value & 0xff;
  bytes[offset + 1] = (value >> 8) & 0xff;
  bytes[offset + 2] = (value >> 16) & 0xff;
  bytes[offset + 3] = (value >> 24) & 0xff;
}
