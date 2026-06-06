part of 'bindings.dart';

// Runtime implementation of the generated native document reader API.
//
// Native storage exposes either indexed result sets or streaming query cursors.
// When `_useCurrentDocument` is true, the normal public `readX(documentIndex,
// fieldIndex)` methods dispatch to native `readCurrentX` functions and ignore
// `documentIndex`; this keeps generated hydrators unchanged while allowing
// streaming readers to avoid current-row lookups by index.
final class _CindelNativeDocumentReader
    implements CindelNativeDocumentReader, CindelNativeObjectDocumentReader {
  _CindelNativeDocumentReader(
    this._functions,
    this._reader, {
    bool useCurrentDocument = false,
  }) : _useCurrentDocument = useCurrentDocument,
       _boolValue = calloc<Bool>(),
       _intValue = calloc<Int64>(),
       _doubleValue = calloc<Double>(),
       _bytesPointer = calloc<Pointer<Uint8>>(),
       _bytesLength = calloc<Size>(),
       _stringIsAscii = calloc<Bool>(),
       _stringInternId = calloc<Uint64>(),
       _idValue = calloc<Uint64>(),
       _fieldNamesCache = LinkedHashMap<List<String>, Uint8List>(),
       _ownsScratch = true;

  // Child readers represent list or embedded-object fields. They own their
  // native reader handle but share the parent's scratch pointers and field-name
  // cache, so they must not outlive the parent reader.
  _CindelNativeDocumentReader._child(
    this._functions,
    this._reader,
    _CindelNativeDocumentReader parent,
  ) : _useCurrentDocument = false,
      _boolValue = parent._boolValue,
      _intValue = parent._intValue,
      _doubleValue = parent._doubleValue,
      _bytesPointer = parent._bytesPointer,
      _bytesLength = parent._bytesLength,
      _stringIsAscii = parent._stringIsAscii,
      _stringInternId = parent._stringInternId,
      _idValue = parent._idValue,
      _fieldNamesCache = parent._fieldNamesCache,
      _ownsScratch = false;

  final _CindelNativeFunctions _functions;
  final Pointer<Void> _reader;
  final bool _useCurrentDocument;
  final Pointer<Bool> _boolValue;
  final Pointer<Int64> _intValue;
  final Pointer<Double> _doubleValue;
  final Pointer<Pointer<Uint8>> _bytesPointer;
  final Pointer<Size> _bytesLength;
  final Pointer<Bool> _stringIsAscii;
  final Pointer<Uint64> _stringInternId;
  final Pointer<Uint64> _idValue;
  final LinkedHashMap<List<String>, Uint8List> _fieldNamesCache;
  final bool _ownsScratch;
  bool _released = false;

  /// Number of documents or list items exposed by this reader.
  @override
  int get length => _functions.nativeDocumentReaderLen(_reader);

  /// Whether [documentIndex] contains a stored document.
  @override
  bool isPresent(int documentIndex) {
    return _functions.nativeDocumentReaderIsPresent(_reader, documentIndex);
  }

  /// Reads the external document id.
  ///
  /// Native uses `_nativeReaderNullId` when an id is unavailable; generated
  /// schemas expect ids to be present, so that state is surfaced as an error.
  @override
  int readId(int documentIndex) {
    final value = _useCurrentDocument
        ? _functions.nativeDocumentReaderReadCurrentIdValue(_reader)
        : _functions.nativeDocumentReaderReadIdValue(_reader, documentIndex);
    if (value == _nativeReaderNullId) {
      throw StateError('Native Cindel document id is not available.');
    }
    return value;
  }

  /// Reads a nullable boolean field.
  @override
  bool? readBool(int documentIndex, int fieldIndex) {
    final value = _useCurrentDocument
        ? _functions.nativeDocumentReaderReadCurrentBoolValue(
            _reader,
            fieldIndex,
          )
        : _functions.nativeDocumentReaderReadBoolValue(
            _reader,
            documentIndex,
            fieldIndex,
          );
    return switch (value) {
      0 => false,
      1 => true,
      _ => null,
    };
  }

  /// Reads a nullable integer field.
  @override
  int? readInt(int documentIndex, int fieldIndex) {
    final value = _useCurrentDocument
        ? _functions.nativeDocumentReaderReadCurrentIntValue(
            _reader,
            fieldIndex,
          )
        : _functions.nativeDocumentReaderReadIntValue(
            _reader,
            documentIndex,
            fieldIndex,
          );
    if (value == _nativeReaderNullInt) {
      return null;
    }
    return value;
  }

  /// Reads a nullable double field.
  ///
  /// Native uses NaN as the nullable sentinel for doubles.
  @override
  double? readDouble(int documentIndex, int fieldIndex) {
    final value = _useCurrentDocument
        ? _functions.nativeDocumentReaderReadCurrentDoubleValue(
            _reader,
            fieldIndex,
          )
        : _functions.nativeDocumentReaderReadDoubleValue(
            _reader,
            documentIndex,
            fieldIndex,
          );
    if (value.isNaN) {
      return null;
    }
    return value;
  }

  /// Reads a nullable string field and decodes the borrowed native bytes
  /// immediately into a Dart-owned [String].
  @override
  String? readString(int documentIndex, int fieldIndex) {
    final length = _useCurrentDocument
        ? _functions.nativeDocumentReaderReadCurrentStringValue(
            _reader,
            fieldIndex,
            _bytesPointer,
            _stringIsAscii,
          )
        : _functions.nativeDocumentReaderReadStringValue(
            _reader,
            documentIndex,
            fieldIndex,
            _bytesPointer,
            _stringIsAscii,
          );
    if (_bytesPointer.value == nullptr) {
      return null;
    }
    final bytes = _bytesPointer.value.asTypedList(length);
    return _decodeNativeString(bytes, isAscii: _stringIsAscii.value);
  }

  /// Reads a nullable string-list field.
  ///
  /// The native payload may be compact offsets, a versioned native list, or a
  /// legacy JSON fallback; decoding is centralized in `_decodeNativeStringList`.
  @override
  List<String>? readStringList(int documentIndex, int fieldIndex) {
    final ok = _useCurrentDocument
        ? _functions.nativeDocumentReaderReadCurrentListBytes(
            _reader,
            fieldIndex,
            _bytesPointer,
            _bytesLength,
          )
        : _functions.nativeDocumentReaderReadListBytes(
            _reader,
            documentIndex,
            fieldIndex,
            _bytesPointer,
            _bytesLength,
          );
    if (!ok) {
      return null;
    }
    final bytes = _bytesPointer.value.asTypedList(_bytesLength.value);
    return _decodeNativeStringList(bytes);
  }

  /// Reads an embedded object stored as binary object bytes.
  @override
  Map<String, Object?>? readObject(int documentIndex, int fieldIndex) {
    if (!_readBytes(documentIndex, fieldIndex)) {
      return null;
    }
    final bytes = _bytesPointer.value.asTypedList(_bytesLength.value);
    return cindelDecodeBinaryObject(Uint8List.fromList(bytes));
  }

  /// Reads a list of embedded objects stored as a binary list payload.
  @override
  List<Map<String, Object?>?>? readObjectList(
    int documentIndex,
    int fieldIndex,
  ) {
    if (!_readBytes(documentIndex, fieldIndex)) {
      return null;
    }
    final bytes = _bytesPointer.value.asTypedList(_bytesLength.value);
    final values = cindelDecodeBinaryList(Uint8List.fromList(bytes));
    return values
        .map(
          (value) =>
              value == null ? null : (value as Map).cast<String, Object?>(),
        )
        .toList(growable: false);
  }

  /// Opens a child reader for a list field.
  ///
  /// The returned reader must be released by generated helper code when it is no
  /// longer needed.
  @override
  CindelNativeDocumentReader? readList(int documentIndex, int fieldIndex) {
    final listReader = _useCurrentDocument
        ? _functions.nativeDocumentReaderReadCurrentList(_reader, fieldIndex)
        : _functions.nativeDocumentReaderReadList(
            _reader,
            documentIndex,
            fieldIndex,
          );
    if (listReader == nullptr) {
      return null;
    }
    return _CindelNativeDocumentReader._child(_functions, listReader, this);
  }

  /// Opens a child reader for an embedded object using [fieldNames] as the
  /// expected object field layout.
  @override
  CindelNativeDocumentReader? readObjectReader(
    int documentIndex,
    int fieldIndex,
    List<String> fieldNames,
  ) {
    final fieldNamesBytes = _cachedFieldNamesBytes(fieldNames);
    final objectReader = _stringBytesWith(fieldNamesBytes, (pointer, length) {
      return _useCurrentDocument
          ? _functions.nativeDocumentReaderReadCurrentObject(
              _reader,
              fieldIndex,
              pointer,
              length,
            )
          : _functions.nativeDocumentReaderReadObject(
              _reader,
              documentIndex,
              fieldIndex,
              pointer,
              length,
            );
    });
    if (objectReader == nullptr) {
      return null;
    }
    return _CindelNativeDocumentReader._child(_functions, objectReader, this);
  }

  // Shared raw-byte read helper used by embedded object fallbacks.
  bool _readBytes(int documentIndex, int fieldIndex) {
    return _useCurrentDocument
        ? _functions.nativeDocumentReaderReadCurrentBytes(
            _reader,
            fieldIndex,
            _bytesPointer,
            _bytesLength,
          )
        : _functions.nativeDocumentReaderReadBytes(
            _reader,
            documentIndex,
            fieldIndex,
            _bytesPointer,
            _bytesLength,
          );
  }

  // Temporarily copies encoded field names into native memory for object-reader
  // calls. Native must not retain the pointer after [action] returns.
  T _stringBytesWith<T>(
    Uint8List bytes,
    T Function(Pointer<Uint8> pointer, int length) action,
  ) {
    final pointer = calloc<Uint8>(bytes.length);
    try {
      pointer.asTypedList(bytes.length).setAll(0, bytes);
      return action(pointer, bytes.length);
    } finally {
      calloc.free(pointer);
    }
  }

  // Caches encoded field-name layouts for generated embedded object readers.
  // The cache is intentionally small because generated schemas usually reuse a
  // handful of embedded layouts.
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

  /// Releases the native reader and any scratch memory owned by this wrapper.
  ///
  /// The method is idempotent so generated cleanup paths can call it defensively.
  @override
  void release() {
    if (_released) {
      return;
    }
    _released = true;
    _functions.nativeDocumentReaderFree(_reader);
    if (!_ownsScratch) {
      return;
    }
    calloc
      ..free(_boolValue)
      ..free(_intValue)
      ..free(_doubleValue)
      ..free(_bytesPointer)
      ..free(_bytesLength)
      ..free(_stringIsAscii)
      ..free(_stringInternId)
      ..free(_idValue);
  }
}
