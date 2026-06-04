part of 'bindings.dart';

final class _CindelNativeDocumentReader implements CindelNativeDocumentReader {
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
