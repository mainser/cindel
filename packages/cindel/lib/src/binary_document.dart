import 'dart:convert';
import 'dart:typed_data';

const _magic = [0x43, 0x44, 0x42, 0x46]; // CDBF
const _formatVersion = 1;
const _headerLength = 24;
const _slotLength = 16;
const _nullFlag = 0x01;
const _compactNullBool = 0xff;
const _compactNullInt = -9223372036854775808;
const _compactNullDoubleBits = 0x7ff8000000000001;

/// Schema-backed field types used by Cindel's compact generated document
/// layout.
enum CindelBinaryFieldType {
  boolValue,
  intValue,
  doubleValue,
  stringValue,
  listValue,
  objectValue,
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
  embedded(9),
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

/// Encodes generated field values into Cindel's binary document format.
Uint8List cindelEncodeBinaryDocument(List<Object?> fields) {
  final slots = <_FieldSlot>[];
  final staticSection = BytesBuilder(copy: false);
  final dynamicSection = BytesBuilder(copy: false);

  for (final field in fields) {
    if (field == null) {
      slots.add(_FieldSlot.nullValue());
      continue;
    }
    final value = _BinaryValue.from(field);
    switch (value.kind) {
      case _BinaryKind.boolValue:
        final offset = staticSection.length;
        staticSection.add([value.value as bool ? 1 : 0]);
        slots.add(_FieldSlot.staticValue(value.kind, offset));
      case _BinaryKind.intValue:
      case _BinaryKind.dateTime:
      case _BinaryKind.duration:
        final offset = staticSection.length;
        staticSection.add(_int64Bytes(value.value as int));
        slots.add(_FieldSlot.staticValue(value.kind, offset));
      case _BinaryKind.doubleValue:
        final number = value.value as double;
        if (!number.isFinite) {
          throw ArgumentError.value(number, 'fields', 'Must be finite.');
        }
        final offset = staticSection.length;
        staticSection.add(_float64Bytes(number));
        slots.add(_FieldSlot.staticValue(value.kind, offset));
      case _BinaryKind.stringValue:
      case _BinaryKind.enumValue:
        final payload = utf8.encode(value.value as String);
        final offset = dynamicSection.length;
        dynamicSection.add(payload);
        slots.add(_FieldSlot.dynamicValue(value.kind, offset, payload.length));
      case _BinaryKind.list:
        final payload = _encodeList(value.value as List<Object?>);
        final offset = dynamicSection.length;
        dynamicSection.add(payload);
        slots.add(_FieldSlot.dynamicValue(value.kind, offset, payload.length));
      case _BinaryKind.object:
        final payload = _encodeObject(value.value as Map<String, Object?>);
        final offset = dynamicSection.length;
        dynamicSection.add(payload);
        slots.add(_FieldSlot.dynamicValue(value.kind, offset, payload.length));
      case _BinaryKind.embedded:
      case _BinaryKind.nullValue:
        throw StateError('Unsupported generated binary field kind.');
    }
  }

  final staticBytes = staticSection.toBytes();
  final dynamicBytes = dynamicSection.toBytes();
  final headerLength = _headerLength + slots.length * _slotLength;
  final totalLength = headerLength + staticBytes.length + dynamicBytes.length;
  final writer = _BytesWriter(totalLength);
  writer
    ..addBytes(_magic)
    ..addUint16(_formatVersion)
    ..addUint16(headerLength)
    ..addUint16(slots.length)
    ..addUint16(0)
    ..addUint32(staticBytes.length)
    ..addUint32(dynamicBytes.length)
    ..addUint32(totalLength);
  for (final slot in slots) {
    writer
      ..addUint8(slot.kind.tag)
      ..addUint8(slot.flags)
      ..addUint16(0)
      ..addUint32(slot.staticOffset)
      ..addUint32(slot.dynamicOffset)
      ..addUint32(slot.dynamicLength);
  }
  writer
    ..addBytes(staticBytes)
    ..addBytes(dynamicBytes);
  return writer.takeBytes();
}

/// Decodes Cindel binary document bytes into generated stored field values.
List<Object?> cindelDecodeBinaryDocument(Uint8List bytes) {
  final document = _BinaryDocument(bytes);
  return [
    for (var index = 0; index < document.fieldCount; index += 1)
      document.fieldValue(index),
  ];
}

/// Encodes generated field values using the schema-specific static/dynamic
/// layout used by the optimized typed path.
Uint8List cindelEncodeSchemaBinaryDocument(
  List<Object?> fields,
  List<CindelBinaryFieldType> fieldTypes,
) {
  if (fields.length != fieldTypes.length) {
    throw ArgumentError.value(
      fields.length,
      'fields',
      'Field count must match field type count.',
    );
  }
  final staticSize = fieldTypes.fold<int>(
    0,
    (size, type) => size + _compactStaticSize(type),
  );
  if (staticSize > 0xffffff) {
    throw ArgumentError.value(staticSize, 'fieldTypes', 'Static size too big.');
  }

  final staticBytes = Uint8List(3 + staticSize);
  final staticData = staticBytes.buffer.asByteData();
  _writeUint24(staticBytes, 0, staticSize);
  final dynamicBytes = BytesBuilder(copy: false);
  var staticOffset = 0;
  for (var index = 0; index < fields.length; index += 1) {
    final value = fields[index];
    final type = fieldTypes[index];
    switch (type) {
      case CindelBinaryFieldType.boolValue:
        staticBytes[3 + staticOffset] = value == null
            ? _compactNullBool
            : (value as bool ? 1 : 0);
      case CindelBinaryFieldType.intValue:
        final stored = value as int?;
        if (stored == _compactNullInt) {
          throw ArgumentError.value(
            stored,
            'fields',
            'The compact int null sentinel cannot be stored.',
          );
        }
        staticData.setInt64(
          3 + staticOffset,
          stored ?? _compactNullInt,
          Endian.little,
        );
      case CindelBinaryFieldType.doubleValue:
        final stored = value as double?;
        if (stored != null && !stored.isFinite) {
          throw ArgumentError.value(stored, 'fields', 'Must be finite.');
        }
        if (stored == null) {
          staticData.setUint64(
            3 + staticOffset,
            _compactNullDoubleBits,
            Endian.little,
          );
        } else {
          staticData.setFloat64(3 + staticOffset, stored, Endian.little);
        }
      case CindelBinaryFieldType.stringValue:
        _writeCompactDynamic(
          staticBytes,
          staticOffset,
          staticSize,
          dynamicBytes,
          value == null ? null : utf8.encode(value as String),
        );
      case CindelBinaryFieldType.listValue:
        _writeCompactDynamic(
          staticBytes,
          staticOffset,
          staticSize,
          dynamicBytes,
          value == null ? null : _encodeList((value as List).cast<Object?>()),
        );
      case CindelBinaryFieldType.objectValue:
        _writeCompactDynamic(
          staticBytes,
          staticOffset,
          staticSize,
          dynamicBytes,
          value == null
              ? null
              : _encodeObject((value as Map).cast<String, Object?>()),
        );
    }
    staticOffset += _compactStaticSize(type);
  }
  return (BytesBuilder(copy: false)
        ..add(staticBytes)
        ..add(dynamicBytes.takeBytes()))
      .takeBytes();
}

/// Decodes schema-specific compact generated document bytes.
List<Object?> cindelDecodeSchemaBinaryDocument(
  Uint8List bytes,
  List<CindelBinaryFieldType> fieldTypes,
) {
  if (_hasLegacyMagic(bytes)) {
    return cindelDecodeBinaryDocument(bytes);
  }
  if (bytes.length < 3) {
    throw StateError('Compact binary document is shorter than the header.');
  }
  final staticSize = _readUint24(bytes, 0);
  final expectedStaticSize = fieldTypes.fold<int>(
    0,
    (size, type) => size + _compactStaticSize(type),
  );
  if (staticSize != expectedStaticSize) {
    throw StateError(
      'Compact binary document static size does not match schema.',
    );
  }
  if (bytes.length < 3 + staticSize) {
    throw StateError('Compact binary document static section is truncated.');
  }
  var staticOffset = 0;
  final values = <Object?>[];
  for (final type in fieldTypes) {
    values.add(_readCompactField(bytes, staticSize, staticOffset, type));
    staticOffset += _compactStaticSize(type);
  }
  return values;
}

/// Direct reader for schema-specific compact generated document bytes.
///
/// Generated hydration code uses this reader to pull only the fields it assigns
/// to the Dart model, avoiding the intermediate `List<Object?>` allocation used
/// by [cindelDecodeSchemaBinaryDocument].
final class CindelSchemaBinaryDocumentReader {
  CindelSchemaBinaryDocumentReader(this.bytes, {required this.staticSize}) {
    if (_hasLegacyMagic(bytes)) {
      _legacyFields = cindelDecodeBinaryDocument(bytes);
      return;
    }
    if (bytes.length < 3) {
      throw StateError('Compact binary document is shorter than the header.');
    }
    final storedStaticSize = _readUint24(bytes, 0);
    if (storedStaticSize != staticSize) {
      throw StateError(
        'Compact binary document static size does not match schema.',
      );
    }
    if (bytes.length < 3 + staticSize) {
      throw StateError('Compact binary document static section is truncated.');
    }
    _byteData = bytes.buffer.asByteData(
      bytes.offsetInBytes,
      bytes.lengthInBytes,
    );
  }

  final Uint8List bytes;
  final int staticSize;
  ByteData? _byteData;
  List<Object?>? _legacyFields;

  bool? readBool(int fieldIndex, int staticOffset) {
    final legacyFields = _legacyFields;
    if (legacyFields != null) {
      return legacyFields[fieldIndex] as bool?;
    }
    final absolute = 3 + staticOffset;
    return switch (bytes[absolute]) {
      _compactNullBool => null,
      0 => false,
      1 => true,
      final value => throw StateError('Invalid compact bool byte `$value`.'),
    };
  }

  int? readInt(int fieldIndex, int staticOffset) {
    final legacyFields = _legacyFields;
    if (legacyFields != null) {
      return legacyFields[fieldIndex] as int?;
    }
    final value = _byteData!.getInt64(3 + staticOffset, Endian.little);
    return value == _compactNullInt ? null : value;
  }

  double? readDouble(int fieldIndex, int staticOffset) {
    final legacyFields = _legacyFields;
    if (legacyFields != null) {
      return legacyFields[fieldIndex] as double?;
    }
    return _readCompactDouble(_byteData!, 3 + staticOffset);
  }

  String? readString(int fieldIndex, int staticOffset) {
    final legacyFields = _legacyFields;
    if (legacyFields != null) {
      return legacyFields[fieldIndex] as String?;
    }
    final payload = _readCompactDynamic(bytes, staticSize, staticOffset);
    return payload == null ? null : utf8.decode(payload);
  }

  List<Object?>? readList(int fieldIndex, int staticOffset) {
    final legacyFields = _legacyFields;
    if (legacyFields != null) {
      return legacyFields[fieldIndex] as List<Object?>?;
    }
    final payload = _readCompactDynamic(bytes, staticSize, staticOffset);
    return payload == null ? null : _decodeList(payload);
  }

  Map<String, Object?>? readObject(int fieldIndex, int staticOffset) {
    final legacyFields = _legacyFields;
    if (legacyFields != null) {
      return (legacyFields[fieldIndex] as Map?)?.cast<String, Object?>();
    }
    final payload = _readCompactDynamic(bytes, staticSize, staticOffset);
    return payload == null ? null : _decodeObject(payload);
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

final class _FieldSlot {
  const _FieldSlot({
    required this.kind,
    required this.flags,
    required this.staticOffset,
    required this.dynamicOffset,
    required this.dynamicLength,
  });

  const _FieldSlot.nullValue()
    : kind = _BinaryKind.nullValue,
      flags = _nullFlag,
      staticOffset = 0,
      dynamicOffset = 0,
      dynamicLength = 0;

  const _FieldSlot.staticValue(this.kind, this.staticOffset)
    : flags = 0,
      dynamicOffset = 0,
      dynamicLength = 0;

  const _FieldSlot.dynamicValue(
    this.kind,
    this.dynamicOffset,
    this.dynamicLength,
  ) : flags = 0,
      staticOffset = 0;

  final _BinaryKind kind;
  final int flags;
  final int staticOffset;
  final int dynamicOffset;
  final int dynamicLength;

  bool get isNull => flags & _nullFlag != 0 || kind == _BinaryKind.nullValue;
}

final class _BinaryDocument {
  _BinaryDocument(this.bytes) {
    if (bytes.length < _headerLength) {
      throw StateError('Binary document is shorter than the header.');
    }
    for (var index = 0; index < _magic.length; index += 1) {
      if (bytes[index] != _magic[index]) {
        throw StateError('Binary document has an invalid magic header.');
      }
    }
    final version = _readUint16(bytes, 4);
    if (version != _formatVersion) {
      throw StateError('Unsupported binary document version `$version`.');
    }
    headerLength = _readUint16(bytes, 6);
    fieldCount = _readUint16(bytes, 8);
    staticLength = _readUint32(bytes, 12);
    dynamicLength = _readUint32(bytes, 16);
    final totalLength = _readUint32(bytes, 20);
    if (totalLength != bytes.length) {
      throw StateError('Binary document total length does not match bytes.');
    }
    staticStart = headerLength;
    dynamicStart = staticStart + staticLength;
    if (dynamicStart + dynamicLength != totalLength) {
      throw StateError('Binary document sections do not match total length.');
    }
  }

  final Uint8List bytes;
  late final int headerLength;
  late final int fieldCount;
  late final int staticStart;
  late final int dynamicStart;
  late final int staticLength;
  late final int dynamicLength;

  Object? fieldValue(int index) {
    final slot = _slot(index);
    if (slot.isNull) {
      return null;
    }
    return switch (slot.kind) {
      _BinaryKind.boolValue => _staticPayload(slot, 1)[0] != 0,
      _BinaryKind.intValue ||
      _BinaryKind.dateTime ||
      _BinaryKind.duration => _readInt64(_staticPayload(slot, 8), 0),
      _BinaryKind.doubleValue => _readFloat64(_staticPayload(slot, 8), 0),
      _BinaryKind.stringValue ||
      _BinaryKind.enumValue => utf8.decode(_dynamicPayload(slot)),
      _BinaryKind.list => _decodeList(_dynamicPayload(slot)),
      _BinaryKind.embedded => cindelDecodeBinaryDocument(
        Uint8List.fromList(_dynamicPayload(slot)),
      ),
      _BinaryKind.object => _decodeObject(_dynamicPayload(slot)),
      _BinaryKind.nullValue => null,
    };
  }

  _FieldSlot _slot(int index) {
    if (index < 0 || index >= fieldCount) {
      throw RangeError.index(index, null, 'index', null, fieldCount);
    }
    final offset = _headerLength + index * _slotLength;
    return _FieldSlot(
      kind: _BinaryKind.fromTag(bytes[offset]),
      flags: bytes[offset + 1],
      staticOffset: _readUint32(bytes, offset + 4),
      dynamicOffset: _readUint32(bytes, offset + 8),
      dynamicLength: _readUint32(bytes, offset + 12),
    );
  }

  Uint8List _staticPayload(_FieldSlot slot, int length) {
    final start = staticStart + slot.staticOffset;
    final end = start + length;
    if (end > staticStart + staticLength) {
      throw StateError('Binary static field is outside the static section.');
    }
    return Uint8List.sublistView(bytes, start, end);
  }

  Uint8List _dynamicPayload(_FieldSlot slot) {
    final start = dynamicStart + slot.dynamicOffset;
    final end = start + slot.dynamicLength;
    if (end > dynamicStart + dynamicLength) {
      throw StateError('Binary dynamic field is outside the dynamic section.');
    }
    return Uint8List.sublistView(bytes, start, end);
  }
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
    _BinaryKind.embedded || _BinaryKind.nullValue => throw StateError(
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
      _BinaryKind.embedded => cindelDecodeBinaryDocument(payload),
      _BinaryKind.object => _decodeObject(payload),
      _BinaryKind.nullValue => null,
    };
  }
}

final class _BytesWriter {
  _BytesWriter([int? capacity])
    : _builder = BytesBuilder(copy: false),
      _bytes = capacity == null ? null : Uint8List(capacity);

  final BytesBuilder _builder;
  final Uint8List? _bytes;
  int _offset = 0;

  void addUint8(int value) {
    final bytes = _bytes;
    if (bytes == null) {
      _builder.add([value]);
    } else {
      bytes[_offset] = value;
      _offset += 1;
    }
  }

  void addUint16(int value) {
    addBytes(_uint16Bytes(value));
  }

  void addUint32(int value) {
    addBytes(_uint32Bytes(value));
  }

  void addBytes(List<int> value) {
    final bytes = _bytes;
    if (bytes == null) {
      _builder.add(value);
    } else {
      bytes.setRange(_offset, _offset + value.length, value);
      _offset += value.length;
    }
  }

  Uint8List takeBytes() {
    final bytes = _bytes;
    if (bytes == null) {
      return _builder.toBytes();
    }
    if (_offset != bytes.length) {
      return Uint8List.sublistView(bytes, 0, _offset);
    }
    return bytes;
  }
}

Uint8List _uint16Bytes(int value) {
  return Uint8List(2)..buffer.asByteData().setUint16(0, value, Endian.little);
}

Uint8List _uint32Bytes(int value) {
  return Uint8List(4)..buffer.asByteData().setUint32(0, value, Endian.little);
}

Uint8List _int64Bytes(int value) {
  return Uint8List(8)..buffer.asByteData().setInt64(0, value, Endian.little);
}

Uint8List _float64Bytes(double value) {
  return Uint8List(8)..buffer.asByteData().setFloat64(0, value, Endian.little);
}

int _readUint16(Uint8List bytes, int offset) {
  return bytes.buffer
      .asByteData(bytes.offsetInBytes, bytes.lengthInBytes)
      .getUint16(offset, Endian.little);
}

int _readUint32(Uint8List bytes, int offset) {
  return bytes.buffer
      .asByteData(bytes.offsetInBytes, bytes.lengthInBytes)
      .getUint32(offset, Endian.little);
}

int _readInt64(Uint8List bytes, int offset) {
  return bytes.buffer
      .asByteData(bytes.offsetInBytes, bytes.lengthInBytes)
      .getInt64(offset, Endian.little);
}

double _readFloat64(Uint8List bytes, int offset) {
  return bytes.buffer
      .asByteData(bytes.offsetInBytes, bytes.lengthInBytes)
      .getFloat64(offset, Endian.little);
}

bool _hasLegacyMagic(Uint8List bytes) {
  if (bytes.length < _magic.length) {
    return false;
  }
  for (var index = 0; index < _magic.length; index += 1) {
    if (bytes[index] != _magic[index]) {
      return false;
    }
  }
  return true;
}

int _compactStaticSize(CindelBinaryFieldType type) {
  return switch (type) {
    CindelBinaryFieldType.boolValue => 1,
    CindelBinaryFieldType.intValue => 8,
    CindelBinaryFieldType.doubleValue => 8,
    CindelBinaryFieldType.stringValue ||
    CindelBinaryFieldType.listValue ||
    CindelBinaryFieldType.objectValue => 3,
  };
}

void _writeCompactDynamic(
  Uint8List staticBytes,
  int staticOffset,
  int staticSize,
  BytesBuilder dynamicBytes,
  List<int>? payload,
) {
  if (payload == null) {
    _writeUint24(staticBytes, 3 + staticOffset, 0);
    return;
  }
  if (payload.length > 0xffffff) {
    throw ArgumentError.value(payload.length, 'payload', 'Payload too large.');
  }
  final offset = staticSize + dynamicBytes.length;
  if (offset > 0xffffff) {
    throw ArgumentError.value(offset, 'payload', 'Dynamic offset too large.');
  }
  _writeUint24(staticBytes, 3 + staticOffset, offset);
  final header = Uint8List(3);
  _writeUint24(header, 0, payload.length);
  dynamicBytes
    ..add(header)
    ..add(payload);
}

Object? _readCompactField(
  Uint8List bytes,
  int staticSize,
  int staticOffset,
  CindelBinaryFieldType type,
) {
  final byteData = bytes.buffer.asByteData(
    bytes.offsetInBytes,
    bytes.lengthInBytes,
  );
  final absolute = 3 + staticOffset;
  return switch (type) {
    CindelBinaryFieldType.boolValue => switch (bytes[absolute]) {
      _compactNullBool => null,
      0 => false,
      1 => true,
      final value => throw StateError('Invalid compact bool byte `$value`.'),
    },
    CindelBinaryFieldType.intValue => switch (byteData.getInt64(
      absolute,
      Endian.little,
    )) {
      _compactNullInt => null,
      final value => value,
    },
    CindelBinaryFieldType.doubleValue => _readCompactDouble(byteData, absolute),
    CindelBinaryFieldType.stringValue => switch (_readCompactDynamic(
      bytes,
      staticSize,
      staticOffset,
    )) {
      null => null,
      final payload => utf8.decode(payload),
    },
    CindelBinaryFieldType.listValue => switch (_readCompactDynamic(
      bytes,
      staticSize,
      staticOffset,
    )) {
      null => null,
      final payload => _decodeList(payload),
    },
    CindelBinaryFieldType.objectValue => switch (_readCompactDynamic(
      bytes,
      staticSize,
      staticOffset,
    )) {
      null => null,
      final payload => _decodeObject(payload),
    },
  };
}

double? _readCompactDouble(ByteData byteData, int offset) {
  final bits = byteData.getUint64(offset, Endian.little);
  if (bits == _compactNullDoubleBits) {
    return null;
  }
  return byteData.getFloat64(offset, Endian.little);
}

Uint8List? _readCompactDynamic(
  Uint8List bytes,
  int staticSize,
  int staticOffset,
) {
  final relative = _readUint24(bytes, 3 + staticOffset);
  if (relative == 0) {
    return null;
  }
  if (relative < staticSize) {
    throw StateError('Compact dynamic field points into static section.');
  }
  final header = 3 + relative;
  if (header + 3 > bytes.length) {
    throw StateError('Compact dynamic field length is truncated.');
  }
  final length = _readUint24(bytes, header);
  final start = header + 3;
  final end = start + length;
  if (end > bytes.length) {
    throw StateError('Compact dynamic field payload is truncated.');
  }
  return Uint8List.sublistView(bytes, start, end);
}

void _writeUint24(Uint8List bytes, int offset, int value) {
  bytes[offset] = value & 0xff;
  bytes[offset + 1] = (value >> 8) & 0xff;
  bytes[offset + 2] = (value >> 16) & 0xff;
}

int _readUint24(Uint8List bytes, int offset) {
  return bytes[offset] | (bytes[offset + 1] << 8) | (bytes[offset + 2] << 16);
}
