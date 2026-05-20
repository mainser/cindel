import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'native/bindings.dart';

/// A JSON-like document accepted by Cindel's manual API.
typedef CindelDocument = Map<String, Object?>;

const _maximumSqliteId = 0x7FFFFFFFFFFFFFFF;

/// An open handle to a local Cindel database.
class CindelDatabase {
  CindelDatabase._({
    required this.directory,
    required CindelNativeBindings bindings,
    required Pointer<Void> handle,
  }) : _bindings = bindings,
       _handle = handle;

  /// The directory where the database files are stored.
  final String directory;
  final CindelNativeBindings _bindings;
  Pointer<Void>? _handle;

  /// Opens a database stored under [directory].
  ///
  /// Throws an [ArgumentError] when [directory] is empty and a [StateError] when
  /// the native engine cannot be opened.
  static Future<CindelDatabase> open({required String directory}) async {
    _checkDirectory(directory);

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

  /// Closes this database.
  ///
  /// Calling [close] more than once is safe.
  Future<void> close() async {
    final handle = _handle;
    if (handle == null) {
      return;
    }
    _bindings.close(handle);
    _handle = null;
  }

  /// Stores [value] in [collection] under [id].
  ///
  /// Throws an [ArgumentError] when [collection], [id], or [value] is invalid.
  /// Throws a [StateError] when this database is already closed or the native
  /// write fails.
  Future<void> put(String collection, int id, CindelDocument value) async {
    final handle = _checkOpen();
    _checkCollection(collection);
    _checkId(id);
    _checkDocument(value);

    final bytes = _encodeDocument(value);
    _bindings.put(handle, collection, id, bytes);
  }

  /// Returns the document stored in [collection] under [id], or `null`.
  ///
  /// Throws an [ArgumentError] when [collection] or [id] is invalid. Throws a
  /// [StateError] when this database is already closed or the native read
  /// returns invalid data.
  Future<CindelDocument?> get(String collection, int id) async {
    final handle = _checkOpen();
    _checkCollection(collection);
    _checkId(id);

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

  /// Deletes the document stored in [collection] under [id], if it exists.
  ///
  /// Throws an [ArgumentError] when [collection] or [id] is invalid. Throws a
  /// [StateError] when this database is already closed or the native delete
  /// fails.
  Future<void> delete(String collection, int id) async {
    final handle = _checkOpen();
    _checkCollection(collection);
    _checkId(id);

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

Uint8List _encodeDocument(CindelDocument value) {
  return Uint8List.fromList(utf8.encode(jsonEncode(value)));
}

void _checkDirectory(String directory) {
  if (directory.trim().isEmpty) {
    throw ArgumentError.value(directory, 'directory', 'Must not be empty.');
  }
}

void _checkCollection(String collection) {
  if (collection.trim().isEmpty) {
    throw ArgumentError.value(collection, 'collection', 'Must not be empty.');
  }
}

void _checkId(int id) {
  if (id < 0) {
    throw ArgumentError.value(id, 'id', 'Must be greater than or equal to 0.');
  }
  if (id > _maximumSqliteId) {
    throw ArgumentError.value(
      id,
      'id',
      'Must be less than or equal to $_maximumSqliteId.',
    );
  }
}

void _checkDocument(CindelDocument value) {
  for (final entry in value.entries) {
    _checkJsonValue(entry.value, 'value.${entry.key}');
  }
}

void _checkJsonValue(Object? value, String path) {
  switch (value) {
    case null || String() || bool():
      return;
    case int():
      return;
    case double() when value.isFinite:
      return;
    case List<Object?>():
      for (var index = 0; index < value.length; index += 1) {
        _checkJsonValue(value[index], '$path[$index]');
      }
      return;
    case Map<String, Object?>():
      for (final entry in value.entries) {
        _checkJsonValue(entry.value, '$path.${entry.key}');
      }
      return;
    default:
      throw ArgumentError.value(
        value,
        path,
        'Must be a JSON-compatible value.',
      );
  }
}
