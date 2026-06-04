part of 'bindings.dart';

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

  @override
  int get length => _functions.nativeDocumentReaderLen(_reader);

  @override
  bool isPresent(int documentIndex) {
    return _functions.nativeDocumentReaderIsPresent(_reader, documentIndex);
  }

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

  @override
  Map<String, Object?>? readObject(int documentIndex, int fieldIndex) {
    if (!_readBytes(documentIndex, fieldIndex)) {
      return null;
    }
    final bytes = _bytesPointer.value.asTypedList(_bytesLength.value);
    return cindelDecodeBinaryObject(Uint8List.fromList(bytes));
  }

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
