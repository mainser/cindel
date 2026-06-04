part of 'bindings.dart';

T _withNativeUtf8Bytes<T>(
  String value,
  T Function(Pointer<Uint8> pointer, int length) action,
) {
  return _withNativeBytes(Uint8List.fromList(utf8.encode(value)), action);
}

T _withNativeBytes<T>(
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

T _withNullableNativeBytes<T>(
  Uint8List? bytes,
  T Function(Pointer<Uint8> pointer, int length) action,
) {
  if (bytes == null) {
    return action(nullptr, 0);
  }
  return _withNativeBytes(bytes, action);
}

Uint8List _encodeNativeFieldNames(List<String> fieldNames) {
  final encodedNames = [for (final name in fieldNames) utf8.encode(name)];
  final length =
      4 + encodedNames.fold<int>(0, (sum, name) => sum + 4 + name.length);
  final bytes = Uint8List(length);
  final data = bytes.buffer.asByteData();
  data.setUint32(0, encodedNames.length, Endian.little);
  var offset = 4;
  for (final name in encodedNames) {
    data.setUint32(offset, name.length, Endian.little);
    offset += 4;
    bytes.setRange(offset, offset + name.length, name);
    offset += name.length;
  }
  return bytes;
}

List<int> _queryIds(
  int Function(Pointer<Pointer<Uint8>> outPointer, Pointer<Size> outLength)
  action,
  void Function(Pointer<Uint8> pointer, int length) freeBuffer,
  String operation,
) {
  final bytes = _queryBytes(action, freeBuffer, operation);
  try {
    return decodeIdList(bytes);
  } on FormatException {
    throw StateError('Native Cindel returned invalid binary id list.');
  } catch (_) {
    throw StateError('Native Cindel returned invalid binary id list.');
  }
}

Uint8List _queryBytes(
  int Function(Pointer<Pointer<Uint8>> outPointer, Pointer<Size> outLength)
  action,
  void Function(Pointer<Uint8> pointer, int length) freeBuffer,
  String operation,
) {
  final outPointer = calloc<Pointer<Uint8>>();
  final outLength = calloc<Size>();
  try {
    final status = action(outPointer, outLength);
    _checkStatus(status, operation);

    final pointer = outPointer.value;
    final length = outLength.value;
    final bytes = Uint8List.fromList(pointer.asTypedList(length));
    freeBuffer(pointer, length);
    return bytes;
  } finally {
    calloc
      ..free(outPointer)
      ..free(outLength);
  }
}

Uint8List _queryPlanBytes(
  Pointer<Void> handle,
  String collection,
  Uint8List plan,
  int Function(_QueryPlanCallArgs args) action,
  void Function(Pointer<Uint8> pointer, int length) freeBuffer,
  String operation,
) {
  return _withNativeUtf8Bytes(collection, (
    collectionPointer,
    collectionLength,
  ) {
    return _withNativeBytes(plan, (planPointer, planLength) {
      return _queryBytes(
        (outPointer, outLength) {
          return action(
            _QueryPlanCallArgs(
              handle: handle,
              collectionPointer: collectionPointer,
              collectionLength: collectionLength,
              planPointer: planPointer,
              planLength: planLength,
              outPointer: outPointer,
              outLength: outLength,
            ),
          );
        },
        freeBuffer,
        operation,
      );
    });
  });
}

final class _QueryPlanCallArgs {
  const _QueryPlanCallArgs({
    required this.handle,
    required this.collectionPointer,
    required this.collectionLength,
    required this.planPointer,
    required this.planLength,
    required this.outPointer,
    required this.outLength,
  });

  final Pointer<Void> handle;
  final Pointer<Uint8> collectionPointer;
  final int collectionLength;
  final Pointer<Uint8> planPointer;
  final int planLength;
  final Pointer<Pointer<Uint8>> outPointer;
  final Pointer<Size> outLength;
}

void _checkId(int id) {
  if (id < 0) {
    throw ArgumentError.value(id, 'id', 'Must be greater than or equal to 0.');
  }
}

void _checkStatus(int status, String operation) {
  if (status != 0) {
    throw StateError('Native Cindel $operation failed.');
  }
}
