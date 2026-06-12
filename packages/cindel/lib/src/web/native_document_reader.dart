import 'dart:convert';
import 'dart:typed_data';

import '../schema.dart';

const _nativeBoolNull = 0xff;
const _nativeIntNullBytes = [0, 0, 0, 0, 0, 0, 0, 0x80];
const _uint32Range = 4294967296;
const _int32SignBit = 0x80000000;
const _maxSafeInteger = 0x1FFFFFFFFFFFFF;

final class CindelWebNativeDocumentReader
    implements CindelNativeDocumentReader {
  CindelWebNativeDocumentReader({
    required List<int> ids,
    required List<Uint8List?> documents,
    required Uint8List fieldTypes,
  }) : _ids = ids,
       _documents = documents,
       _fieldTypes = fieldTypes,
       _offsets = _fieldOffsets(fieldTypes);

  final List<int> _ids;
  final List<Uint8List?> _documents;
  final Uint8List _fieldTypes;
  final List<int> _offsets;

  @override
  int get length => _documents.length;

  @override
  bool isPresent(int documentIndex) => _documents[documentIndex] != null;

  @override
  int readId(int documentIndex) => _ids[documentIndex];

  @override
  bool? readBool(int documentIndex, int fieldIndex) {
    final document = _document(documentIndex);
    _checkFieldType(fieldIndex, 0);
    final value = document[_fieldOffset(fieldIndex)];
    return value == _nativeBoolNull ? null : value != 0;
  }

  @override
  int? readInt(int documentIndex, int fieldIndex) {
    final document = _document(documentIndex);
    _checkFieldType(fieldIndex, 1);
    final offset = _fieldOffset(fieldIndex);
    if (_bytesEqual(
      Uint8List.sublistView(document, offset, offset + 8),
      _nativeIntNullBytes,
    )) {
      return null;
    }
    return _readSafeInt64(document, offset);
  }

  @override
  double? readDouble(int documentIndex, int fieldIndex) {
    final document = _document(documentIndex);
    _checkFieldType(fieldIndex, 2);
    final offset = _fieldOffset(fieldIndex);
    final value = ByteData.sublistView(
      document,
      offset,
      offset + 8,
    ).getFloat64(0, Endian.little);
    return value.isNaN ? null : value;
  }

  @override
  String? readString(int documentIndex, int fieldIndex) {
    _checkFieldType(fieldIndex, 3);
    final payload = _dynamicPayload(documentIndex, fieldIndex);
    return payload == null ? null : utf8.decode(payload);
  }

  @override
  List<String>? readStringList(int documentIndex, int fieldIndex) {
    _checkFieldType(fieldIndex, 4);
    final payload = _dynamicPayload(documentIndex, fieldIndex);
    if (payload == null) {
      return null;
    }
    final value = jsonDecode(utf8.decode(payload));
    if (value is! List) {
      throw const FormatException('Native string-list payload is not a list.');
    }
    return [for (final item in value) item as String];
  }

  @override
  Map<String, Object?>? readObject(int documentIndex, int fieldIndex) {
    throw UnsupportedError(
      'Cindel Web native embedded object reads are not available yet.',
    );
  }

  @override
  List<Map<String, Object?>?>? readObjectList(
    int documentIndex,
    int fieldIndex,
  ) {
    throw UnsupportedError(
      'Cindel Web native embedded object-list reads are not available yet.',
    );
  }

  @override
  CindelNativeDocumentReader? readList(int documentIndex, int fieldIndex) {
    throw UnsupportedError('Nested native Web list readers are not supported.');
  }

  @override
  void release() {}

  Uint8List _document(int documentIndex) {
    final document = _documents[documentIndex];
    if (document == null) {
      throw StateError('Native Cindel document is not present.');
    }
    final staticSize = _readU24(document, 0);
    final expectedStaticSize = _staticSize(_fieldTypes);
    if (staticSize != expectedStaticSize) {
      throw const FormatException(
        'Native Cindel document static size does not match schema.',
      );
    }
    if (document.length < 3 + staticSize) {
      throw const FormatException(
        'Native Cindel document static section is truncated.',
      );
    }
    return document;
  }

  int _fieldOffset(int fieldIndex) {
    return 3 + _offsets[fieldIndex];
  }

  Uint8List? _dynamicPayload(int documentIndex, int fieldIndex) {
    final document = _document(documentIndex);
    final relativeOffset = _readU24(document, _fieldOffset(fieldIndex));
    if (relativeOffset == 0) {
      return null;
    }
    final staticSize = _readU24(document, 0);
    if (relativeOffset < staticSize) {
      throw const FormatException(
        'Native Cindel dynamic field points into static section.',
      );
    }
    final lengthOffset = 3 + relativeOffset;
    final length = _readU24(document, lengthOffset);
    final start = lengthOffset + 3;
    final end = start + length;
    if (end > document.length) {
      throw const FormatException(
        'Native Cindel dynamic field payload is truncated.',
      );
    }
    return Uint8List.sublistView(document, start, end);
  }

  void _checkFieldType(int fieldIndex, int expected) {
    if (fieldIndex < 0 || fieldIndex >= _fieldTypes.length) {
      throw RangeError.index(fieldIndex, _fieldTypes, 'fieldIndex');
    }
    if (_fieldTypes[fieldIndex] != expected) {
      throw StateError('Native Cindel field type does not match reader call.');
    }
  }
}

List<int> _fieldOffsets(Uint8List fieldTypes) {
  var offset = 0;
  return [
    for (final fieldType in fieldTypes)
      () {
        final current = offset;
        offset += _fieldStaticSize(fieldType);
        return current;
      }(),
  ];
}

int _staticSize(Uint8List fieldTypes) {
  var size = 0;
  for (final fieldType in fieldTypes) {
    size += _fieldStaticSize(fieldType);
  }
  return size;
}

int _fieldStaticSize(int fieldType) {
  return switch (fieldType) {
    0 => 1,
    1 || 2 => 8,
    3 || 4 || 5 => 3,
    _ => throw StateError('Unsupported native Cindel field type.'),
  };
}

int _readU24(Uint8List bytes, int offset) {
  if (offset < 0 || offset + 3 > bytes.length) {
    throw const FormatException('Native Cindel uint24 is out of range.');
  }
  return bytes[offset] | (bytes[offset + 1] << 8) | (bytes[offset + 2] << 16);
}

int _readSafeInt64(Uint8List bytes, int offset) {
  if (offset < 0 || offset + 8 > bytes.length) {
    throw const FormatException('Native Cindel int64 is out of range.');
  }
  final low =
      bytes[offset] +
      bytes[offset + 1] * 0x100 +
      bytes[offset + 2] * 0x10000 +
      bytes[offset + 3] * 0x1000000;
  final high =
      bytes[offset + 4] +
      bytes[offset + 5] * 0x100 +
      bytes[offset + 6] * 0x10000 +
      bytes[offset + 7] * 0x1000000;
  final signedHigh = high >= _int32SignBit ? high - _uint32Range : high;
  final value = signedHigh * _uint32Range + low;
  if (value < -_maxSafeInteger || value > _maxSafeInteger) {
    throw UnsupportedError(
      'Cindel Web cannot represent native int64 values outside '
      'JavaScript safe integer range.',
    );
  }
  return value;
}

bool _bytesEqual(Uint8List left, List<int> right) {
  if (left.length != right.length) {
    return false;
  }
  for (var i = 0; i < left.length; i += 1) {
    if (left[i] != right[i]) {
      return false;
    }
  }
  return true;
}
