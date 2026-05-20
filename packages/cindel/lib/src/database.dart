import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'native/bindings.dart';
import 'schema.dart';

/// A JSON-like document accepted by Cindel's manual API.
typedef CindelDocument = Map<String, Object?>;

const _maximumSqliteId = 0x7FFFFFFFFFFFFFFF;
const _defaultWatchPollInterval = Duration(milliseconds: 50);

/// An open handle to a local Cindel database.
class CindelDatabase {
  CindelDatabase._({
    required this.directory,
    required CindelNativeBindings bindings,
    required Pointer<Void> handle,
    required Map<String, CindelCollectionSchema<dynamic>> schemas,
  }) : _bindings = bindings,
       _handle = handle,
       _schemas = schemas;

  /// The directory where the database files are stored.
  final String directory;
  final CindelNativeBindings _bindings;
  final Map<String, CindelCollectionSchema<dynamic>> _schemas;
  final Map<String, Set<_RegisteredWatcher>> _watchersByCollection = {};
  Pointer<Void>? _handle;

  /// Opens a database stored under [directory].
  ///
  /// Throws an [ArgumentError] when [directory] is empty and a [StateError] when
  /// the native engine cannot be opened.
  static Future<CindelDatabase> open({
    required String directory,
    Iterable<CindelCollectionSchema<dynamic>> schemas = const [],
  }) async {
    _checkDirectory(directory);
    final schemasByCollection = _schemasByCollection(schemas);

    const bindings = CindelNativeBindings();
    final handle = bindings.open(directory);
    if (handle == nullptr) {
      throw StateError('Failed to open Cindel native engine.');
    }
    return CindelDatabase._(
      directory: directory,
      bindings: bindings,
      handle: handle,
      schemas: schemasByCollection,
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
    await _closeWatchers();
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
    final indexEntries = _indexEntriesFor(collection, value);
    if (indexEntries == null) {
      _bindings.put(handle, collection, id, bytes);
      _notifyWatchers(collection);
      return;
    }

    _bindings.putIndexed(
      handle,
      collection,
      id,
      bytes,
      _encodeIndexEntries(indexEntries),
    );
    _notifyWatchers(collection);
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
    _notifyWatchers(collection);
  }

  /// Watches the current value of a document and emits after committed changes.
  ///
  /// The stream emits the current snapshot first, then emits again whenever the
  /// native collection revision changes. Local writes notify watchers as soon as
  /// the native call returns, and [pollInterval] catches changes made by other
  /// database handles.
  Stream<CindelDocument?> watchDocument(
    String collection,
    int id, {
    Duration pollInterval = _defaultWatchPollInterval,
  }) {
    _checkOpen();
    _checkCollection(collection);
    _checkId(id);
    _checkPollInterval(pollInterval);

    return _watch(
      collection,
      pollInterval: pollInterval,
      readSnapshot: () => get(collection, id),
    );
  }

  /// Watches all documents in [collection] and emits after committed changes.
  ///
  /// Documents are emitted in id order. The stream emits a snapshot immediately
  /// and then reacts to native collection revision changes.
  Stream<List<CindelDocument>> watchCollection(
    String collection, {
    Duration pollInterval = _defaultWatchPollInterval,
  }) {
    _checkOpen();
    _checkCollection(collection);
    _checkPollInterval(pollInterval);

    return _watch(
      collection,
      pollInterval: pollInterval,
      readSnapshot: () async {
        final handle = _checkOpen();
        final ids = _bindings.documentIds(handle, collection);
        return _documentsByIds(collection, ids);
      },
    );
  }

  /// Returns documents whose indexed [field] equals [value].
  ///
  /// Throws an [ArgumentError] when the input is invalid. Throws a [StateError]
  /// when [collection] has no registered schema or [field] is not indexed.
  Future<List<CindelDocument>> queryEqual(
    String collection,
    String field,
    Object value,
  ) async {
    final handle = _checkOpen();
    _checkCollection(collection);
    _checkIndexName(field);
    final schemaField = _checkIndexedField(collection, field);
    final encodedValue = _encodeIndexValue(value, schemaField.dartType);

    final ids = _bindings.queryIndexEqual(
      handle,
      collection,
      field,
      encodedValue,
    );
    return _documentsByIds(collection, ids);
  }

  /// Returns documents whose indexed [field] is inside the inclusive range.
  ///
  /// At least one of [lower] or [upper] must be provided. Range queries support
  /// `int`, `double`, and `String` index values.
  Future<List<CindelDocument>> queryRange(
    String collection,
    String field, {
    Object? lower,
    Object? upper,
  }) async {
    final handle = _checkOpen();
    _checkCollection(collection);
    _checkIndexName(field);
    final schemaField = _checkIndexedField(collection, field);
    if (lower == null && upper == null) {
      throw ArgumentError.value(null, 'lower/upper', 'Must provide a bound.');
    }

    final encodedLower = lower == null
        ? null
        : _encodeRangeIndexValue(lower, schemaField.dartType, 'lower');
    final encodedUpper = upper == null
        ? null
        : _encodeRangeIndexValue(upper, schemaField.dartType, 'upper');
    _checkMatchingRangeBounds(encodedLower, encodedUpper);

    final ids = _bindings.queryIndexRange(
      handle,
      collection,
      field,
      encodedLower?.bytes,
      encodedUpper?.bytes,
    );
    return _documentsByIds(collection, ids);
  }

  Pointer<Void> _checkOpen() {
    final handle = _handle;
    if (handle == null) {
      throw StateError('CindelDatabase is closed.');
    }
    return handle;
  }

  List<_IndexEntry>? _indexEntriesFor(String collection, CindelDocument value) {
    final schema = _schemas[collection];
    if (schema == null) {
      return null;
    }

    final entries = <_IndexEntry>[];
    for (final field in schema.fields) {
      if (!field.isIndexed || !value.containsKey(field.name)) {
        continue;
      }
      final fieldValue = value[field.name];
      if (fieldValue == null) {
        continue;
      }
      entries.add(
        _IndexEntry(
          name: field.name,
          value: _indexValueJson(fieldValue, field.dartType),
        ),
      );
    }
    return entries;
  }

  CindelFieldSchema _checkIndexedField(String collection, String field) {
    final schema = _schemas[collection];
    if (schema == null) {
      throw StateError(
        'Collection `$collection` has no registered Cindel schema.',
      );
    }

    for (final schemaField in schema.fields) {
      if (schemaField.name == field && schemaField.isIndexed) {
        return schemaField;
      }
    }

    throw StateError('Field `$field` is not indexed for `$collection`.');
  }

  Future<List<CindelDocument>> _documentsByIds(
    String collection,
    List<int> ids,
  ) async {
    final documents = <CindelDocument>[];
    for (final id in ids) {
      final document = await get(collection, id);
      if (document != null) {
        documents.add(document);
      }
    }
    return documents;
  }

  Stream<T> _watch<T>(
    String collection, {
    required Duration pollInterval,
    required Future<T> Function() readSnapshot,
  }) {
    late final _CindelWatcher<T> watcher;
    watcher = _CindelWatcher<T>(
      pollInterval: pollInterval,
      readRevision: () {
        final handle = _handle;
        if (handle == null) {
          throw StateError('CindelDatabase is closed.');
        }
        return _bindings.collectionRevision(handle, collection);
      },
      readSnapshot: readSnapshot,
      onListen: () => _registerWatcher(collection, watcher),
      onCancel: () => _unregisterWatcher(collection, watcher),
    );
    return watcher.stream;
  }

  void _registerWatcher(String collection, _RegisteredWatcher watcher) {
    _watchersByCollection
        .putIfAbsent(collection, () => <_RegisteredWatcher>{})
        .add(watcher);
  }

  void _notifyWatchers(String collection) {
    final watchers = _watchersByCollection[collection];
    if (watchers == null) {
      return;
    }
    for (final watcher in List<_RegisteredWatcher>.of(watchers)) {
      unawaited(watcher.poll());
    }
  }

  void _unregisterWatcher(String collection, _RegisteredWatcher watcher) {
    final watchers = _watchersByCollection[collection];
    if (watchers == null) {
      return;
    }
    watchers.remove(watcher);
    if (watchers.isEmpty) {
      _watchersByCollection.remove(collection);
    }
  }

  Future<void> _closeWatchers() async {
    final watchers = [
      for (final collectionWatchers in _watchersByCollection.values)
        ...collectionWatchers,
    ];
    _watchersByCollection.clear();
    await Future.wait<void>([for (final watcher in watchers) watcher.close()]);
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

void _checkIndexName(String field) {
  if (field.trim().isEmpty) {
    throw ArgumentError.value(field, 'field', 'Must not be empty.');
  }
}

void _checkPollInterval(Duration pollInterval) {
  if (pollInterval <= Duration.zero) {
    throw ArgumentError.value(
      pollInterval,
      'pollInterval',
      'Must be greater than zero.',
    );
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

Map<String, CindelCollectionSchema<dynamic>> _schemasByCollection(
  Iterable<CindelCollectionSchema<dynamic>> schemas,
) {
  final schemasByCollection = <String, CindelCollectionSchema<dynamic>>{};
  for (final schema in schemas) {
    if (schemasByCollection.containsKey(schema.name)) {
      throw ArgumentError.value(
        schema.name,
        'schemas',
        'Collection schemas must be unique by name.',
      );
    }
    schemasByCollection[schema.name] = schema;
  }
  return Map.unmodifiable(schemasByCollection);
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

Uint8List _encodeIndexEntries(List<_IndexEntry> entries) {
  return Uint8List.fromList(
    utf8.encode(
      jsonEncode([
        for (final entry in entries) {'name': entry.name, 'value': entry.value},
      ]),
    ),
  );
}

Uint8List _encodeIndexValue(Object value, String dartType) {
  return _encodedIndexValue(value, dartType, 'value').bytes;
}

_EncodedIndexValue _encodeRangeIndexValue(
  Object value,
  String dartType,
  String argumentName,
) {
  final encoded = _encodedIndexValue(value, dartType, argumentName);
  if (encoded.kind == 'bool') {
    throw ArgumentError.value(
      value,
      argumentName,
      'Range queries support int, double, and String values.',
    );
  }
  return encoded;
}

_EncodedIndexValue _encodedIndexValue(
  Object value,
  String dartType,
  String argumentName,
) {
  final json = _indexValueJson(value, dartType, argumentName);
  return _EncodedIndexValue(
    kind: json['type']! as String,
    bytes: Uint8List.fromList(utf8.encode(jsonEncode(json))),
  );
}

Map<String, Object> _indexValueJson(
  Object value,
  String dartType, [
  String argumentName = 'value',
]) {
  final normalizedType = dartType.endsWith('?')
      ? dartType.substring(0, dartType.length - 1)
      : dartType;

  return switch ((normalizedType, value)) {
    ('bool', final bool value) => {'type': 'bool', 'value': value},
    ('int', final int value) => {
      'type': 'int',
      'value': _checkSqliteInteger(value, argumentName),
    },
    ('double', final double value) when value.isFinite => {
      'type': 'double',
      'value': value,
    },
    ('String', final String value) => {'type': 'string', 'value': value},
    ('double', final double value) => throw ArgumentError.value(
      value,
      argumentName,
      'Must be finite.',
    ),
    _ => throw ArgumentError.value(
      value,
      argumentName,
      'Must match indexed field type `$dartType`.',
    ),
  };
}

int _checkSqliteInteger(int value, String argumentName) {
  if (value < -0x8000000000000000 || value > _maximumSqliteId) {
    throw ArgumentError.value(
      value,
      argumentName,
      'Must fit in SQLite INTEGER range.',
    );
  }
  return value;
}

void _checkMatchingRangeBounds(
  _EncodedIndexValue? lower,
  _EncodedIndexValue? upper,
) {
  if (lower != null && upper != null && lower.kind != upper.kind) {
    throw ArgumentError.value(
      upper.kind,
      'upper',
      'Range bounds must have matching types.',
    );
  }
}

final class _IndexEntry {
  const _IndexEntry({required this.name, required this.value});

  final String name;
  final Map<String, Object> value;
}

final class _EncodedIndexValue {
  const _EncodedIndexValue({required this.kind, required this.bytes});

  final String kind;
  final Uint8List bytes;
}

abstract interface class _RegisteredWatcher {
  Future<void> poll({bool force});

  Future<void> close();
}

final class _CindelWatcher<T> implements _RegisteredWatcher {
  _CindelWatcher({
    required Duration pollInterval,
    required int Function() readRevision,
    required Future<T> Function() readSnapshot,
    required void Function() onListen,
    required void Function() onCancel,
  }) : _pollInterval = pollInterval,
       _readRevision = readRevision,
       _readSnapshot = readSnapshot,
       _onListen = onListen,
       _onCancel = onCancel {
    _controller = StreamController<T>(
      onListen: () {
        _onListen();
        unawaited(poll(force: true));
        _timer = Timer.periodic(_pollInterval, (_) => unawaited(poll()));
      },
      onCancel: () {
        _timer?.cancel();
        _onCancel();
      },
    );
  }

  final Duration _pollInterval;
  final int Function() _readRevision;
  final Future<T> Function() _readSnapshot;
  final void Function() _onListen;
  final void Function() _onCancel;

  late final StreamController<T> _controller;
  Timer? _timer;
  int? _lastRevision;
  bool _isPolling = false;

  Stream<T> get stream => _controller.stream;

  Future<void> poll({bool force = false}) async {
    if (_isPolling || _controller.isClosed) {
      return;
    }
    _isPolling = true;
    try {
      final revision = _readRevision();
      if (!force && revision == _lastRevision) {
        return;
      }
      _lastRevision = revision;
      final snapshot = await _readSnapshot();
      if (!_controller.isClosed) {
        _controller.add(snapshot);
      }
    } catch (error, stackTrace) {
      if (!_controller.isClosed) {
        _controller.addError(error, stackTrace);
      }
    } finally {
      _isPolling = false;
    }
  }

  Future<void> close() async {
    _timer?.cancel();
    await _controller.close();
  }
}
