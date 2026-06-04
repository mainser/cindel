part of 'bindings.dart';

final class _CindelNativeDocumentWriter
    implements
        CindelNativeStringListDocumentWriter,
        CindelNativeObjectDocumentWriter {
  _CindelNativeDocumentWriter(this._functions, this._writer)
    : _stringBytes = _ReusableNativeBytes(256),
      _largeStringCache = LinkedHashMap<String, Uint8List>(),
      _fieldNamesCache = LinkedHashMap<List<String>, Uint8List>(),
      _ownsBuffers = true;

  _CindelNativeDocumentWriter._child(
    this._functions,
    this._writer,
    this._stringBytes,
    this._largeStringCache,
    this._fieldNamesCache,
  ) : _ownsBuffers = false;

  final _CindelNativeFunctions _functions;
  final Pointer<Void> _writer;
  final _ReusableNativeBytes _stringBytes;
  final LinkedHashMap<String, Uint8List> _largeStringCache;
  final LinkedHashMap<List<String>, Uint8List> _fieldNamesCache;
  final bool _ownsBuffers;

  @override
  void writeNull(int fieldIndex) {
    _functions.nativeBatchWriterWriteNull(_writer, fieldIndex);
  }

  @override
  void writeBool(int fieldIndex, bool value) {
    _functions.nativeBatchWriterWriteBool(_writer, fieldIndex, value);
  }

  @override
  void writeInt(int fieldIndex, int value) {
    _functions.nativeBatchWriterWriteInt(_writer, fieldIndex, value);
  }

  @override
  void writeDouble(int fieldIndex, double value) {
    _functions.nativeBatchWriterWriteDouble(_writer, fieldIndex, value);
  }

  @override
  void writeString(int fieldIndex, String value) {
    final cachedBytes = _cachedLargeStringBytes(value);
    final write = (Pointer<Uint8> pointer, int length) {
      _functions.nativeBatchWriterWriteBytes(
        _writer,
        fieldIndex,
        pointer,
        length,
      );
    };
    if (cachedBytes == null) {
      _stringBytes.withUtf8String(value, write);
    } else {
      _stringBytes.withBytes(cachedBytes, write);
    }
  }

  @override
  void writeStringList(int fieldIndex, List<String> value) {
    _stringBytes.withCompactStringList(value, (pointer, length) {
      _functions.nativeBatchWriterWriteBytes(
        _writer,
        fieldIndex,
        pointer,
        length,
      );
    });
  }

  @override
  void writeObject(int fieldIndex, Map<String, Object?> value) {
    final bytes = cindelEncodeBinaryObject(value);
    _stringBytes.withBytes(bytes, (pointer, length) {
      _functions.nativeBatchWriterWriteBytes(
        _writer,
        fieldIndex,
        pointer,
        length,
      );
    });
  }

  @override
  void writeObjectList(int fieldIndex, List<Map<String, Object?>?> value) {
    final bytes = cindelEncodeBinaryList(value);
    _stringBytes.withBytes(bytes, (pointer, length) {
      _functions.nativeBatchWriterWriteBytes(
        _writer,
        fieldIndex,
        pointer,
        length,
      );
    });
  }

  @override
  CindelNativeDocumentWriter beginList(int fieldIndex, int length) {
    final writer = _functions.nativeBatchWriterBeginList(
      _writer,
      fieldIndex,
      length,
    );
    if (writer == nullptr) {
      throw StateError('Native Cindel list writer allocation failed.');
    }
    return _CindelNativeDocumentWriter._child(
      _functions,
      writer,
      _stringBytes,
      _largeStringCache,
      _fieldNamesCache,
    );
  }

  @override
  void endList(CindelNativeDocumentWriter listWriter) {
    if (listWriter is! _CindelNativeDocumentWriter) {
      throw ArgumentError.value(
        listWriter,
        'listWriter',
        'Must be a Cindel native list writer.',
      );
    }
    _functions.nativeBatchWriterEndList(_writer, listWriter._writer);
    listWriter.release();
  }

  @override
  CindelNativeDocumentWriter beginObject(
    int fieldIndex,
    List<String> fieldNames,
  ) {
    final fieldNamesBytes = _cachedFieldNamesBytes(fieldNames);
    final writer = _withNativeBytes(fieldNamesBytes, (pointer, length) {
      return _functions.nativeBatchWriterBeginObject(
        _writer,
        fieldIndex,
        pointer,
        length,
      );
    });
    if (writer == nullptr) {
      throw StateError('Native Cindel object writer allocation failed.');
    }
    return _CindelNativeDocumentWriter._child(
      _functions,
      writer,
      _stringBytes,
      _largeStringCache,
      _fieldNamesCache,
    );
  }

  @override
  void endObject(CindelNativeDocumentWriter objectWriter) {
    if (objectWriter is! _CindelNativeDocumentWriter) {
      throw ArgumentError.value(
        objectWriter,
        'objectWriter',
        'Must be a Cindel native object writer.',
      );
    }
    _functions.nativeBatchWriterEndObject(_writer, objectWriter._writer);
    objectWriter.release();
  }

  void release() {
    if (_ownsBuffers) {
      _stringBytes.free();
    }
  }

  Uint8List? _cachedLargeStringBytes(String value) {
    if (value.length < 128) {
      return null;
    }
    final existing = _largeStringCache[value];
    if (existing != null) {
      return existing;
    }
    final bytes = Uint8List.fromList(utf8.encode(value));
    if (_largeStringCache.length >= 8) {
      _largeStringCache.remove(_largeStringCache.keys.first);
    }
    _largeStringCache[value] = bytes;
    return bytes;
  }

  Uint8List _cachedFieldNamesBytes(List<String> fieldNames) {
    final existing = _fieldNamesCache[fieldNames];
    if (existing != null) {
      return existing;
    }
    final bytes = _encodeNativeFieldNames(fieldNames);
    if (_fieldNamesCache.length >= 16) {
      _fieldNamesCache.remove(_fieldNamesCache.keys.first);
    }
    _fieldNamesCache[fieldNames] = bytes;
    return bytes;
  }
}
