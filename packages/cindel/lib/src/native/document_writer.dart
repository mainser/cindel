part of 'bindings.dart';

// Runtime implementation of the generated native document writer API.
//
// A writer wraps one native batch-writer handle. Generated schemas call this
// through `CindelNativeDocumentWriter` to write scalar fields, compact
// string-list payloads, embedded objects, and list/object child writers without
// constructing full Dart-side binary documents first.
final class _CindelNativeDocumentWriter
    implements
        CindelNativeStringListDocumentWriter,
        CindelNativeObjectDocumentWriter {
  _CindelNativeDocumentWriter(this._functions, this._writer)
    : _stringBytes = _ReusableNativeBytes(256),
      _largeStringCache = LinkedHashMap<String, Uint8List>(),
      _fieldNamesCache = LinkedHashMap<List<String>, Uint8List>(),
      _ownsBuffers = true;

  // Child writers represent a nested list or embedded object. They share the
  // parent's reusable buffers and caches, and are closed by `endList` /
  // `endObject` on the parent writer.
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

  /// Writes a null field value.
  @override
  void writeNull(int fieldIndex) {
    _functions.nativeBatchWriterWriteNull(_writer, fieldIndex);
  }

  /// Writes a boolean field value.
  @override
  void writeBool(int fieldIndex, bool value) {
    _functions.nativeBatchWriterWriteBool(_writer, fieldIndex, value);
  }

  /// Writes an integer field value.
  @override
  void writeInt(int fieldIndex, int value) {
    _functions.nativeBatchWriterWriteInt(_writer, fieldIndex, value);
  }

  /// Writes a double field value.
  @override
  void writeDouble(int fieldIndex, double value) {
    _functions.nativeBatchWriterWriteDouble(_writer, fieldIndex, value);
  }

  /// Writes a string field value.
  ///
  /// Short ASCII strings are copied directly through the reusable scratch
  /// buffer. Large strings are cached as UTF-8 bytes for the duration of this
  /// writer because generated serializers often write repeated values in a
  /// batch.
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

  /// Writes a string-list field value using Cindel's compact native list
  /// payload.
  @override
  void writeStringList(int fieldIndex, List<String> value) {
    _stringBytes.withCompactStringList(value, (pointer, length) {
      _functions.nativeBatchWriterWriteListBytes(
        _writer,
        fieldIndex,
        pointer,
        length,
      );
    });
  }

  /// Writes an embedded object field as a binary object payload.
  @override
  void writeObject(int fieldIndex, Map<String, Object?> value) {
    final bytes = cindelEncodeBinaryObject(value);
    _stringBytes.withBytes(bytes, (pointer, length) {
      _functions.nativeBatchWriterWriteObjectBytes(
        _writer,
        fieldIndex,
        pointer,
        length,
      );
    });
  }

  /// Writes a list of embedded objects as a binary list payload.
  @override
  void writeObjectList(int fieldIndex, List<Map<String, Object?>?> value) {
    final bytes = cindelEncodeBinaryList(value);
    _stringBytes.withBytes(bytes, (pointer, length) {
      _functions.nativeBatchWriterWriteListBytes(
        _writer,
        fieldIndex,
        pointer,
        length,
      );
    });
  }

  /// Starts a nested list writer for [fieldIndex].
  ///
  /// The returned writer must be passed back to [endList] on this parent writer.
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

  /// Finishes a nested list writer started by [beginList].
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

  /// Starts an embedded object writer for [fieldIndex].
  ///
  /// [fieldNames] describes the object's generated field layout and is encoded
  /// once, then cached for repeated embedded object writes.
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

  /// Finishes an embedded object writer started by [beginObject].
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

  // Releases Dart-owned reusable buffers. The native batch writer itself is
  // finished or aborted by `CindelNativeBindings`.
  void release() {
    if (_ownsBuffers) {
      _stringBytes.free();
    }
  }

  // Cache UTF-8 bytes for large strings only. Small values are cheaper to encode
  // through the reusable ASCII/UTF-8 scratch path than to store in the cache.
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

  // Cache encoded embedded-object field layouts for repeated generated object
  // writes in the same batch.
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
