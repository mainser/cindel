import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:cindel_annotations/cindel_annotations.dart';

import 'native/bindings.dart';
import 'schema.dart';
import 'text.dart';

/// A JSON-like document accepted by Cindel's manual API.
typedef CindelDocument = Map<String, Object?>;

const _maximumSqliteId = 0x7FFFFFFFFFFFFFFF;
const _inMemoryDirectory = ':memory:';

enum _TransactionMode { read, write }

/// Native storage backend used by a Cindel database.
enum CindelStorageBackend {
  /// SQLite is available as the secondary compatibility backend.
  sqlite,

  /// MDBX is the default backend for new Cindel databases.
  mdbx,
}

/// The storage backend used when callers do not pass an explicit backend.
const defaultCindelStorageBackend = CindelStorageBackend.mdbx;

extension on CindelStorageBackend {
  int get _nativeId {
    return switch (this) {
      CindelStorageBackend.sqlite => 0,
      CindelStorageBackend.mdbx => 1,
    };
  }
}

/// Default polling interval used by Cindel watchers.
const defaultCindelWatchPollInterval = Duration(milliseconds: 50);

/// An open handle to a local Cindel database.
class CindelDatabase {
  CindelDatabase._({
    required this.directory,
    required CindelNativeBindings bindings,
    required Pointer<Void> handle,
    required Map<String, CindelCollectionSchema<dynamic>> schemas,
    required this.backend,
  }) : _bindings = bindings,
       _handle = handle,
       _schemas = schemas;

  /// The directory where the database files are stored.
  final String directory;

  /// The native storage backend selected for this database handle.
  final CindelStorageBackend backend;

  final CindelNativeBindings _bindings;
  final Map<String, CindelCollectionSchema<dynamic>> _schemas;
  final Map<String, Set<_RegisteredWatcher>> _watchersByCollection = {};
  final Set<String> _changedCollectionsInTransaction = {};
  Pointer<Void>? _handle;
  _TransactionMode? _activeTransaction;

  /// Opens a database stored under [directory].
  ///
  /// Throws an [ArgumentError] when [directory] is empty and a [StateError] when
  /// the native engine cannot be opened.
  static Future<CindelDatabase> open({
    required String directory,
    Iterable<CindelCollectionSchema<dynamic>> schemas = const [],
    CindelStorageBackend backend = defaultCindelStorageBackend,
  }) async {
    _checkDirectory(directory);
    return _openUnchecked(
      directory: directory,
      schemas: schemas,
      backend: backend,
    );
  }

  /// Opens an in-memory database.
  ///
  /// Data is discarded when this database is closed.
  static Future<CindelDatabase> openInMemory({
    Iterable<CindelCollectionSchema<dynamic>> schemas = const [],
    CindelStorageBackend backend = defaultCindelStorageBackend,
  }) {
    return _openUnchecked(
      directory: _inMemoryDirectory,
      schemas: schemas,
      backend: backend,
    );
  }

  static Future<CindelDatabase> _openUnchecked({
    required String directory,
    required Iterable<CindelCollectionSchema<dynamic>> schemas,
    required CindelStorageBackend backend,
  }) async {
    final database = await _openRaw(
      directory: directory,
      schemas: schemas,
      backend: backend,
    );
    final schemasByCollection = database._schemas;
    final schemaManifest = schemasByCollection.isEmpty
        ? null
        : _encodeSchemaManifest(schemasByCollection.values);
    try {
      if (schemaManifest != null) {
        database._bindings.registerSchemas(
          database._checkOpen(),
          schemaManifest,
        );
      }
    } catch (_) {
      await database.close();
      rethrow;
    }
    return database;
  }

  static Future<CindelDatabase> _openRaw({
    required String directory,
    required Iterable<CindelCollectionSchema<dynamic>> schemas,
    required CindelStorageBackend backend,
  }) async {
    final schemasByCollection = _schemasByCollection(schemas);

    final bindings = CindelNativeBindings();
    final handle = bindings.open(directory, backend: backend._nativeId);
    if (handle == nullptr) {
      throw StateError(
        'Failed to open Cindel native engine with backend `${backend.name}`.',
      );
    }
    return CindelDatabase._(
      directory: directory,
      backend: backend,
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
    if (_activeTransaction != null) {
      _bindings.rollbackTransaction(handle);
      _activeTransaction = null;
      _changedCollectionsInTransaction.clear();
    }
    await _closeWatchers();
    _bindings.close(handle);
    _handle = null;
  }

  /// Runs [action] inside a native read transaction.
  ///
  /// Read transactions provide a consistent snapshot for the reads performed by
  /// this database handle. Write operations inside [readTxn] throw [StateError].
  Future<T> readTxn<T>(Future<T> Function() action) {
    return _runTransaction(_TransactionMode.read, action);
  }

  /// Runs [action] inside a native write transaction.
  ///
  /// All writes performed by this database handle are committed together. If
  /// [action] throws, native changes are rolled back and watchers are not
  /// notified.
  Future<T> writeTxn<T>(Future<T> Function() action) {
    return _runTransaction(_TransactionMode.write, action);
  }

  /// Stores [value] in [collection] under [id].
  ///
  /// Throws an [ArgumentError] when [collection], [id], or [value] is invalid.
  /// Throws a [StateError] when this database is already closed or the native
  /// write fails.
  Future<void> put(String collection, int id, CindelDocument value) async {
    final handle = _checkOpen();
    _checkCanWrite();
    _checkCollection(collection);
    _checkId(id);
    _checkDocument(value);

    final bytes = _encodeDocument(value);
    final indexEntries = _indexEntriesFor(collection, value);
    if (indexEntries == null) {
      _bindings.put(handle, collection, id, bytes);
      _markCollectionChanged(collection);
      return;
    }
    await _checkUniqueIndexes(collection, {id: value}, indexEntries);

    _bindings.putIndexed(
      handle,
      collection,
      id,
      bytes,
      _encodeIndexEntries(indexEntries),
    );
    _markCollectionChanged(collection);
  }

  /// Stores every document in [values] atomically.
  ///
  /// All documents are committed in one native transaction. If validation or the
  /// native write fails, none of the documents are persisted.
  Future<void> putAll(
    String collection,
    Map<int, CindelDocument> values,
  ) async {
    final handle = _checkOpen();
    _checkCanWrite();
    _checkCollection(collection);
    if (values.isEmpty) {
      return;
    }

    final documents = <_BatchPutEntry>[];
    for (final entry in values.entries) {
      _checkId(entry.key);
      _checkDocument(entry.value);
      documents.add(
        _BatchPutEntry(
          id: entry.key,
          document: entry.value,
          indexes: _indexEntriesFor(collection, entry.value) ?? const [],
        ),
      );
    }
    await _checkUniqueBatchIndexes(collection, values, documents);

    _bindings.putManyIndexed(
      handle,
      collection,
      _encodeBatchPutEntries(documents),
    );
    _markCollectionChanged(collection);
  }

  /// Stores one generated binary document.
  ///
  /// This is intended for generated typed collections when the selected
  /// backend can index and read Cindel's binary document format directly.
  Future<void> putBinaryDocument(
    String collection,
    int id,
    Uint8List bytes,
  ) async {
    final handle = _checkOpen();
    _checkCanWrite();
    _checkBinaryBackend();
    _checkCollection(collection);
    _checkId(id);

    _bindings.putIndexed(handle, collection, id, bytes, Uint8List(0));
    _markCollectionChanged(collection);
  }

  /// Stores generated binary documents atomically.
  Future<void> putAllBinaryDocuments(
    String collection,
    Map<int, Uint8List> values,
  ) async {
    final handle = _checkOpen();
    _checkCanWrite();
    _checkBinaryBackend();
    _checkCollection(collection);
    if (values.isEmpty) {
      return;
    }
    for (final id in values.keys) {
      _checkId(id);
    }

    _bindings.putManyStored(
      handle,
      collection,
      _encodeBinaryBatchPutEntries(values),
    );
    _markCollectionChanged(collection);
  }

  /// Stores many documents atomically.
  ///
  /// Alias for [putAll], provided for APIs that prefer `many` naming.
  Future<void> putMany(String collection, Map<int, CindelDocument> values) {
    return putAll(collection, values);
  }

  /// Allocates the next native auto-increment id for [collection].
  ///
  /// The returned id is persisted by the native engine before this method
  /// completes, so reopened databases continue from the next value.
  Future<int> allocateId(String collection) async {
    final handle = _checkOpen();
    _checkCanWrite();
    _checkCollection(collection);
    return _bindings.allocateId(handle, collection);
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

  /// Returns raw generated binary document bytes, or `null`.
  Future<Uint8List?> getBinaryDocument(String collection, int id) async {
    final handle = _checkOpen();
    _checkBinaryBackend();
    _checkCollection(collection);
    _checkId(id);

    return _bindings.getStored(handle, collection, id);
  }

  /// Returns the documents stored under [ids], preserving input order.
  ///
  /// Missing documents are returned as `null`.
  Future<List<CindelDocument?>> getAll(
    String collection,
    Iterable<int> ids,
  ) async {
    final handle = _checkOpen();
    _checkCollection(collection);
    final idList = ids.toList(growable: false);
    for (final id in idList) {
      _checkId(id);
    }

    return _documentsByIdsNullable(handle, collection, idList);
  }

  /// Returns raw generated binary document bytes, preserving input order.
  Future<List<Uint8List?>> getAllBinaryDocuments(
    String collection,
    Iterable<int> ids,
  ) async {
    final handle = _checkOpen();
    _checkBinaryBackend();
    _checkCollection(collection);
    final idList = ids.toList(growable: false);
    for (final id in idList) {
      _checkId(id);
    }
    if (idList.isEmpty) {
      return const <Uint8List?>[];
    }

    final bytes = _bindings.getManyStored(
      handle,
      collection,
      _encodeIds(idList),
    );
    return _decodeBinaryDocumentBatch(bytes);
  }

  /// Returns every document in [collection], ordered by id.
  Future<List<CindelDocument>> queryAll(String collection) async {
    final handle = _checkOpen();
    _checkCollection(collection);

    final ids = _bindings.documentIds(handle, collection);
    return _documentsByIds(collection, ids);
  }

  /// Returns documents stored under [ids], preserving input order.
  Future<List<CindelDocument>> documentsByIds(
    String collection,
    Iterable<int> ids,
  ) async {
    _checkOpen();
    _checkCollection(collection);
    final idList = ids.toList(growable: false);
    for (final id in idList) {
      _checkId(id);
    }
    return _documentsByIds(collection, idList);
  }

  /// Returns every id in [collection], ordered ascending.
  Future<List<int>> documentIds(String collection) async {
    final handle = _checkOpen();
    _checkCollection(collection);

    return _bindings.documentIds(handle, collection);
  }

  /// Deletes the document stored in [collection] under [id], if it exists.
  ///
  /// Throws an [ArgumentError] when [collection] or [id] is invalid. Throws a
  /// [StateError] when this database is already closed or the native delete
  /// fails.
  Future<void> delete(String collection, int id) async {
    final handle = _checkOpen();
    _checkCanWrite();
    _checkCollection(collection);
    _checkId(id);

    _bindings.delete(handle, collection, id);
    _markCollectionChanged(collection);
  }

  /// Deletes every document under [ids] atomically.
  Future<void> deleteAll(String collection, Iterable<int> ids) async {
    final handle = _checkOpen();
    _checkCanWrite();
    _checkCollection(collection);
    final idList = ids.toList(growable: false);
    for (final id in idList) {
      _checkId(id);
    }
    if (idList.isEmpty) {
      return;
    }

    _bindings.deleteMany(handle, collection, _encodeIds(idList));
    _markCollectionChanged(collection);
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
    Duration pollInterval = defaultCindelWatchPollInterval,
    bool fireImmediately = true,
  }) {
    _checkOpen();
    _checkCollection(collection);
    _checkId(id);
    _checkPollInterval(pollInterval);

    return _watch(
      collection,
      pollInterval: pollInterval,
      fireImmediately: fireImmediately,
      readSnapshot: () => get(collection, id),
      areSnapshotsEqual: _jsonLikeEquals,
    );
  }

  /// Watches a document and emits without loading it for consumers.
  ///
  /// The stream emits after the visible document value changes. Set
  /// [fireImmediately] to `true` to emit once when the listener starts.
  Stream<void> watchDocumentLazy(
    String collection,
    int id, {
    Duration pollInterval = defaultCindelWatchPollInterval,
    bool fireImmediately = false,
  }) {
    return watchDocument(
      collection,
      id,
      pollInterval: pollInterval,
      fireImmediately: fireImmediately,
    ).map((_) {});
  }

  /// Watches all documents in [collection] and emits after committed changes.
  ///
  /// Documents are emitted in id order. The stream emits a snapshot immediately
  /// and then reacts to native collection revision changes.
  Stream<List<CindelDocument>> watchCollection(
    String collection, {
    Duration pollInterval = defaultCindelWatchPollInterval,
    bool fireImmediately = true,
  }) {
    _checkOpen();
    _checkCollection(collection);
    _checkPollInterval(pollInterval);

    return _watch(
      collection,
      pollInterval: pollInterval,
      fireImmediately: fireImmediately,
      readSnapshot: () async {
        final handle = _checkOpen();
        final ids = _bindings.documentIds(handle, collection);
        return _documentsByIds(collection, ids);
      },
      areSnapshotsEqual: _jsonLikeEquals,
    );
  }

  /// Watches a collection and emits without returning collection snapshots.
  ///
  /// The stream emits after the visible collection snapshot changes. Set
  /// [fireImmediately] to `true` to emit once when the listener starts.
  Stream<void> watchCollectionLazy(
    String collection, {
    Duration pollInterval = defaultCindelWatchPollInterval,
    bool fireImmediately = false,
  }) {
    return watchCollection(
      collection,
      pollInterval: pollInterval,
      fireImmediately: fireImmediately,
    ).map((_) {});
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
    _checkCollection(collection);
    _checkIndexName(field);
    final schemaField = _checkIndexedField(collection, field);
    final ids = _queryEqualRawIds(collection, field, value, schemaField);
    final documents = await _documentsByIds(
      collection,
      schemaField.indexType == CindelIndexType.words ? _dedupeIds(ids) : ids,
    );
    if (schemaField.indexType == CindelIndexType.hash) {
      return documents
          .where(
            (document) =>
                _indexedValuesEqual(document[field], value, schemaField),
          )
          .toList(growable: false);
    }
    return documents;
  }

  /// Returns ids whose indexed [field] equals [value].
  ///
  /// Hash indexes intentionally use [queryEqual] instead, because hash
  /// collisions need document verification before the result is observable.
  Future<List<int>> queryEqualIds(
    String collection,
    String field,
    Object value,
  ) async {
    _checkCollection(collection);
    _checkIndexName(field);
    final schemaField = _checkIndexedField(collection, field);
    if (schemaField.indexType == CindelIndexType.hash) {
      throw StateError(
        'Hash index `${schemaField.name}` requires document verification.',
      );
    }
    final ids = _queryEqualRawIds(collection, field, value, schemaField);
    return schemaField.indexType == CindelIndexType.words
        ? _dedupeIds(ids)
        : ids;
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
    if (schemaField.indexType == CindelIndexType.hash) {
      throw StateError(
        'Hash index `${schemaField.name}` only supports equality queries.',
      );
    }
    if (lower == null && upper == null) {
      throw ArgumentError.value(null, 'lower/upper', 'Must provide a bound.');
    }

    final encodedLower = lower == null
        ? null
        : _encodeRangeIndexValue(lower, schemaField, 'lower');
    final encodedUpper = upper == null
        ? null
        : _encodeRangeIndexValue(upper, schemaField, 'upper');
    _checkMatchingRangeBounds(encodedLower, encodedUpper);

    final ids = _queryRangeRawIds(
      handle,
      collection,
      field,
      encodedLower?.bytes,
      encodedUpper?.bytes,
    );
    return _documentsByIds(
      collection,
      schemaField.indexType == CindelIndexType.words ? _dedupeIds(ids) : ids,
    );
  }

  /// Returns ids whose indexed [field] is inside the inclusive range.
  Future<List<int>> queryRangeIds(
    String collection,
    String field, {
    Object? lower,
    Object? upper,
  }) async {
    final handle = _checkOpen();
    _checkCollection(collection);
    _checkIndexName(field);
    final schemaField = _checkIndexedField(collection, field);
    if (schemaField.indexType == CindelIndexType.hash) {
      throw StateError(
        'Hash index `${schemaField.name}` only supports equality queries.',
      );
    }
    if (lower == null && upper == null) {
      throw ArgumentError.value(null, 'lower/upper', 'Must provide a bound.');
    }

    final encodedLower = lower == null
        ? null
        : _encodeRangeIndexValue(lower, schemaField, 'lower');
    final encodedUpper = upper == null
        ? null
        : _encodeRangeIndexValue(upper, schemaField, 'upper');
    _checkMatchingRangeBounds(encodedLower, encodedUpper);

    final ids = _queryRangeRawIds(
      handle,
      collection,
      field,
      encodedLower?.bytes,
      encodedUpper?.bytes,
    );
    return schemaField.indexType == CindelIndexType.words
        ? _dedupeIds(ids)
        : ids;
  }

  /// Applies a native binary-document filter to [candidateIds].
  Future<List<int>> queryNativeFilterIds(
    String collection,
    Iterable<int> candidateIds,
    Uint8List filter,
  ) async {
    final handle = _checkOpen();
    _checkBinaryBackend();
    _checkCollection(collection);
    final idList = candidateIds.toList(growable: false);
    for (final id in idList) {
      _checkId(id);
    }
    if (idList.isEmpty) {
      return const <int>[];
    }
    return _bindings.queryFilter(
      handle,
      collection,
      _encodeIds(idList),
      filter,
    );
  }

  /// Projects [field] from native binary documents under [candidateIds].
  Future<List<Object?>> queryNativeProjection(
    String collection,
    Iterable<int> candidateIds,
    String field,
  ) async {
    final handle = _checkOpen();
    _checkBinaryBackend();
    _checkCollection(collection);
    _checkIndexName(field);
    final idList = candidateIds.toList(growable: false);
    for (final id in idList) {
      _checkId(id);
    }
    if (idList.isEmpty) {
      return const <Object?>[];
    }
    final bytes = _bindings.queryProject(
      handle,
      collection,
      _encodeIds(idList),
      field,
    );
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! List) {
      throw StateError('Native Cindel returned a non-list projection.');
    }
    return decoded.cast<Object?>();
  }

  /// Returns the persisted schema version for [collection], or `null`.
  ///
  /// A schema starts at version `1` when first registered. Compatible additive
  /// schema changes advance the version during [Cindel.open].
  Future<int?> schemaVersion(String collection) async {
    final handle = _checkOpen();
    _checkCollection(collection);
    return _bindings.schemaVersion(handle, collection);
  }

  Pointer<Void> _checkOpen() {
    final handle = _handle;
    if (handle == null) {
      throw StateError('CindelDatabase is closed.');
    }
    return handle;
  }

  void _checkCanWrite() {
    if (_activeTransaction == _TransactionMode.read) {
      throw StateError('Cannot write inside a Cindel read transaction.');
    }
  }

  Future<T> _runTransaction<T>(
    _TransactionMode mode,
    Future<T> Function() action,
  ) async {
    final handle = _checkOpen();
    if (_activeTransaction != null) {
      throw StateError('Cindel does not support nested transactions yet.');
    }

    final previousChangedCollections = Set<String>.of(
      _changedCollectionsInTransaction,
    );
    _changedCollectionsInTransaction.clear();
    if (mode == _TransactionMode.read) {
      _bindings.beginReadTransaction(handle);
    } else {
      _bindings.beginWriteTransaction(handle);
    }
    _activeTransaction = mode;

    try {
      final result = await action();
      _bindings.commitTransaction(handle);
      final changedCollections = Set<String>.of(
        _changedCollectionsInTransaction,
      );
      _changedCollectionsInTransaction
        ..clear()
        ..addAll(previousChangedCollections);
      _activeTransaction = null;
      if (mode == _TransactionMode.write) {
        for (final collection in changedCollections) {
          _notifyWatchers(collection);
        }
      }
      return result;
    } catch (_) {
      try {
        _bindings.rollbackTransaction(handle);
      } catch (_) {
        // Preserve the original failure from user code or commit.
      }
      _changedCollectionsInTransaction
        ..clear()
        ..addAll(previousChangedCollections);
      _activeTransaction = null;
      rethrow;
    }
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
      if (field.indexType == CindelIndexType.words) {
        if (fieldValue is! String) {
          throw ArgumentError.value(
            fieldValue,
            'value.${field.name}',
            'Word indexes require String values.',
          );
        }
        for (final token in cindelSplitWords(
          fieldValue,
          caseSensitive: field.indexCaseSensitive,
        )) {
          entries.add(
            _IndexEntry(name: field.name, value: _indexValueJson(token, field)),
          );
        }
        continue;
      }
      entries.add(
        _IndexEntry(
          name: field.name,
          value: _indexValueJson(fieldValue, field),
        ),
      );
    }
    return entries;
  }

  Future<void> _checkUniqueBatchIndexes(
    String collection,
    Map<int, CindelDocument> values,
    List<_BatchPutEntry> documents,
  ) async {
    final uniqueEntries = <_UniqueIndexEntry>[];
    for (final document in documents) {
      for (final index in document.indexes) {
        final schemaField = _fieldSchema(collection, index.name);
        if (schemaField?.isIndexUnique ?? false) {
          uniqueEntries.add(
            _UniqueIndexEntry(
              id: document.id,
              field: schemaField!,
              originalValue: values[document.id]![schemaField.name],
              encodedValue: index.value,
            ),
          );
        }
      }
    }
    if (uniqueEntries.isEmpty) {
      return;
    }

    final seen = <String, int>{};
    for (final entry in uniqueEntries) {
      final key = _uniqueValueKey(entry.field, entry.originalValue);
      final existingId = seen[key];
      if (existingId != null && existingId != entry.id) {
        throw StateError(
          'Unique index `${entry.field.name}` already contains this value.',
        );
      }
      seen[key] = entry.id;
    }

    for (final entry in uniqueEntries) {
      await _checkUniqueIndexes(
        collection,
        {entry.id: values[entry.id]!},
        [_IndexEntry(name: entry.field.name, value: entry.encodedValue)],
      );
    }
  }

  Future<void> _checkUniqueIndexes(
    String collection,
    Map<int, CindelDocument> documents,
    List<_IndexEntry> indexEntries,
  ) async {
    for (final documentEntry in documents.entries) {
      for (final index in indexEntries) {
        final schemaField = _fieldSchema(collection, index.name);
        if (!(schemaField?.isIndexUnique ?? false)) {
          continue;
        }
        final fieldValue = documentEntry.value[schemaField!.name];
        if (fieldValue == null) {
          continue;
        }
        final candidates = await queryEqual(
          collection,
          schemaField.name,
          fieldValue,
        );
        for (final candidate in candidates) {
          final candidateId = candidate[_schemas[collection]!.idField];
          if (candidateId != documentEntry.key) {
            throw StateError(
              'Unique index `${schemaField.name}` already contains this value.',
            );
          }
        }
      }
    }
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

  void _checkBinaryBackend() {
    if (backend != CindelStorageBackend.mdbx) {
      throw StateError(
        'Cindel binary documents require the MDBX storage backend.',
      );
    }
  }

  CindelFieldSchema? _fieldSchema(String collection, String field) {
    final schema = _schemas[collection];
    if (schema == null) {
      return null;
    }
    for (final schemaField in schema.fields) {
      if (schemaField.name == field) {
        return schemaField;
      }
    }
    return null;
  }

  List<int> _queryEqualRawIds(
    String collection,
    String field,
    Object value,
    CindelFieldSchema schemaField,
  ) {
    final handle = _checkOpen();
    _checkCollection(collection);
    _checkIndexName(field);
    final encodedValue = _encodeIndexValue(value, schemaField);
    return _bindings.queryIndexEqual(handle, collection, field, encodedValue);
  }

  List<int> _queryRangeRawIds(
    Pointer<Void> handle,
    String collection,
    String field,
    Uint8List? lower,
    Uint8List? upper,
  ) {
    return _bindings.queryIndexRange(handle, collection, field, lower, upper);
  }

  Future<List<CindelDocument>> _documentsByIds(
    String collection,
    List<int> ids,
  ) async {
    final documents = _documentsByIdsNullable(_checkOpen(), collection, ids);
    return [
      for (final document in documents)
        if (document != null) document,
    ];
  }

  List<CindelDocument?> _documentsByIdsNullable(
    Pointer<Void> handle,
    String collection,
    List<int> ids,
  ) {
    if (ids.isEmpty) {
      return const <CindelDocument?>[];
    }

    final bytes = _bindings.getMany(handle, collection, _encodeIds(ids));
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! List) {
      throw StateError('Native Cindel returned a non-list document batch.');
    }
    return [
      for (final value in decoded)
        if (value == null)
          null
        else if (value is Map)
          value.cast<String, Object?>()
        else
          throw StateError('Native Cindel returned a non-object document.'),
    ];
  }

  Stream<T> _watch<T>(
    String collection, {
    required Duration pollInterval,
    required bool fireImmediately,
    required Future<T> Function() readSnapshot,
    bool Function(T left, T right)? areSnapshotsEqual,
  }) {
    late final _CindelWatcher<T> watcher;
    watcher = _CindelWatcher<T>(
      pollInterval: pollInterval,
      fireImmediately: fireImmediately,
      shouldPoll: () => _activeTransaction == null,
      readRevision: () {
        final handle = _handle;
        if (handle == null) {
          throw StateError('CindelDatabase is closed.');
        }
        return _bindings.collectionRevision(handle, collection);
      },
      readSnapshot: readSnapshot,
      areSnapshotsEqual: areSnapshotsEqual,
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

  void _markCollectionChanged(String collection) {
    if (_activeTransaction == _TransactionMode.write) {
      _changedCollectionsInTransaction.add(collection);
      return;
    }
    _notifyWatchers(collection);
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

String _uniqueValueKey(CindelFieldSchema field, Object? value) {
  if (_nonNullableDartType(field.dartType) == 'String' &&
      !field.indexCaseSensitive &&
      value is String) {
    return '${field.name}:String:${value.toLowerCase()}';
  }
  return '${field.name}:${value.runtimeType}:$value';
}

List<int> _dedupeIds(List<int> ids) {
  final seen = <int>{};
  return [
    for (final id in ids)
      if (seen.add(id)) id,
  ];
}

Uint8List _encodeDocument(CindelDocument value) {
  return Uint8List.fromList(utf8.encode(jsonEncode(value)));
}

Uint8List _encodeIds(Iterable<int> ids) {
  return Uint8List.fromList(utf8.encode(jsonEncode(ids.toList())));
}

List<Uint8List?> _decodeBinaryDocumentBatch(Uint8List bytes) {
  final data = bytes.buffer.asByteData(
    bytes.offsetInBytes,
    bytes.lengthInBytes,
  );
  var offset = 0;
  int readUint8() {
    if (offset + 1 > bytes.length) {
      throw StateError('Native Cindel returned a truncated binary batch.');
    }
    return bytes[offset++];
  }

  int readUint32() {
    if (offset + 4 > bytes.length) {
      throw StateError('Native Cindel returned a truncated binary batch.');
    }
    final value = data.getUint32(offset, Endian.little);
    offset += 4;
    return value;
  }

  final count = readUint32();
  final documents = <Uint8List?>[];
  for (var index = 0; index < count; index += 1) {
    final present = readUint8();
    final length = readUint32();
    if (present == 0) {
      if (length != 0) {
        throw StateError('Native Cindel returned an invalid binary batch.');
      }
      documents.add(null);
      continue;
    }
    if (present != 1 || offset + length > bytes.length) {
      throw StateError('Native Cindel returned an invalid binary batch.');
    }
    documents.add(Uint8List.sublistView(bytes, offset, offset + length));
    offset += length;
  }
  if (offset != bytes.length) {
    throw StateError('Native Cindel returned trailing binary batch bytes.');
  }
  return documents;
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

Uint8List _encodeBatchPutEntries(List<_BatchPutEntry> entries) {
  return Uint8List.fromList(
    utf8.encode(
      jsonEncode([
        for (final entry in entries)
          {
            'id': entry.id,
            'document': entry.document,
            'indexes': [
              for (final index in entry.indexes)
                {'name': index.name, 'value': index.value},
            ],
          },
      ]),
    ),
  );
}

Uint8List _encodeBinaryBatchPutEntries(Map<int, Uint8List> entries) {
  final length =
      4 +
      entries.entries.fold<int>(
        0,
        (total, entry) => total + 8 + 4 + entry.value.length,
      );
  final bytes = Uint8List(length);
  final data = bytes.buffer.asByteData();
  var offset = 0;
  data.setUint32(offset, entries.length, Endian.little);
  offset += 4;
  for (final entry in entries.entries) {
    data.setUint64(offset, entry.key, Endian.little);
    offset += 8;
    data.setUint32(offset, entry.value.length, Endian.little);
    offset += 4;
    bytes.setRange(offset, offset + entry.value.length, entry.value);
    offset += entry.value.length;
  }
  return bytes;
}

Uint8List _encodeSchemaManifest(
  Iterable<CindelCollectionSchema<dynamic>> schemas,
) {
  final collections = schemas.toList(growable: false)
    ..sort((left, right) => left.name.compareTo(right.name));
  return Uint8List.fromList(
    utf8.encode(
      jsonEncode({
        'collections': [for (final schema in collections) _schemaJson(schema)],
      }),
    ),
  );
}

Map<String, Object> _schemaJson(CindelCollectionSchema<dynamic> schema) {
  final fields = schema.fields.toList(growable: false)
    ..sort((left, right) => left.name.compareTo(right.name));
  return {
    'name': schema.name,
    'id_field': schema.idField,
    'fields': [
      for (final field in fields)
        {
          'name': field.name,
          'dart_type': field.dartType,
          'is_id': field.isId,
          'is_indexed': field.isIndexed,
          'is_index_unique': field.isIndexUnique,
          'index_case_sensitive': field.indexCaseSensitive,
          'index_type': field.indexType.name,
        },
    ],
  };
}

Uint8List _encodeIndexValue(Object value, CindelFieldSchema field) {
  return _encodedIndexValue(value, field, 'value').bytes;
}

_EncodedIndexValue _encodeRangeIndexValue(
  Object value,
  CindelFieldSchema field,
  String argumentName,
) {
  final encoded = _encodedIndexValue(value, field, argumentName);
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
  CindelFieldSchema field,
  String argumentName,
) {
  final json = _indexValueJson(value, field, argumentName);
  return _EncodedIndexValue(
    kind: json['type']! as String,
    bytes: Uint8List.fromList(utf8.encode(jsonEncode(json))),
  );
}

Map<String, Object> _indexValueJson(
  Object value,
  CindelFieldSchema field, [
  String argumentName = 'value',
]) {
  final normalizedType = _nonNullableDartType(field.dartType);

  final valueJson = switch ((normalizedType, value)) {
    ('bool', final bool value) => {'type': 'bool', 'value': value},
    ('int', final int value) => {
      'type': 'int',
      'value': _checkSqliteInteger(value, argumentName),
    },
    ('double', final double value) when value.isFinite => {
      'type': 'double',
      'value': value,
    },
    ('String', final String value) => _stringIndexValueJson(value, field),
    ('DateTime', final DateTime value) => {
      'type': 'int',
      'value': _checkSqliteInteger(value.microsecondsSinceEpoch, argumentName),
    },
    ('DateTime', final int value) => {
      'type': 'int',
      'value': _checkSqliteInteger(value, argumentName),
    },
    ('Duration', final Duration value) => {
      'type': 'int',
      'value': _checkSqliteInteger(value.inMicroseconds, argumentName),
    },
    ('Duration', final int value) => {
      'type': 'int',
      'value': _checkSqliteInteger(value, argumentName),
    },
    ('double', final double value) => throw ArgumentError.value(
      value,
      argumentName,
      'Must be finite.',
    ),
    (_, final bool value) => {'type': 'bool', 'value': value},
    (_, final int value) => {
      'type': 'int',
      'value': _checkSqliteInteger(value, argumentName),
    },
    (_, final double value) when value.isFinite => {
      'type': 'double',
      'value': value,
    },
    (_, final String value) => {'type': 'string', 'value': value},
    (_, final double value) => throw ArgumentError.value(
      value,
      argumentName,
      'Must be finite.',
    ),
    _ => throw ArgumentError.value(
      value,
      argumentName,
      'Must match indexed field type `${field.dartType}`.',
    ),
  };
  if (field.indexType == CindelIndexType.hash) {
    return {'type': 'int', 'value': _stableHash(_stableJson(valueJson))};
  }
  return valueJson;
}

String _nonNullableDartType(String dartType) {
  return dartType.endsWith('?')
      ? dartType.substring(0, dartType.length - 1)
      : dartType;
}

Map<String, Object> _stringIndexValueJson(
  String value,
  CindelFieldSchema field,
) {
  final indexedValue = field.indexCaseSensitive ? value : value.toLowerCase();
  return {'type': 'string', 'value': indexedValue};
}

bool _indexedValuesEqual(
  Object? actual,
  Object expected,
  CindelFieldSchema field,
) {
  if (_nonNullableDartType(field.dartType) == 'String' &&
      !field.indexCaseSensitive) {
    return actual is String &&
        expected is String &&
        actual.toLowerCase() == expected.toLowerCase();
  }
  if (_nonNullableDartType(field.dartType) == 'DateTime') {
    return _dateTimeMicros(actual) == _dateTimeMicros(expected);
  }
  if (_nonNullableDartType(field.dartType) == 'Duration') {
    return _durationMicros(actual) == _durationMicros(expected);
  }
  return actual == expected;
}

int? _dateTimeMicros(Object? value) {
  return switch (value) {
    DateTime() => value.microsecondsSinceEpoch,
    int() => value,
    _ => null,
  };
}

int? _durationMicros(Object? value) {
  return switch (value) {
    Duration() => value.inMicroseconds,
    int() => value,
    _ => null,
  };
}

String _stableJson(Object value) => jsonEncode(value);

bool _jsonLikeEquals(Object? left, Object? right) {
  if (identical(left, right)) {
    return true;
  }
  if (left is Map && right is Map) {
    if (left.length != right.length) {
      return false;
    }
    for (final entry in left.entries) {
      if (!right.containsKey(entry.key)) {
        return false;
      }
      if (!_jsonLikeEquals(entry.value, right[entry.key])) {
        return false;
      }
    }
    return true;
  }
  if (left is List && right is List) {
    if (left.length != right.length) {
      return false;
    }
    for (var index = 0; index < left.length; index += 1) {
      if (!_jsonLikeEquals(left[index], right[index])) {
        return false;
      }
    }
    return true;
  }
  return left == right;
}

int _stableHash(String value) {
  const offsetBasis = 0xcbf29ce484222325;
  const prime = 0x100000001b3;
  const mask = 0x7fffffffffffffff;
  var hash = offsetBasis;
  for (final codeUnit in value.codeUnits) {
    hash ^= codeUnit;
    hash = (hash * prime) & mask;
  }
  return hash;
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

final class _BatchPutEntry {
  const _BatchPutEntry({
    required this.id,
    required this.document,
    required this.indexes,
  });

  final int id;
  final CindelDocument document;
  final List<_IndexEntry> indexes;
}

final class _UniqueIndexEntry {
  const _UniqueIndexEntry({
    required this.id,
    required this.field,
    required this.originalValue,
    required this.encodedValue,
  });

  final int id;
  final CindelFieldSchema field;
  final Object? originalValue;
  final Map<String, Object> encodedValue;
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
    required bool fireImmediately,
    required bool Function() shouldPoll,
    required int Function() readRevision,
    required Future<T> Function() readSnapshot,
    required bool Function(T left, T right)? areSnapshotsEqual,
    required void Function() onListen,
    required void Function() onCancel,
  }) : _pollInterval = pollInterval,
       _fireImmediately = fireImmediately,
       _shouldPoll = shouldPoll,
       _readRevision = readRevision,
       _readSnapshot = readSnapshot,
       _areSnapshotsEqual = areSnapshotsEqual,
       _onListen = onListen,
       _onCancel = onCancel {
    _controller = StreamController<T>(
      onListen: () {
        _onListen();
        if (_fireImmediately) {
          unawaited(poll(force: true));
        } else {
          unawaited(_prime());
        }
        _timer = Timer.periodic(_pollInterval, (_) => unawaited(poll()));
      },
      onCancel: () {
        _timer?.cancel();
        _onCancel();
      },
    );
  }

  final Duration _pollInterval;
  final bool _fireImmediately;
  final bool Function() _shouldPoll;
  final int Function() _readRevision;
  final Future<T> Function() _readSnapshot;
  final bool Function(T left, T right)? _areSnapshotsEqual;
  final void Function() _onListen;
  final void Function() _onCancel;

  late final StreamController<T> _controller;
  Timer? _timer;
  int? _lastRevision;
  bool _hasLastSnapshot = false;
  T? _lastSnapshot;
  bool _isPolling = false;

  Stream<T> get stream => _controller.stream;

  Future<void> _prime() async {
    if (_isPolling || _controller.isClosed) {
      return;
    }
    _isPolling = true;
    try {
      _lastRevision = _readRevision();
      _lastSnapshot = await _readSnapshot();
      _hasLastSnapshot = true;
    } catch (error, stackTrace) {
      if (!_controller.isClosed) {
        _controller.addError(error, stackTrace);
      }
    } finally {
      _isPolling = false;
    }
  }

  Future<void> poll({bool force = false}) async {
    if (_isPolling || _controller.isClosed) {
      return;
    }
    if (!force && !_shouldPoll()) {
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
      final areSnapshotsEqual = _areSnapshotsEqual;
      if (!force && _hasLastSnapshot && areSnapshotsEqual != null) {
        final lastSnapshot = _lastSnapshot as T;
        if (areSnapshotsEqual(lastSnapshot, snapshot)) {
          _lastSnapshot = snapshot;
          return;
        }
      }
      _lastSnapshot = snapshot;
      _hasLastSnapshot = true;
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
