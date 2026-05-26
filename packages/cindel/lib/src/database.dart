import 'dart:async';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:cindel_annotations/cindel_annotations.dart';

import 'generic_document.dart';
import 'native/bindings.dart';
import 'native/wire.dart';
import 'schema.dart';
import 'text.dart';

/// A JSON-like document accepted by Cindel's manual API.
typedef CindelDocument = Map<String, Object?>;

const _maximumSqliteId = 0x7FFFFFFFFFFFFFFF;
const _inMemoryDirectory = ':memory:';
const _nativeAggregateOperations = {'count', 'min', 'max', 'sum', 'average'};

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

sealed class CindelNativeQuerySource {
  const CindelNativeQuerySource();
}

final class CindelNativeAllQuerySource extends CindelNativeQuerySource {
  const CindelNativeAllQuerySource();
}

final class CindelNativeIndexEqualQuerySource extends CindelNativeQuerySource {
  const CindelNativeIndexEqualQuerySource({
    required this.indexName,
    required this.value,
    this.dedupe = false,
  });

  final String indexName;
  final Object value;
  final bool dedupe;
}

final class CindelNativeCompositeEqualQuerySource
    extends CindelNativeQuerySource {
  const CindelNativeCompositeEqualQuerySource({
    required this.indexName,
    required this.values,
  });

  final String indexName;
  final List<Object> values;
}

final class CindelNativeIndexRangeQuerySource extends CindelNativeQuerySource {
  const CindelNativeIndexRangeQuerySource({
    required this.indexName,
    required this.lower,
    required this.upper,
    this.dedupe = false,
  });

  final String indexName;
  final Object? lower;
  final Object? upper;
  final bool dedupe;
}

final class CindelNativeQuerySort {
  const CindelNativeQuerySort({required this.field, required this.descending});

  final String field;
  final bool descending;
}

final class CindelNativeQueryPlan {
  const CindelNativeQueryPlan({
    required this.source,
    this.filter,
    this.sorts = const [],
    this.distinctFields = const [],
    this.offset = 0,
    this.limit,
  });

  final CindelNativeQuerySource source;
  final Uint8List? filter;
  final List<CindelNativeQuerySort> sorts;
  final List<String> distinctFields;
  final int offset;
  final int? limit;
}

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
  final Map<String, _CindelChangeSetBuilder> _changesInTransaction = {};
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
      _changesInTransaction.clear();
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
      _markNativeCollectionChanged(
        CindelChangeSet.upsert(collection, id, value),
      );
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
    _markNativeCollectionChanged(CindelChangeSet.upsert(collection, id, value));
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
    _markNativeCollectionChanged(CindelChangeSet.upserts(collection, values));
  }

  /// Stores one generated binary document.
  ///
  /// This is intended for generated typed collections when the selected
  /// backend can index and read Cindel's binary document format directly.
  Future<void> putBinaryDocument(
    String collection,
    int id,
    Uint8List bytes, {
    CindelDocument? document,
  }) async {
    final handle = _checkOpen();
    _checkCanWrite();
    _checkBinaryBackend();
    _checkCollection(collection);
    _checkId(id);

    _bindings.putIndexed(handle, collection, id, bytes, Uint8List(0));
    _markNativeCollectionChanged(
      CindelChangeSet.upsert(collection, id, document),
    );
  }

  /// Stores generated binary documents atomically.
  Future<void> putAllBinaryDocuments(
    String collection,
    Map<int, Uint8List> values, {
    Map<int, CindelDocument>? documents,
  }) async {
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
    _markNativeCollectionChanged(
      CindelChangeSet.upserts(collection, documents, ids: values.keys),
    );
  }

  /// Stores generated typed objects through the native binary document writer.
  Future<void> putAllNativeBinaryDocuments<T>(
    String collection,
    List<int> ids,
    List<T> objects,
    Uint8List fieldTypes,
    CindelWriteNativeDocument<T> writeDocument,
  ) async {
    final handle = _checkOpen();
    _checkCanWrite();
    _checkBinaryBackend();
    _checkCollection(collection);
    if (objects.isEmpty) {
      return;
    }
    if (ids.length != objects.length) {
      throw ArgumentError.value(
        ids.length,
        'ids',
        'Must match the object count.',
      );
    }
    for (final id in ids) {
      _checkId(id);
    }
    final trackChanges =
        _activeTransaction == _TransactionMode.write ||
        _hasWatchers(collection);

    _bindings.putManyNativeDocuments(
      handle,
      collection,
      fieldTypes,
      ids,
      objects,
      writeDocument,
      trackChanges,
    );
    _markNativeCollectionChanged(
      CindelChangeSet.upserts(collection, null, ids: ids),
    );
  }

  /// Stores generated typed objects through the native writer in one Dart pass.
  Future<void> putAllNativeBinaryObjects<T>(
    String collection,
    List<T> objects,
    Uint8List fieldTypes,
    CindelGetId<T> getId,
    CindelWriteNativeDocument<T> writeDocument,
  ) async {
    final handle = _checkOpen();
    _checkCanWrite();
    _checkBinaryBackend();
    _checkCollection(collection);
    if (objects.isEmpty) {
      return;
    }
    final trackChanges =
        _activeTransaction == _TransactionMode.write ||
        _hasWatchers(collection);

    _bindings.putManyNativeObjects(
      handle,
      collection,
      fieldTypes,
      objects,
      getId,
      writeDocument,
      trackChanges,
    );
    _markNativeCollectionChanged(CindelChangeSet.upserts(collection, null));
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

    return _decodeDocument(collection, bytes, _schemas[collection]);
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

  /// Reads generated typed objects through the native binary document reader.
  Future<List<T?>> getAllNativeBinaryDocuments<T>(
    String collection,
    Iterable<int> ids,
    Uint8List fieldTypes,
    CindelReadNativeDocument<T> readDocument,
  ) async {
    final handle = _checkOpen();
    _checkBinaryBackend();
    _checkCollection(collection);
    final idList = ids.toList(growable: false);
    for (final id in idList) {
      _checkId(id);
    }
    if (idList.isEmpty) {
      return <T?>[];
    }

    return _bindings.getManyNativeDocuments(
      handle,
      collection,
      _encodeIds(idList),
      fieldTypes,
      readDocument,
    );
  }

  /// Reads generated typed query results through the native binary document
  /// reader without a separate id-list round trip.
  Future<List<T>> queryNativePlanObjects<T>(
    String collection,
    CindelNativeQueryPlan plan,
    Uint8List fieldTypes,
    CindelReadNativeDocument<T> readDocument,
  ) async {
    final handle = _checkOpen();
    _checkBinaryBackend();
    _checkCollection(collection);
    return _bindings.queryPlanNativeDocuments(
      handle,
      collection,
      _encodeNativeQueryPlan(collection, plan),
      fieldTypes,
      readDocument,
    );
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
    _markNativeCollectionChanged(CindelChangeSet.delete(collection, id));
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
    _markNativeCollectionChanged(CindelChangeSet.deletes(collection, idList));
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
      shouldReadChange: (change) => change.mayAffectDocument(id),
      readSnapshot: (_) => get(collection, id),
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
      shouldReadChange: (_) => true,
      readSnapshot: (_) async {
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
    return watchCollectionChanges(
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
    final rows = decodeProjectionRows(bytes);
    if (rows.columnCount != 1) {
      throw StateError('Native Cindel returned an invalid projection shape.');
    }
    return [for (final cell in rows.cells) _wireValueToObject(cell)];
  }

  /// Aggregates [field] from native binary documents under [candidateIds].
  Future<Object?> queryNativeAggregate(
    String collection,
    Iterable<int> candidateIds,
    String field,
    String operation,
  ) async {
    final handle = _checkOpen();
    _checkBinaryBackend();
    _checkCollection(collection);
    _checkIndexName(field);
    if (!_nativeAggregateOperations.contains(operation)) {
      throw ArgumentError.value(
        operation,
        'operation',
        'Unsupported aggregate.',
      );
    }
    final idList = candidateIds.toList(growable: false);
    for (final id in idList) {
      _checkId(id);
    }
    if (idList.isEmpty) {
      return operation == 'count' ? 0 : null;
    }
    final bytes = _bindings.queryAggregate(
      handle,
      collection,
      _encodeIds(idList),
      field,
      operation,
    );
    return _wireScalarToObject(decodeScalar(bytes));
  }

  Future<List<int>> queryNativePlanIds(
    String collection,
    CindelNativeQueryPlan plan,
  ) async {
    final handle = _checkOpen();
    _checkBinaryBackend();
    _checkCollection(collection);
    return _bindings.queryPlanIds(
      handle,
      collection,
      _encodeNativeQueryPlan(collection, plan),
    );
  }

  Future<List<CindelDocument>> queryNativePlanDocuments(
    String collection,
    CindelNativeQueryPlan plan,
  ) async {
    final handle = _checkOpen();
    _checkBinaryBackend();
    _checkCollection(collection);
    final documents = _decodeBinaryDocumentBatch(
      _bindings.queryPlanDocuments(
        handle,
        collection,
        _encodeNativeQueryPlan(collection, plan),
      ),
    );
    return [
      for (final bytes in documents)
        if (bytes != null)
          _decodeDocument(collection, bytes, _schemas[collection]),
    ];
  }

  Future<int> queryNativePlanCount(
    String collection,
    CindelNativeQueryPlan plan,
  ) async {
    final handle = _checkOpen();
    _checkBinaryBackend();
    _checkCollection(collection);
    final scalar = decodeScalar(
      _bindings.queryPlanCount(
        handle,
        collection,
        _encodeNativeQueryPlan(collection, plan),
      ),
    );
    final value = _wireScalarToObject(scalar);
    if (value is int) {
      return value;
    }
    throw StateError('Native Cindel returned a non-integer query count.');
  }

  Future<List<Object?>> queryNativePlanProjection(
    String collection,
    CindelNativeQueryPlan plan,
    String field,
  ) async {
    final handle = _checkOpen();
    _checkBinaryBackend();
    _checkCollection(collection);
    _checkIndexName(field);
    final rows = decodeProjectionRows(
      _bindings.queryPlanProject(
        handle,
        collection,
        _encodeNativeQueryPlan(collection, plan),
        field,
      ),
    );
    if (rows.columnCount != 1) {
      throw StateError('Native Cindel returned an invalid projection shape.');
    }
    return [for (final cell in rows.cells) _wireValueToObject(cell)];
  }

  Future<Object?> queryNativePlanAggregate(
    String collection,
    CindelNativeQueryPlan plan,
    String field,
    String operation,
  ) async {
    final handle = _checkOpen();
    _checkBinaryBackend();
    _checkCollection(collection);
    _checkIndexName(field);
    if (!_nativeAggregateOperations.contains(operation)) {
      throw ArgumentError.value(
        operation,
        'operation',
        'Unsupported aggregate.',
      );
    }
    final bytes = _bindings.queryPlanAggregate(
      handle,
      collection,
      _encodeNativeQueryPlan(collection, plan),
      field,
      operation,
    );
    return _wireScalarToObject(decodeScalar(bytes));
  }

  Future<List<int>> deleteNativePlan(
    String collection,
    CindelNativeQueryPlan plan,
  ) async {
    final handle = _checkOpen();
    _checkCanWrite();
    _checkBinaryBackend();
    _checkCollection(collection);
    final ids = _bindings.queryPlanDelete(
      handle,
      collection,
      _encodeNativeQueryPlan(collection, plan),
    );
    if (ids.isNotEmpty) {
      _markNativeCollectionChanged(CindelChangeSet.deletes(collection, ids));
    }
    return ids;
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

    final previousChanges = Map<String, _CindelChangeSetBuilder>.of(
      _changesInTransaction,
    );
    _changesInTransaction.clear();
    if (mode == _TransactionMode.read) {
      _bindings.beginReadTransaction(handle);
    } else {
      _bindings.beginWriteTransaction(handle);
    }
    _activeTransaction = mode;

    try {
      final result = await action();
      _bindings.commitTransaction(handle);
      final localChanges = {
        for (final entry in _changesInTransaction.entries)
          entry.key: entry.value.build(),
      };
      final changes = mode == _TransactionMode.write
          ? _nativeChangesForWatchers(handle, localChanges)
          : const <CindelChangeSet>[];
      _changesInTransaction
        ..clear()
        ..addAll(previousChanges);
      _activeTransaction = null;
      if (mode == _TransactionMode.write) {
        for (final change in changes) {
          _notifyWatchers(change);
        }
      }
      return result;
    } catch (_) {
      try {
        _bindings.rollbackTransaction(handle);
      } catch (_) {
        // Preserve the original failure from user code or commit.
      }
      _changesInTransaction
        ..clear()
        ..addAll(previousChanges);
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
            _IndexEntry(name: field.name, value: _indexValueWire(token, field)),
          );
        }
        continue;
      }
      if (field.indexType == CindelIndexType.multiEntry) {
        if (fieldValue is! Iterable) {
          throw ArgumentError.value(
            fieldValue,
            'value.${field.name}',
            'Multi-entry indexes require List values.',
          );
        }
        for (final item in fieldValue) {
          if (item == null) {
            continue;
          }
          entries.add(
            _IndexEntry(name: field.name, value: _indexValueWire(item, field)),
          );
        }
        continue;
      }
      entries.add(
        _IndexEntry(
          name: field.name,
          value: _indexValueWire(fieldValue, field),
        ),
      );
    }
    for (final index in schema.compositeIndexes) {
      final values = <WireIndexValue>[];
      var hasAllValues = true;
      for (final fieldName in index.fields) {
        if (!value.containsKey(fieldName) || value[fieldName] == null) {
          hasAllValues = false;
          break;
        }
        final field = _fieldSchema(collection, fieldName)!;
        values.add(
          _indexValueWire(
            value[fieldName]!,
            CindelFieldSchema(
              name: field.name,
              dartType: field.dartType,
              binaryType: field.binaryType,
              isId: field.isId,
              isIndexed: field.isIndexed,
              isIndexUnique: field.isIndexUnique,
              indexCaseSensitive: index.caseSensitive,
              indexType: field.indexType,
            ),
          ),
        );
      }
      if (hasAllValues) {
        entries.add(
          _IndexEntry(name: index.name, value: WireIndexValue.list(values)),
        );
      }
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

  /// Returns documents whose composite [indexName] equals [values].
  Future<List<CindelDocument>> queryCompositeEqual(
    String collection,
    String indexName,
    List<Object> values,
  ) async {
    final ids = queryCompositeEqualIds(collection, indexName, values);
    return _documentsByIds(collection, ids);
  }

  /// Returns ids whose composite [indexName] equals [values].
  List<int> queryCompositeEqualIds(
    String collection,
    String indexName,
    List<Object> values,
  ) {
    final handle = _checkOpen();
    _checkCollection(collection);
    _checkIndexName(indexName);
    final schema = _schemas[collection];
    if (schema == null) {
      throw StateError(
        'Collection `$collection` has no registered Cindel schema.',
      );
    }
    final composite = schema.compositeIndexes.firstWhere(
      (index) => index.name == indexName,
      orElse: () => throw StateError(
        'Composite index `$indexName` is not registered for `$collection`.',
      ),
    );
    if (values.length != composite.fields.length) {
      throw ArgumentError.value(
        values,
        'values',
        'Composite index `$indexName` expects ${composite.fields.length} values.',
      );
    }
    final encodedValues = <WireIndexValue>[];
    for (var index = 0; index < values.length; index += 1) {
      final field = _fieldSchema(collection, composite.fields[index])!;
      encodedValues.add(
        _indexValueWire(
          values[index],
          CindelFieldSchema(
            name: field.name,
            dartType: field.dartType,
            binaryType: field.binaryType,
            isId: field.isId,
            isIndexed: field.isIndexed,
            isIndexUnique: field.isIndexUnique,
            indexCaseSensitive: composite.caseSensitive,
            indexType: field.indexType,
          ),
        ),
      );
    }
    final encodedValue = encodeIndexValue(WireIndexValue.list(encodedValues));
    return _bindings.queryIndexEqual(
      handle,
      collection,
      indexName,
      encodedValue,
    );
  }

  Uint8List _encodeNativeQueryPlan(
    String collection,
    CindelNativeQueryPlan plan,
  ) {
    if (plan.offset < 0) {
      throw ArgumentError.value(plan.offset, 'offset', 'Must be non-negative.');
    }
    final limit = plan.limit;
    if (limit != null && limit < 0) {
      throw ArgumentError.value(limit, 'limit', 'Must be non-negative.');
    }

    final wireSource = switch (plan.source) {
      CindelNativeAllQuerySource() => const WireQuerySource.all(dedupe: false),
      CindelNativeIndexEqualQuerySource(
        :final indexName,
        :final value,
        :final dedupe,
      ) =>
        WireQuerySource.indexEqual(
          indexName: indexName,
          value: _nativeQueryIndexValue(collection, indexName, value),
          dedupe: dedupe,
        ),
      CindelNativeCompositeEqualQuerySource(:final indexName, :final values) =>
        WireQuerySource.indexEqual(
          indexName: indexName,
          value: _compositeIndexValueWire(collection, indexName, values),
          dedupe: false,
        ),
      CindelNativeIndexRangeQuerySource(
        :final indexName,
        :final lower,
        :final upper,
        :final dedupe,
      ) =>
        WireQuerySource.indexRange(
          indexName: indexName,
          lower: lower == null
              ? null
              : _nativeQueryRangeValue(collection, indexName, lower, 'lower'),
          upper: upper == null
              ? null
              : _nativeQueryRangeValue(collection, indexName, upper, 'upper'),
          dedupe: dedupe,
        ),
    };

    for (final sort in plan.sorts) {
      _requireSchemaField(collection, sort.field);
    }
    for (final field in plan.distinctFields) {
      _requireSchemaField(collection, field);
    }

    return encodeQueryPlan(
      WireQueryPlan(
        source: wireSource,
        filter: plan.filter,
        sorts: [
          for (final sort in plan.sorts)
            WireQuerySort(field: sort.field, ascending: !sort.descending),
        ],
        distinctFields: plan.distinctFields,
        offset: plan.offset,
        limit: limit,
      ),
    );
  }

  WireIndexValue _nativeQueryIndexValue(
    String collection,
    String field,
    Object value,
  ) {
    final schemaField = _indexedFieldSchema(collection, field);
    return _indexValueWire(value, schemaField);
  }

  WireIndexValue _nativeQueryRangeValue(
    String collection,
    String field,
    Object value,
    String argumentName,
  ) {
    final schemaField = _indexedFieldSchema(collection, field);
    final encoded = _encodeRangeIndexValue(value, schemaField, argumentName);
    return decodeIndexValue(encoded.bytes);
  }

  WireIndexValue _compositeIndexValueWire(
    String collection,
    String indexName,
    List<Object> values,
  ) {
    final schema = _schemas[collection];
    if (schema == null) {
      throw StateError(
        'Collection `$collection` has no registered Cindel schema.',
      );
    }
    final composite = schema.compositeIndexes.firstWhere(
      (index) => index.name == indexName,
      orElse: () => throw StateError(
        'Composite index `$indexName` is not registered for `$collection`.',
      ),
    );
    if (values.length != composite.fields.length) {
      throw ArgumentError.value(
        values,
        'values',
        'Composite index `$indexName` expects ${composite.fields.length} values.',
      );
    }
    return WireIndexValue.list([
      for (var index = 0; index < values.length; index += 1)
        _indexValueWire(
          values[index],
          _fieldSchemaWithCaseSensitivity(
            collection,
            composite.fields[index],
            composite.caseSensitive,
          ),
        ),
    ]);
  }

  CindelFieldSchema _fieldSchemaWithCaseSensitivity(
    String collection,
    String field,
    bool caseSensitive,
  ) {
    final schemaField = _requireSchemaField(collection, field);
    return CindelFieldSchema(
      name: schemaField.name,
      dartType: schemaField.dartType,
      binaryType: schemaField.binaryType,
      isId: schemaField.isId,
      isIndexed: schemaField.isIndexed,
      isIndexUnique: schemaField.isIndexUnique,
      indexCaseSensitive: caseSensitive,
      indexType: schemaField.indexType,
    );
  }

  CindelFieldSchema _indexedFieldSchema(String collection, String field) {
    final schemaField = _requireSchemaField(collection, field);
    if (!schemaField.isIndexed) {
      throw StateError('Field `$field` is not indexed for `$collection`.');
    }
    return schemaField;
  }

  CindelFieldSchema _requireSchemaField(String collection, String field) {
    final schemaField = _fieldSchema(collection, field);
    if (schemaField == null) {
      throw StateError('Field `$field` is not registered for `$collection`.');
    }
    return schemaField;
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

    final documents = _decodeBinaryDocumentBatch(
      _bindings.getMany(handle, collection, _encodeIds(ids)),
    );
    return [
      for (final bytes in documents)
        if (bytes == null)
          null
        else
          _decodeDocument(collection, bytes, _schemas[collection]),
    ];
  }

  Stream<T> _watch<T>(
    String collection, {
    required Duration pollInterval,
    required bool fireImmediately,
    required bool Function(CindelChangeSet change) shouldReadChange,
    required Future<T> Function(CindelChangeSet? change) readSnapshot,
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
      shouldReadChange: shouldReadChange,
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

  Stream<CindelChangeSet> watchCollectionChanges(
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
      shouldReadChange: (_) => true,
      readSnapshot: (change) async =>
          change ?? CindelChangeSet.external(collection),
      areSnapshotsEqual: null,
    );
  }

  void _notifyWatchers(CindelChangeSet change) {
    final watchers = _watchersByCollection[change.collection];
    if (watchers == null) {
      return;
    }
    for (final watcher in List<_RegisteredWatcher>.of(watchers)) {
      unawaited(watcher.poll(change: change));
    }
  }

  void _markNativeCollectionChanged(CindelChangeSet fallback) {
    if (_activeTransaction == _TransactionMode.write) {
      _markCollectionChanged(fallback);
      return;
    }

    final handle = _checkOpen();
    if (!_hasWatchers(fallback.collection)) {
      _bindings.discardChanges(handle);
      return;
    }
    final changes = _changesFromNative(_takeNativeChangeSets(handle), {
      fallback.collection: fallback,
    });
    for (final change in changes) {
      _notifyWatchers(change);
    }
  }

  List<CindelChangeSet> _nativeChangesForWatchers(
    Pointer<Void> handle,
    Map<String, CindelChangeSet> localChanges,
  ) {
    if (!localChanges.keys.any(_hasWatchers)) {
      _bindings.discardChanges(handle);
      return const [];
    }
    return _changesFromNative(_takeNativeChangeSets(handle), localChanges);
  }

  bool _hasWatchers(String collection) {
    return _watchersByCollection[collection]?.isNotEmpty ?? false;
  }

  List<WireChangeSet> _takeNativeChangeSets(Pointer<Void> handle) {
    return decodeChangeSetList(_bindings.takeChanges(handle));
  }

  List<CindelChangeSet> _changesFromNative(
    List<WireChangeSet> nativeChanges,
    Map<String, CindelChangeSet> localChanges,
  ) {
    return [
      for (final change in nativeChanges)
        _changeFromNative(change, localChanges[change.collection]),
    ];
  }

  CindelChangeSet _changeFromNative(
    WireChangeSet change,
    CindelChangeSet? localChange,
  ) {
    final ids = change.documentIds.toSet();
    final documents = {
      for (final entry
          in (localChange?.documents ?? const <int, CindelDocument>{}).entries)
        if (ids.contains(entry.key)) entry.key: entry.value,
    };
    return CindelChangeSet.native(
      collection: change.collection,
      revision: change.revision,
      ids: ids,
      documents: documents,
      hasUnknownDocuments: localChange?.hasUnknownDocuments ?? false,
    );
  }

  void _markCollectionChanged(CindelChangeSet change) {
    if (_activeTransaction == _TransactionMode.write) {
      _changesInTransaction
          .putIfAbsent(
            change.collection,
            () => _CindelChangeSetBuilder(change.collection),
          )
          .add(change);
      return;
    }
    _notifyWatchers(change);
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
  return cindelEncodeGenericDocument(value);
}

CindelDocument _decodeDocument(
  String collection,
  Uint8List bytes,
  CindelCollectionSchema<dynamic>? schema,
) {
  if (cindelIsGenericDocument(bytes)) {
    return cindelDecodeGenericDocument(bytes);
  }

  if (schema != null) {
    final dynamic dynamicSchema = schema;
    final fromBinaryDocument = dynamicSchema.fromBinaryDocument;
    if (fromBinaryDocument != null) {
      try {
        final object = fromBinaryDocument(bytes);
        final document = dynamicSchema.toDocument(object);
        if (document is Map) {
          return document.cast<String, Object?>();
        }
      } on Object {
        // Fall through to the unsupported payload error below.
      }
    }
  }

  throw StateError(
    'Native Cindel returned an unsupported document payload for `$collection`.',
  );
}

Object? _wireScalarToObject(WireScalar scalar) {
  return switch (scalar) {
    WireScalarNull() => null,
    WireScalarBool(:final value) => value,
    WireScalarInt(:final value) => value,
    WireScalarDouble(:final value) => value,
    WireScalarString(:final value) => value,
  };
}

Object? _wireValueToObject(WireValue value) {
  return switch (value) {
    WireNullValue() => null,
    WireBoolValue(:final value) => value,
    WireIntValue(:final value) => value,
    WireDoubleValue(:final value) => value,
    WireStringValue(:final value) => value,
    WireListValue(:final values) => [
      for (final value in values) _wireValueToObject(value),
    ],
    WireObjectValue(:final fields) => {
      for (final field in fields) field.name: _wireValueToObject(field.value),
    },
  };
}

Uint8List _encodeIds(Iterable<int> ids) {
  return encodeIdList(ids.toList(growable: false));
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
  return encodeIndexEntryList([
    for (final entry in entries)
      WireIndexEntry(documentId: 0, indexName: entry.name, value: entry.value),
  ]);
}

Uint8List _encodeBatchPutEntries(List<_BatchPutEntry> entries) {
  return encodeIndexedDocumentWriteBatch([
    for (final entry in entries)
      WireIndexedDocumentWrite(
        id: entry.id,
        bytes: _encodeDocument(entry.document),
        indexes: [
          for (final index in entry.indexes)
            WireIndexEntry(
              documentId: entry.id,
              indexName: index.name,
              value: index.value,
            ),
        ],
      ),
  ]);
}

Uint8List _encodeBinaryBatchPutEntries(Map<int, Uint8List> entries) {
  return encodeDocumentWriteBatch([
    for (final entry in entries.entries)
      WireDocumentWrite(id: entry.key, bytes: entry.value),
  ]);
}

Uint8List _encodeSchemaManifest(
  Iterable<CindelCollectionSchema<dynamic>> schemas,
) {
  final collections = schemas.toList(growable: false)
    ..sort((left, right) => left.name.compareTo(right.name));
  return encodeSchemaManifest(
    WireSchemaManifest(
      version: 1,
      collections: [for (final schema in collections) _schemaWire(schema)],
    ),
  );
}

WireCollectionSchema _schemaWire(CindelCollectionSchema<dynamic> schema) {
  final fields = schema.fields.toList(growable: false)
    ..sort((left, right) => left.name.compareTo(right.name));
  return WireCollectionSchema(
    name: schema.name,
    idField: schema.idField,
    fields: [
      for (final field in fields)
        WireFieldSchema(
          name: field.name,
          typeName: field.dartType,
          binaryType: field.binaryType ?? field.dartType,
          indexType: field.indexType.name,
          isId: field.isId,
          isIndexed: field.isIndexed,
          isUnique: field.isIndexUnique,
          isNullable: field.dartType.endsWith('?'),
          caseSensitive: field.indexCaseSensitive,
        ),
    ],
    indexes: [
      for (final index in schema.compositeIndexes)
        WireIndexSchema(
          name: index.name,
          fields: index.fields,
          isUnique: index.isUnique,
          caseSensitive: index.caseSensitive,
        ),
    ],
  );
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
  final wire = _indexValueWire(value, field, argumentName);
  return _EncodedIndexValue(
    kind: _wireIndexValueKind(wire),
    bytes: encodeIndexValue(wire),
  );
}

WireIndexValue _indexValueWire(
  Object value,
  CindelFieldSchema field, [
  String argumentName = 'value',
]) {
  final normalizedType = _nonNullableDartType(field.dartType);

  final wireValue = switch ((normalizedType, value)) {
    ('bool', final bool value) => WireIndexValue.bool(value),
    ('int', final int value) => WireIndexValue.int(
      _checkSqliteInteger(value, argumentName),
    ),
    ('double', final double value) when value.isFinite => WireIndexValue.double(
      value,
    ),
    ('String', final String value) => _stringIndexValueWire(value, field),
    ('DateTime', final DateTime value) => WireIndexValue.int(
      _checkSqliteInteger(value.microsecondsSinceEpoch, argumentName),
    ),
    ('DateTime', final int value) => WireIndexValue.int(
      _checkSqliteInteger(value, argumentName),
    ),
    ('Duration', final Duration value) => WireIndexValue.int(
      _checkSqliteInteger(value.inMicroseconds, argumentName),
    ),
    ('Duration', final int value) => WireIndexValue.int(
      _checkSqliteInteger(value, argumentName),
    ),
    ('double', final double value) => throw ArgumentError.value(
      value,
      argumentName,
      'Must be finite.',
    ),
    (_, final bool value) => WireIndexValue.bool(value),
    (_, final int value) => WireIndexValue.int(
      _checkSqliteInteger(value, argumentName),
    ),
    (_, final double value) when value.isFinite => WireIndexValue.double(value),
    (_, final String value) =>
      field.indexType == CindelIndexType.multiEntry
          ? _stringIndexValueWire(value, field)
          : WireIndexValue.string(value),
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
    return WireIndexValue.int(_stableHashBytes(encodeIndexValue(wireValue)));
  }
  return wireValue;
}

String _nonNullableDartType(String dartType) {
  return dartType.endsWith('?')
      ? dartType.substring(0, dartType.length - 1)
      : dartType;
}

WireIndexValue _stringIndexValueWire(String value, CindelFieldSchema field) {
  final indexedValue = field.indexCaseSensitive ? value : value.toLowerCase();
  return WireIndexValue.string(indexedValue);
}

String _wireIndexValueKind(WireIndexValue value) {
  return switch (value) {
    WireIndexNull() => 'null',
    WireIndexBool() => 'bool',
    WireIndexInt() => 'int',
    WireIndexDouble() => 'double',
    WireIndexString() => 'string',
    WireIndexList() => 'list',
  };
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

int _stableHashBytes(Uint8List value) {
  const offsetBasis = 0xcbf29ce484222325;
  const prime = 0x100000001b3;
  const mask = 0x7fffffffffffffff;
  var hash = offsetBasis;
  for (final byte in value) {
    hash ^= byte;
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
  final WireIndexValue value;
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
  final WireIndexValue encodedValue;
}

final class _EncodedIndexValue {
  const _EncodedIndexValue({required this.kind, required this.bytes});

  final String kind;
  final Uint8List bytes;
}

/// A native-backed collection change observed by Cindel watchers.
///
/// Local writes include changed ids and, when Dart has the value available,
/// written documents. Changes from other database handles are reported as
/// external changes and require reading the native collection revision.
final class CindelChangeSet {
  const CindelChangeSet._({
    required this.collection,
    required this.documentIds,
    required this.documents,
    required this.hasUnknownDocuments,
    required this.isExternal,
    required this.revision,
  });

  factory CindelChangeSet.external(String collection) {
    return CindelChangeSet._(
      collection: collection,
      documentIds: null,
      documents: const {},
      hasUnknownDocuments: true,
      isExternal: true,
      revision: null,
    );
  }

  factory CindelChangeSet.upsert(
    String collection,
    int id,
    CindelDocument? document,
  ) {
    return CindelChangeSet._(
      collection: collection,
      documentIds: {id},
      documents: document == null ? const {} : {id: Map.of(document)},
      hasUnknownDocuments: document == null,
      isExternal: false,
      revision: null,
    );
  }

  factory CindelChangeSet.upserts(
    String collection,
    Map<int, CindelDocument>? documents, {
    Iterable<int>? ids,
  }) {
    final documentCopies = {
      for (final entry in (documents ?? const <int, CindelDocument>{}).entries)
        entry.key: Map<String, Object?>.of(entry.value),
    };
    return CindelChangeSet._(
      collection: collection,
      documentIds: {...?ids, ...documentCopies.keys},
      documents: documentCopies,
      hasUnknownDocuments: documents == null,
      isExternal: false,
      revision: null,
    );
  }

  factory CindelChangeSet.delete(String collection, int id) {
    return CindelChangeSet.deletes(collection, [id]);
  }

  factory CindelChangeSet.deletes(String collection, Iterable<int> ids) {
    return CindelChangeSet._(
      collection: collection,
      documentIds: ids.toSet(),
      documents: const {},
      hasUnknownDocuments: false,
      isExternal: false,
      revision: null,
    );
  }

  factory CindelChangeSet.native({
    required String collection,
    required int revision,
    required Iterable<int> ids,
    Map<int, CindelDocument> documents = const {},
    bool hasUnknownDocuments = false,
  }) {
    final documentCopies = {
      for (final entry in documents.entries)
        entry.key: Map<String, Object?>.of(entry.value),
    };
    return CindelChangeSet._(
      collection: collection,
      documentIds: ids.toSet(),
      documents: Map<int, CindelDocument>.unmodifiable(documentCopies),
      hasUnknownDocuments: hasUnknownDocuments,
      isExternal: false,
      revision: revision,
    );
  }

  final String collection;

  /// Changed document ids, or `null` when the exact ids are unknown.
  final Set<int>? documentIds;

  /// Documents written by this handle, keyed by id when available.
  final Map<int, CindelDocument> documents;

  /// Whether this change includes local writes whose document value is not
  /// available to Dart.
  final bool hasUnknownDocuments;

  /// Whether this change was detected from another handle through revision
  /// polling instead of from local write metadata.
  final bool isExternal;

  /// Native collection revision after the commit, when delivered by the native
  /// change-set path.
  final int? revision;

  bool mayAffectDocument(int id) {
    final ids = documentIds;
    return ids == null || ids.contains(id);
  }
}

final class _CindelChangeSetBuilder {
  _CindelChangeSetBuilder(this.collection);

  final String collection;
  final Set<int> _documentIds = {};
  final Map<int, CindelDocument> _documents = {};
  bool _unknownIds = false;
  bool _hasUnknownDocuments = false;

  void add(CindelChangeSet change) {
    if (change.documentIds == null) {
      _unknownIds = true;
    } else {
      _documentIds.addAll(change.documentIds!);
    }
    _hasUnknownDocuments = _hasUnknownDocuments || change.hasUnknownDocuments;
    for (final entry in change.documents.entries) {
      _documents[entry.key] = Map<String, Object?>.of(entry.value);
    }
  }

  CindelChangeSet build() {
    return CindelChangeSet._(
      collection: collection,
      documentIds: _unknownIds ? null : Set<int>.of(_documentIds),
      documents: Map<int, CindelDocument>.unmodifiable(_documents),
      hasUnknownDocuments: _hasUnknownDocuments,
      isExternal: false,
      revision: null,
    );
  }
}

abstract interface class _RegisteredWatcher {
  Future<void> poll({bool force, CindelChangeSet? change});

  Future<void> close();
}

final class _CindelWatcher<T> implements _RegisteredWatcher {
  _CindelWatcher({
    required Duration pollInterval,
    required bool fireImmediately,
    required bool Function() shouldPoll,
    required int Function() readRevision,
    required bool Function(CindelChangeSet change) shouldReadChange,
    required Future<T> Function(CindelChangeSet? change) readSnapshot,
    required bool Function(T left, T right)? areSnapshotsEqual,
    required void Function() onListen,
    required void Function() onCancel,
  }) : _pollInterval = pollInterval,
       _fireImmediately = fireImmediately,
       _shouldPoll = shouldPoll,
       _readRevision = readRevision,
       _shouldReadChange = shouldReadChange,
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
  final bool Function(CindelChangeSet change) _shouldReadChange;
  final Future<T> Function(CindelChangeSet? change) _readSnapshot;
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
      _lastSnapshot = await _readSnapshot(null);
      _hasLastSnapshot = true;
    } catch (error, stackTrace) {
      if (!_controller.isClosed) {
        _controller.addError(error, stackTrace);
      }
    } finally {
      _isPolling = false;
    }
  }

  Future<void> poll({bool force = false, CindelChangeSet? change}) async {
    if (_isPolling || _controller.isClosed) {
      return;
    }
    if (!force && !_shouldPoll()) {
      return;
    }
    _isPolling = true;
    try {
      final revision = change?.revision ?? _readRevision();
      if (!force && change != null && !_shouldReadChange(change)) {
        _lastRevision = revision;
        return;
      }
      if (!force && revision == _lastRevision) {
        return;
      }
      _lastRevision = revision;
      final snapshot = await _readSnapshot(change);
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
