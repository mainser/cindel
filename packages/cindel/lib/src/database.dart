import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'native/bindings.dart';

class CindelDatabase {
  CindelDatabase._({
    required this.directory,
    required CindelNativeBindings bindings,
    required Pointer<Void> handle,
  }) : _bindings = bindings,
       _handle = handle;

  final String directory;
  final CindelNativeBindings _bindings;
  Pointer<Void>? _handle;

  static Future<CindelDatabase> open({required String directory}) async {
    const bindings = CindelNativeBindings();
    final handle = bindings.open(directory);
    if (handle == nullptr) {
      throw StateError('Failed to open Cindel native engine.');
    }
    return CindelDatabase._(
      directory: directory,
      bindings: bindings,
      handle: handle,
    );
  }

  Future<void> close() async {
    final handle = _handle;
    if (handle == null) {
      return;
    }
    _bindings.close(handle);
    _handle = null;
  }

  Future<void> put(
    String collection,
    int id,
    Map<String, Object?> value,
  ) async {
    final handle = _checkOpen();
    final bytes = Uint8List.fromList(utf8.encode(jsonEncode(value)));
    _bindings.put(handle, collection, id, bytes);
  }

  Future<Map<String, Object?>?> get(String collection, int id) async {
    final handle = _checkOpen();
    final bytes = _bindings.get(handle, collection, id);
    if (bytes == null) {
      return null;
    }

    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map) {
      throw StateError('Native Cindel returned a non-object document.');
    }
    return decoded.cast<String, Object?>();
  }

  Future<void> delete(String collection, int id) async {
    final handle = _checkOpen();
    _bindings.delete(handle, collection, id);
  }

  Pointer<Void> _checkOpen() {
    final handle = _handle;
    if (handle == null) {
      throw StateError('CindelDatabase is closed.');
    }
    return handle;
  }
}
