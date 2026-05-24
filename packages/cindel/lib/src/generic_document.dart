import 'dart:convert';
import 'dart:typed_data';

import 'native/wire.dart';

const _genericDocumentMagic = [0x43, 0x47, 0x44, 0x31]; // CGD1
const _genericDocumentVersion = 1;

/// Returns whether [bytes] has Cindel's generic manual document envelope.
bool cindelIsGenericDocument(Uint8List bytes) {
  if (bytes.length < 8) {
    return false;
  }
  for (var index = 0; index < _genericDocumentMagic.length; index += 1) {
    if (bytes[index] != _genericDocumentMagic[index]) {
      return false;
    }
  }
  return ByteData.sublistView(bytes, 4, 8).getUint32(0, Endian.little) ==
      _genericDocumentVersion;
}

/// Encodes a manual Cindel document into GenericDocumentV1 bytes.
Uint8List cindelEncodeGenericDocument(Map<String, Object?> document) {
  final writer = CindelWireWriter();
  for (final byte in _genericDocumentMagic) {
    writer.writeUint8(byte);
  }
  writer.writeUint32(_genericDocumentVersion);
  writer.writeValue(WireValue.object(_encodeObject(document)));
  return writer.finish();
}

/// Decodes GenericDocumentV1 bytes into a manual Cindel document.
Map<String, Object?> cindelDecodeGenericDocument(Uint8List bytes) {
  final reader = CindelWireReader(bytes);
  for (final expected in _genericDocumentMagic) {
    final actual = reader.readUint8();
    if (actual != expected) {
      throw const FormatException(
        'generic document has an invalid magic header',
      );
    }
  }
  final version = reader.readUint32();
  if (version != _genericDocumentVersion) {
    throw FormatException('unsupported generic document version `$version`');
  }
  final value = reader.readValue();
  reader.finish();
  if (value is! WireObjectValue) {
    throw const FormatException('generic document root must be an object');
  }
  return _decodeObject(value);
}

List<WireObjectEntry> _encodeObject(Map<Object?, Object?> document) {
  final keys = <String>[];
  for (final key in document.keys) {
    if (key is! String) {
      throw ArgumentError.value(
        key,
        'document',
        'Generic document object keys must be strings.',
      );
    }
    keys.add(key);
  }
  keys.sort(_compareUtf8);
  return [
    for (final key in keys) WireObjectEntry(key, _encodeValue(document[key])),
  ];
}

WireValue _encodeValue(Object? value) {
  return switch (value) {
    null => const WireValue.nullValue(),
    bool() => WireValue.bool(value),
    int() => WireValue.int(value),
    double() when value.isFinite => WireValue.double(value),
    double() => throw ArgumentError.value(
      value,
      'document',
      'Generic document double values must be finite.',
    ),
    String() => WireValue.string(value),
    List() => WireValue.list([for (final item in value) _encodeValue(item)]),
    Map() => WireValue.object(_encodeObject(value)),
    _ => throw ArgumentError.value(
      value,
      'document',
      'Unsupported generic document value.',
    ),
  };
}

Map<String, Object?> _decodeObject(WireObjectValue object) {
  final result = <String, Object?>{};
  for (final field in object.fields) {
    result[field.name] = _decodeValue(field.value);
  }
  return result;
}

Object? _decodeValue(WireValue value) {
  return switch (value) {
    WireNullValue() => null,
    WireBoolValue(:final value) => value,
    WireIntValue(:final value) => value,
    WireDoubleValue(:final value) => value,
    WireStringValue(:final value) => value,
    WireListValue(:final values) => [
      for (final value in values) _decodeValue(value),
    ],
    WireObjectValue() => _decodeObject(value),
  };
}

int _compareUtf8(String left, String right) {
  final leftBytes = utf8.encode(left);
  final rightBytes = utf8.encode(right);
  final length = leftBytes.length < rightBytes.length
      ? leftBytes.length
      : rightBytes.length;
  for (var index = 0; index < length; index += 1) {
    final diff = leftBytes[index] - rightBytes[index];
    if (diff != 0) {
      return diff;
    }
  }
  return leftBytes.length.compareTo(rightBytes.length);
}
