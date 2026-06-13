part of 'bindings.dart';

// Native document value codecs.
//
// These helpers sit below the public `CindelNativeDocumentReader` /
// `CindelNativeDocumentWriter` interfaces. They keep native document hydration
// fast by avoiding extra allocations for ASCII strings while preserving UTF-8
// encoding paths for every value that cannot use the compact representation.

// Reusable scratch buffer for generated native document writers.
//
// The pointer is owned by this object and reused across field writes. Callers
// must use the pointer only inside the callback because later writes may resize
// or overwrite the buffer.
final class _ReusableNativeBytes {
  _ReusableNativeBytes(int capacity)
    : pointer = calloc<Uint8>(capacity),
      capacity = capacity;

  Pointer<Uint8> pointer;
  int capacity;

  // Fast path for ASCII strings: write code units directly into the scratch
  // buffer. Non-ASCII values fall back to normal UTF-8 encoding.
  void withUtf8String(String value, void Function(Pointer<Uint8>, int) action) {
    if (value.length > capacity) {
      calloc.free(pointer);
      capacity = value.length;
      pointer = calloc<Uint8>(capacity);
    }
    final list = pointer.asTypedList(value.length);
    for (var i = 0; i < value.length; i += 1) {
      final codeUnit = value.codeUnitAt(i);
      if (codeUnit > 0x7f) {
        withBytes(utf8.encode(value), action);
        return;
      }
      list[i] = codeUnit;
    }
    action(pointer, value.length);
  }

  // Copies arbitrary bytes into the reusable native buffer.
  void withBytes(List<int> bytes, void Function(Pointer<Uint8>, int) action) {
    if (bytes.length > capacity) {
      calloc.free(pointer);
      capacity = bytes.length;
      pointer = calloc<Uint8>(capacity);
    }
    pointer.asTypedList(bytes.length).setAll(0, bytes);
    action(pointer, bytes.length);
  }

  // Writes a compact string-list payload directly into the reusable buffer when
  // all strings are ASCII. Non-ASCII lists use `_encodeCompactStringList`.
  void withCompactStringList(
    List<String> values,
    void Function(Pointer<Uint8>, int) action,
  ) {
    final staticSize = values.length * 3;
    if (staticSize > 0x00ff_ffff) {
      throw StateError('Cindel string list static size is too large.');
    }
    var totalLength = 3 + staticSize;
    for (final value in values) {
      totalLength += 3 + value.length;
    }
    if (totalLength > capacity) {
      calloc.free(pointer);
      capacity = totalLength;
      pointer = calloc<Uint8>(capacity);
    }

    final bytes = pointer.asTypedList(totalLength);
    _writeU24Le(bytes, 0, staticSize);
    var cursor = 3 + staticSize;
    for (var i = 0; i < values.length; i += 1) {
      final value = values[i];
      _writeU24Le(bytes, 3 + i * 3, cursor - 3);
      _writeU24Le(bytes, cursor, value.length);
      cursor += 3;
      for (var j = 0; j < value.length; j += 1) {
        final codeUnit = value.codeUnitAt(j);
        if (codeUnit > 0x7f) {
          withBytes(_encodeCompactStringList(values), action);
          return;
        }
        bytes[cursor] = codeUnit;
        cursor += 1;
      }
    }
    action(pointer, totalLength);
  }

  void free() {
    calloc.free(pointer);
  }
}

// Sentinel values used by native readers when an id/int field is absent.
const _nativeReaderNullId = 0xffffffffffffffff;
const _nativeReaderNullInt = -0x8000000000000000;

// Decodes a native string payload. Native readers already report whether the
// bytes are ASCII, which lets Dart avoid UTF-8 validation for the common case.
String _decodeNativeString(Uint8List bytes, {required bool isAscii}) {
  if (isAscii) {
    return String.fromCharCodes(bytes);
  }
  return utf8.decode(bytes);
}

// Decodes the string-list formats that Cindel has emitted over time.
//
// Supported inputs:
// - legacy generated JSON list payloads,
// - native offset-table lists with a version marker,
// - compact U24 offset-table lists used by current generated writers.
List<String>? _decodeNativeStringList(Uint8List bytes) {
  if (bytes.isNotEmpty && bytes[0] == 0x5b) {
    final generatedJsonList = _decodeGeneratedJsonStringList(bytes);
    if (generatedJsonList != null) {
      return generatedJsonList;
    }
    try {
      final values = jsonDecode(utf8.decode(bytes));
      if (values is! List<Object?>) {
        return null;
      }
      final strings = <String>[];
      for (final value in values) {
        if (value == null) {
          strings.add('');
        } else if (value is String) {
          strings.add(value);
        } else {
          return null;
        }
      }
      return strings;
    } catch (_) {
      return null;
    }
  }
  if (bytes.length >= 9 &&
      _readU32Le(bytes, 0) == 0xffff_ffff &&
      bytes[4] == 1) {
    return _decodeNativeStringListOffsets(
      bytes,
      offsetsStart: 9,
      count: _readU32Le(bytes, 5),
      offsetBase: 0,
    );
  }
  if (bytes.length < 3) {
    return null;
  }
  final staticSize = _readU24Le(bytes, 0);
  if (staticSize % 3 != 0) {
    return null;
  }
  return _decodeNativeStringListOffsets(
    bytes,
    offsetsStart: 3,
    count: staticSize ~/ 3,
    offsetBase: 3,
  );
}

// Fast parser for the generated JSON string-list shape.
//
// It intentionally accepts only simple strings and `null` values. Escapes,
// control characters, and non-list payloads fall back to the slower JSON parser
// or fail as unsupported.
List<String>? _decodeGeneratedJsonStringList(Uint8List bytes) {
  if (bytes.length < 2 || bytes[0] != 0x5b) {
    return null;
  }
  var offset = 1;
  if (bytes[offset] == 0x5d) {
    return const <String>[];
  }

  final values = <String>[];
  while (offset < bytes.length) {
    final byte = bytes[offset];
    if (byte == 0x22) {
      offset += 1;
      final start = offset;
      var isAscii = true;
      while (offset < bytes.length) {
        final value = bytes[offset];
        if (value == 0x22) {
          break;
        }
        if (value == 0x5c || value < 0x20) {
          return null;
        }
        if (value > 0x7f) {
          isAscii = false;
        }
        offset += 1;
      }
      if (offset >= bytes.length) {
        return null;
      }
      values.add(
        isAscii
            ? String.fromCharCodes(bytes, start, offset)
            : utf8.decode(Uint8List.sublistView(bytes, start, offset)),
      );
      offset += 1;
    } else if (_matchesJsonNull(bytes, offset)) {
      values.add('');
      offset += 4;
    } else {
      return null;
    }

    if (offset >= bytes.length) {
      return null;
    }
    final separator = bytes[offset];
    if (separator == 0x2c) {
      offset += 1;
      continue;
    }
    if (separator == 0x5d) {
      return offset + 1 == bytes.length ? values : null;
    }
    return null;
  }
  return null;
}

// Matches the literal JSON token `null`.
bool _matchesJsonNull(Uint8List bytes, int offset) {
  return offset + 4 <= bytes.length &&
      bytes[offset] == 0x6e &&
      bytes[offset + 1] == 0x75 &&
      bytes[offset + 2] == 0x6c &&
      bytes[offset + 3] == 0x6c;
}

// Decodes an offset-table string list.
//
// Each entry stores a 24-bit relative offset to a length-prefixed UTF-8 string.
// Offset zero represents an empty string.
List<String>? _decodeNativeStringListOffsets(
  Uint8List bytes, {
  required int offsetsStart,
  required int count,
  required int offsetBase,
}) {
  final offsetsEnd = offsetsStart + count * 3;
  if (offsetsEnd > bytes.length) {
    return null;
  }
  final list = List<String>.filled(count, '', growable: true);
  for (var i = 0; i < count; i += 1) {
    final offset = _readU24Le(bytes, offsetsStart + i * 3);
    if (offset == 0) {
      continue;
    }
    final absolute = offsetBase + offset;
    if (absolute < offsetsEnd || absolute + 3 > bytes.length) {
      return null;
    }
    final length = _readU24Le(bytes, absolute);
    final start = absolute + 3;
    final end = start + length;
    if (end > bytes.length) {
      return null;
    }
    list[i] = _decodeNativeStringBytes(bytes, start, end);
  }
  return list;
}

// Decodes one string from a larger native payload, using a local ASCII scan to
// avoid allocating a sublist for pure ASCII values.
String _decodeNativeStringBytes(Uint8List bytes, int start, int end) {
  for (var i = start; i < end; i += 1) {
    if (bytes[i] > 0x7f) {
      return utf8.decode(Uint8List.sublistView(bytes, start, end));
    }
  }
  return String.fromCharCodes(bytes, start, end);
}

// Reads an unsigned 24-bit little-endian integer.
int _readU24Le(Uint8List bytes, int offset) {
  return bytes[offset] | (bytes[offset + 1] << 8) | (bytes[offset + 2] << 16);
}

// Writes an unsigned 24-bit little-endian integer.
void _writeU24Le(Uint8List bytes, int offset, int value) {
  if (value > 0x00ff_ffff) {
    throw StateError('Cindel string list value is too large.');
  }
  bytes[offset] = value & 0xff;
  bytes[offset + 1] = (value >> 8) & 0xff;
  bytes[offset + 2] = (value >> 16) & 0xff;
}

// Reads an unsigned 32-bit little-endian integer.
int _readU32Le(Uint8List bytes, int offset) {
  return bytes[offset] |
      (bytes[offset + 1] << 8) |
      (bytes[offset + 2] << 16) |
      (bytes[offset + 3] << 24);
}

// Encodes a compact string list using U24 offsets and UTF-8 string bytes.
//
// Layout:
// - 3 bytes: static offset-table size.
// - N * 3 bytes: relative offsets from byte 3 to each string record.
// - repeated string records: 3-byte length followed by UTF-8 bytes.
Uint8List _encodeCompactStringList(List<String> values) {
  final encodedValues = [
    for (final value in values) Uint8List.fromList(utf8.encode(value)),
  ];
  final staticSize = values.length * 3;
  if (staticSize > 0x00ff_ffff) {
    throw StateError('Cindel string list static size is too large.');
  }
  var totalLength = 3 + staticSize;
  for (final value in encodedValues) {
    totalLength += 3 + value.length;
  }
  final bytes = Uint8List(totalLength);
  _writeU24Le(bytes, 0, staticSize);
  var cursor = 3 + staticSize;
  for (var i = 0; i < encodedValues.length; i += 1) {
    final value = encodedValues[i];
    _writeU24Le(bytes, 3 + i * 3, cursor - 3);
    _writeU24Le(bytes, cursor, value.length);
    cursor += 3;
    bytes.setAll(cursor, value);
    cursor += value.length;
  }
  return bytes;
}
