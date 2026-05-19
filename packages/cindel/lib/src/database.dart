import 'dart:ffi';

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
    final handle = bindings.open();
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
    _checkOpen();
    // TODO: serialize and send a write command through FFI.
  }

  Future<Map<String, Object?>?> get(String collection, int id) async {
    _checkOpen();
    // TODO: query through FFI.
    return null;
  }

  Future<void> delete(String collection, int id) async {
    _checkOpen();
    // TODO: send a delete command through FFI.
  }

  void _checkOpen() {
    if (_handle == null) {
      throw StateError('CindelDatabase is closed.');
    }
  }
}
