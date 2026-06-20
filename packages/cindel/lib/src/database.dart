import 'dart:async';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:cindel_annotations/cindel_annotations.dart';

import 'cindel_error.dart';
import 'migration.dart';
import 'native/bindings.dart';
import 'native/wire.dart';
import 'schema.dart';

part 'database/native_query_plan.dart';
part 'database/document_codecs.dart';
part 'database/change_set.dart';

/// Internal map-shaped document representation used by Cindel runtime bridges.
///
/// Values must be compatible with Cindel's persisted document format: `null`,
/// `bool`, finite numbers, `String`, lists, and string-keyed maps.
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
///
/// This class is the runtime boundary between public Dart APIs, generated typed
/// collection helpers, and the native storage engine. Generated paths use
/// binary document serializers and native query plans for lower overhead.
class CindelDatabase {
  CindelDatabase._({
    required this.directory,
    required CindelNativeBindings bindings,
    required Pointer<Void> handle,
    required Map<String, CindelCollectionSchema<dynamic>> schemas,
    required this.backend,
    required bool schemasWereRegisteredOnOpen,
  }) : _bindings = bindings,
       _handle = handle,
       _schemas = Map.of(schemas),
       _schemasWereRegisteredOnOpen = schemasWereRegisteredOnOpen;

  /// The directory where the database files are stored.
  final String directory;

  /// The native storage backend selected for this database handle.
  final CindelStorageBackend backend;

  final CindelNativeBindings _bindings;
  final Map<String, CindelCollectionSchema<dynamic>> _schemas;
  bool _schemasWereRegisteredOnOpen;
  final Map<String, Set<_RegisteredWatcher>> _watchersByCollection = {};
  final Map<String, _CindelChangeSetBuilder> _changesInTransaction = {};
  Pointer<Void>? _handle;
  _TransactionMode? _activeTransaction;

  /// Whether SQLite can use generated native document readers for this handle.
  bool get usesSqliteNativeDocuments =>
      backend == CindelStorageBackend.sqlite && _schemasWereRegisteredOnOpen;

  // Opening and lifecycle.

  /// Opens a database stored under [directory].
  ///
  /// Throws an [ArgumentError] when [directory] is empty and a
  /// [CindelOpenError] when the native engine cannot be opened.
  static Future<CindelDatabase> open({
    required String directory,
    Iterable<CindelCollectionSchema<dynamic>> schemas = const [],
    CindelStorageBackend backend = defaultCindelStorageBackend,
    CindelMigrationPlan? migrationPlan,
  }) async {
    _checkDirectory(directory);
    final usePersistedSchemaMetadata = migrationPlan != null;
    if (migrationPlan != null) {
      await migrationPlan.run(
        directory: directory,
        targetSchemas: schemas,
        backend: backend,
      );
    }
    return _openUnchecked(
      directory: directory,
      schemas: schemas,
      backend: backend,
      persistSchemaMetadata: usePersistedSchemaMetadata,
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

  /// Opens a database handle suitable for controlled migration callbacks.
  static Future<CindelDatabase> openForMigration({
    required String directory,
    Iterable<CindelCollectionSchema<dynamic>> schemas = const [],
    CindelStorageBackend backend = defaultCindelStorageBackend,
  }) {
    _checkDirectory(directory);
    return _openUnchecked(
      directory: directory,
      schemas: schemas,
      backend: backend,
      persistSchemaMetadata: true,
    );
  }

  static Future<CindelDatabase> _openUnchecked({
    required String directory,
    required Iterable<CindelCollectionSchema<dynamic>> schemas,
    required CindelStorageBackend backend,
    bool persistSchemaMetadata = false,
  }) async {
    final schemasByCollection = _schemasByCollection(schemas);
    final schemaManifest = schemasByCollection.isEmpty
        ? null
        : _encodeSchemaManifest(schemasByCollection.values);
    final schemaManifestForOpen =
        !persistSchemaMetadata &&
            schemaManifest != null &&
            (backend != CindelStorageBackend.sqlite ||
                _canOpenSqliteWithNativeSchemas(schemasByCollection.values))
        ? schemaManifest
        : null;
    final database = await _openRaw(
      directory: directory,
      schemasByCollection: schemasByCollection,
      backend: backend,
      schemaManifest: schemaManifestForOpen,
    );
    if (schemaManifest != null && !database._schemasWereRegisteredOnOpen) {
      try {
        database._bindings.registerSchemas(
          database._checkOpen(),
          schemaManifest,
        );
        if (persistSchemaMetadata &&
            backend == CindelStorageBackend.sqlite &&
            _canOpenSqliteWithNativeSchemas(schemasByCollection.values)) {
          database._schemasWereRegisteredOnOpen = true;
        }
      } catch (_) {
        await database.close();
        rethrow;
      }
    }
    return database;
  }

  static bool _canOpenSqliteWithNativeSchemas(
    Iterable<CindelCollectionSchema<dynamic>> schemas,
  ) {
    for (final schema in schemas) {
      final dynamic dynamicSchema = schema;
      if (dynamicSchema.writeNativeDocument == null ||
          dynamicSchema.readNativeDocument == null) {
        return false;
      }
    }
    return true;
  }

  static Future<CindelDatabase> _openRaw({
    required String directory,
    required Map<String, CindelCollectionSchema<dynamic>> schemasByCollection,
    required CindelStorageBackend backend,
    required Uint8List? schemaManifest,
  }) async {
    final bindings = CindelNativeBindings();
    var schemasWereRegisteredOnOpen = false;
    var handle = nullptr.cast<Void>();
    if (schemaManifest != null) {
      handle = bindings.openWithSchemas(
        directory,
        schemaManifest,
        backend: backend._nativeId,
      );
      schemasWereRegisteredOnOpen = handle != nullptr;
    }
    if (handle == nullptr) {
      handle = bindings.open(directory, backend: backend._nativeId);
    }
    if (handle == nullptr) {
      throw CindelOpenError(backend: backend.name);
    }
    return CindelDatabase._(
      directory: directory,
      backend: backend,
      bindings: bindings,
      handle: handle,
      schemas: schemasByCollection,
      schemasWereRegisteredOnOpen: schemasWereRegisteredOnOpen,
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
  /// this database handle. Write operations inside [readTxn] throw
  /// [CindelTransactionError].
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

  /// Whether this handle is currently inside a write transaction.
  bool get isInWriteTransaction => _activeTransaction == _TransactionMode.write;

  // Generated binary and native typed writes.

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
      collection,
      () => CindelChangeSet.upsert(collection, id, document),
    );
  }

  /// Stores generated binary documents atomically.
  ///
  /// [values] contains already-encoded generated binary payloads keyed by id.
  /// [documents] is optional watcher metadata; when omitted, watchers still see
  /// affected ids but may need to read fresh snapshots from storage.
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
      collection,
      () => CindelChangeSet.upserts(collection, documents, ids: values.keys),
    );
  }

  /// Stores generated typed objects through the native binary document writer.
  ///
  /// [fieldTypes] describes the generated native field layout. [writeDocument]
  /// writes each object into the native batch writer. [documents] is only used
  /// when local watchers need Dart document snapshots for the written objects.
  Future<void> putAllNativeBinaryDocuments<T>(
    String collection,
    List<int> ids,
    List<T> objects,
    Uint8List fieldTypes,
    CindelWriteNativeDocument<T> writeDocument, {
    Map<int, CindelDocument>? Function()? documents,
  }) async {
    final handle = _checkOpen();
    _checkCanWrite();
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
      backend == CindelStorageBackend.sqlite,
    );
    _markNativeCollectionChanged(
      collection,
      () => CindelChangeSet.upserts(collection, documents?.call(), ids: ids),
    );
  }

  /// Stores generated typed objects through the native writer in one Dart pass.
  ///
  /// The native side obtains ids through [getId] while [writeDocument] writes
  /// each object. This avoids building a separate id list before the batch.
  Future<void> putAllNativeBinaryObjects<T>(
    String collection,
    List<T> objects,
    Uint8List fieldTypes,
    CindelGetId<T> getId,
    CindelWriteNativeDocument<T> writeDocument,
  ) async {
    final handle = _checkOpen();
    _checkCanWrite();
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
      backend == CindelStorageBackend.sqlite,
    );
    _markNativeCollectionChanged(
      collection,
      () => CindelChangeSet.upserts(collection, null),
    );
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

  /// Returns raw generated binary document bytes, or `null`.
  ///
  /// This is used by generated typed code and requires the MDBX binary backend.
  Future<Uint8List?> getBinaryDocument(String collection, int id) async {
    final handle = _checkOpen();
    _checkBinaryBackend();
    _checkCollection(collection);
    _checkId(id);

    return _bindings.getStored(handle, collection, id);
  }

  /// Returns raw generated binary document bytes, preserving input order.
  ///
  /// Missing documents are returned as `null`.
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
  ///
  /// Returned values preserve [ids] order and include `null` for missing
  /// documents.
  Future<List<T?>> getAllNativeBinaryDocuments<T>(
    String collection,
    Iterable<int> ids,
    Uint8List fieldTypes,
    CindelReadNativeDocument<T> readDocument,
  ) async {
    final handle = _checkOpen();
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
  ///
  /// This is the fast path for generated MDBX queries and SQLite native
  /// document queries when the backend can stream matching rows directly.
  Future<List<T>> queryNativePlanObjects<T>(
    String collection,
    CindelNativeQueryPlan plan,
    Uint8List fieldTypes,
    CindelReadNativeDocument<T> readDocument,
  ) async {
    final handle = _checkOpen();
    _checkNativeQueryBackend();
    _checkCollection(collection);
    return _bindings.queryPlanNativeDocuments(
      handle,
      collection,
      _encodeNativeQueryPlan(collection, plan),
      fieldTypes,
      readDocument,
    );
  }

  /// Returns every id in [collection], ordered ascending.
  Future<List<int>> documentIds(String collection) async {
    final handle = _checkOpen();
    _checkCollection(collection);

    return _bindings.documentIds(handle, collection);
  }

  // Deletes.

  /// Deletes the document stored in [collection] under [id], if it exists.
  ///
  /// Throws an [ArgumentError] when [collection] or [id] is invalid. Throws a
  /// [CindelDatabaseClosedError] when this database is already closed or a
  /// [CindelNativeError] when the native delete fails.
  Future<void> delete(String collection, int id) async {
    final handle = _checkOpen();
    _checkCanWrite();
    _checkCollection(collection);
    _checkId(id);

    _bindings.delete(handle, collection, id);
    _markNativeCollectionChanged(
      collection,
      () => CindelChangeSet.delete(collection, id),
    );
  }

  /// Deletes every document under [ids] atomically.
  ///
  /// Empty [ids] is a no-op.
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
    _markNativeCollectionChanged(
      collection,
      () => CindelChangeSet.deletes(collection, idList),
    );
  }

  /// Deletes generated typed SQLite-native documents atomically.
  ///
  /// This path is used when SQLite stores generated schema-aware rows in native
  /// collection tables instead of generic binary payloads.
  Future<void> deleteAllNativeDocuments(
    String collection,
    Iterable<int> ids,
  ) async {
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

    _bindings.deleteManyNativeDocuments(handle, collection, _encodeIds(idList));
    _markNativeCollectionChanged(
      collection,
      () => CindelChangeSet.deletes(collection, idList),
    );
  }

  /// Returns ids whose indexed [field] equals [value].
  ///
  /// Hash indexes are not exposed through id-only queries because collisions
  /// need typed document verification before the result is observable.
  Future<List<int>> queryEqualIds(
    String collection,
    String field,
    Object value,
  ) async {
    _checkCollection(collection);
    _checkIndexName(field);
    final schemaField = _checkIndexedField(collection, field);
    if (schemaField.indexType == CindelIndexType.hash) {
      throw CindelQueryError(
        'Hash index `${schemaField.name}` requires document verification.',
      );
    }
    final ids =
        _querySqliteNativeIndexEqualRawIds(
          collection,
          field,
          value,
          schemaField,
        ) ??
        _queryEqualRawIds(collection, field, value, schemaField);
    return schemaField.indexType == CindelIndexType.words
        ? _dedupeIds(ids)
        : ids;
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
      throw CindelQueryError(
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

    final ids =
        _querySqliteNativeIndexRangeRawIds(
          collection,
          field,
          lower,
          upper,
          schemaField,
        ) ??
        _queryRangeRawIds(
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

  // Native binary-document operations over explicit candidate ids.

  /// Applies a native binary-document filter to [candidateIds].
  ///
  /// [filter] is an encoded wire filter produced by query planning code.
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
  ///
  /// The result order follows [candidateIds] after native filtering of missing
  /// documents.
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
      throw CindelNativeError(
        'Native Cindel returned an invalid projection shape.',
      );
    }
    return [for (final cell in rows.cells) _wireValueToObject(cell)];
  }

  /// Aggregates [field] from native binary documents under [candidateIds].
  ///
  /// [operation] must be one of the supported native aggregate names:
  /// `count`, `min`, `max`, `sum`, or `average`.
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

  // Native query-plan execution.

  /// Returns ids matched by [plan].
  ///
  /// The plan is encoded and executed by the native query planner.
  Future<List<int>> queryNativePlanIds(
    String collection,
    CindelNativeQueryPlan plan,
  ) async {
    final handle = _checkOpen();
    _checkNativeQueryBackend();
    _checkCollection(collection);
    return _bindings.queryPlanIds(
      handle,
      collection,
      _encodeNativeQueryPlan(collection, plan),
    );
  }

  /// Returns the number of documents matched by [plan].
  Future<int> queryNativePlanCount(
    String collection,
    CindelNativeQueryPlan plan,
  ) async {
    final handle = _checkOpen();
    _checkNativeQueryBackend();
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
    throw CindelNativeError(
      'Native Cindel returned a non-integer query count.',
    );
  }

  /// Projects [field] from documents matched by [plan].
  Future<List<Object?>> queryNativePlanProjection(
    String collection,
    CindelNativeQueryPlan plan,
    String field,
  ) async {
    final handle = _checkOpen();
    _checkNativeQueryBackend();
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
      throw CindelNativeError(
        'Native Cindel returned an invalid projection shape.',
      );
    }
    return [for (final cell in rows.cells) _wireValueToObject(cell)];
  }

  /// Aggregates [field] over documents matched by [plan].
  ///
  /// [operation] must be one of the supported native aggregate names:
  /// `count`, `min`, `max`, `sum`, or `average`.
  Future<Object?> queryNativePlanAggregate(
    String collection,
    CindelNativeQueryPlan plan,
    String field,
    String operation,
  ) async {
    final handle = _checkOpen();
    _checkNativeQueryBackend();
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

  /// Deletes documents matched by [plan] and returns deleted ids.
  Future<List<int>> deleteNativePlan(
    String collection,
    CindelNativeQueryPlan plan,
  ) async {
    final handle = _checkOpen();
    _checkCanWrite();
    _checkNativeQueryBackend();
    _checkCollection(collection);
    final ids = _bindings.queryPlanDelete(
      handle,
      collection,
      _encodeNativeQueryPlan(collection, plan),
    );
    if (ids.isNotEmpty) {
      _markNativeCollectionChanged(
        collection,
        () => CindelChangeSet.deletes(collection, ids),
      );
    }
    return ids;
  }

  /// Applies native field updates to documents matched by [plan].
  ///
  /// Returns the number of updated documents. [updates] must already be encoded
  /// as wire values by the query layer.
  Future<int> updateNativePlan(
    String collection,
    CindelNativeQueryPlan plan,
    Map<String, WireValue> updates,
  ) async {
    final handle = _checkOpen();
    _checkCanWrite();
    _checkNativeQueryBackend();
    _checkCollection(collection);
    if (updates.isEmpty) {
      return 0;
    }
    final count = _bindings.queryPlanUpdate(
      handle,
      collection,
      _encodeNativeQueryPlan(collection, plan),
      encodeFieldUpdates(updates),
      _activeTransaction == _TransactionMode.write || _hasWatchers(collection),
    );
    if (count > 0) {
      _markNativeCollectionChanged(
        collection,
        () => CindelChangeSet.external(collection),
      );
    }
    return count;
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

  /// Returns the persisted database data migration version, or `null`.
  Future<int?> migrationVersion() async {
    final handle = _checkOpen();
    return _bindings.migrationVersion(handle);
  }

  /// Persists the database data migration [version].
  Future<void> setMigrationVersion(int version) async {
    final handle = _checkOpen();
    _checkCanWrite();
    _bindings.setMigrationVersion(handle, version);
  }

  /// Registers [schemas] after caller-controlled data migration.
  ///
  /// Unlike [Cindel.open]'s normal schema registration, this method accepts
  /// incompatible schema changes and clears storage for the migrated target
  /// collections so callers can import the rewritten documents.
  Future<void> registerMigratedSchemas(
    Iterable<CindelCollectionSchema<dynamic>> schemas,
  ) async {
    final schemasByCollection = _schemasByCollection(schemas);
    final handle = _checkOpen();
    _checkCanWrite();
    _bindings.registerMigratedSchemas(
      handle,
      _encodeSchemaManifest(schemasByCollection.values),
    );
    _schemas
      ..clear()
      ..addAll(schemasByCollection);
    _schemasWereRegisteredOnOpen = true;
  }

  /// Requests backend-level compaction for this database.
  Future<void> compact() async {
    final handle = _checkOpen();
    _checkCanWrite();
    _bindings.compact(handle);
  }

  // State and transaction guards.

  Pointer<Void> _checkOpen() {
    final handle = _handle;
    if (handle == null) {
      throw CindelDatabaseClosedError();
    }
    return handle;
  }

  void _checkCanWrite() {
    if (_activeTransaction == _TransactionMode.read) {
      throw CindelTransactionError(
        'Cannot write inside a Cindel read transaction.',
      );
    }
  }

  Future<T> _runTransaction<T>(
    _TransactionMode mode,
    Future<T> Function() action,
  ) async {
    final handle = _checkOpen();
    if (_activeTransaction != null) {
      throw CindelTransactionError(
        'Cindel does not support nested transactions yet.',
      );
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

  // Schema and query-plan helpers.

  CindelFieldSchema _checkIndexedField(String collection, String field) {
    final schema = _schemas[collection];
    if (schema == null) {
      throw CindelSchemaError(
        'Collection `$collection` has no registered Cindel schema.',
      );
    }

    for (final schemaField in schema.fields) {
      if (schemaField.name == field && schemaField.isIndexed) {
        return schemaField;
      }
    }

    throw CindelQueryError('Field `$field` is not indexed for `$collection`.');
  }

  void _checkBinaryBackend() {
    if (backend != CindelStorageBackend.mdbx) {
      throw CindelSchemaError(
        'Cindel binary documents require the MDBX storage backend.',
      );
    }
  }

  void _checkNativeQueryBackend() {
    if (backend == CindelStorageBackend.mdbx || usesSqliteNativeDocuments) {
      return;
    }
    throw CindelQueryError(
      'Native Cindel query plans require MDBX or SQLite native documents.',
    );
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

  /// Returns ids whose composite [indexName] equals [values].
  ///
  /// Composite values are matched in the order declared by the generated schema.
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
      throw CindelSchemaError(
        'Collection `$collection` has no registered Cindel schema.',
      );
    }
    final composite = schema.compositeIndexes.firstWhere(
      (index) => index.name == indexName,
      orElse: () => throw CindelQueryError(
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
            isIndexReplace: field.isIndexReplace,
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
      throw CindelSchemaError(
        'Collection `$collection` has no registered Cindel schema.',
      );
    }
    final composite = schema.compositeIndexes.firstWhere(
      (index) => index.name == indexName,
      orElse: () => throw CindelQueryError(
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
      isIndexReplace: schemaField.isIndexReplace,
      indexCaseSensitive: caseSensitive,
      indexType: schemaField.indexType,
    );
  }

  CindelFieldSchema _indexedFieldSchema(String collection, String field) {
    final schemaField = _requireSchemaField(collection, field);
    if (!schemaField.isIndexed) {
      throw CindelQueryError(
        'Field `$field` is not indexed for `$collection`.',
      );
    }
    return schemaField;
  }

  CindelFieldSchema _requireSchemaField(String collection, String field) {
    final schemaField = _fieldSchema(collection, field);
    if (schemaField == null) {
      throw CindelSchemaError(
        'Field `$field` is not registered for `$collection`.',
      );
    }
    return schemaField;
  }

  CindelCollectionSchema<dynamic>? _sqliteNativeSchema(String collection) {
    if (!usesSqliteNativeDocuments) {
      return null;
    }
    final schema = _schemas[collection];
    final dynamic dynamicSchema = schema;
    if (schema == null ||
        dynamicSchema.writeNativeDocument == null ||
        dynamicSchema.readNativeDocument == null ||
        _nativeFieldTypes(schema) == null) {
      return null;
    }
    return schema;
  }

  // SQLite-native index source helpers.

  List<int>? _querySqliteNativeIndexEqualRawIds(
    String collection,
    String field,
    Object value,
    CindelFieldSchema schemaField,
  ) {
    if (!_canUseSqliteNativeIndexSource(collection, schemaField)) {
      return null;
    }
    final handle = _checkOpen();
    final plan = CindelNativeQueryPlan(
      source: CindelNativeIndexEqualQuerySource(
        indexName: field,
        value: value,
        dedupe: schemaField.indexType == CindelIndexType.words,
      ),
    );
    return _bindings.queryPlanIds(
      handle,
      collection,
      _encodeNativeQueryPlan(collection, plan),
    );
  }

  List<int>? _querySqliteNativeIndexRangeRawIds(
    String collection,
    String field,
    Object? lower,
    Object? upper,
    CindelFieldSchema schemaField,
  ) {
    if (!_canUseSqliteNativeIndexSource(collection, schemaField)) {
      return null;
    }
    final handle = _checkOpen();
    final plan = CindelNativeQueryPlan(
      source: CindelNativeIndexRangeQuerySource(
        indexName: field,
        lower: lower,
        upper: upper,
        dedupe: schemaField.indexType == CindelIndexType.words,
      ),
    );
    return _bindings.queryPlanIds(
      handle,
      collection,
      _encodeNativeQueryPlan(collection, plan),
    );
  }

  bool _canUseSqliteNativeIndexSource(
    String collection,
    CindelFieldSchema field,
  ) {
    if (_sqliteNativeSchema(collection) == null) {
      return false;
    }
    if (!field.indexCaseSensitive && field.binaryType == 'string') {
      return false;
    }
    return field.indexType != CindelIndexType.words &&
        field.indexType != CindelIndexType.multiEntry;
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

  // Watcher plumbing.

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
          throw CindelDatabaseClosedError();
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

  /// Watches raw collection change metadata.
  ///
  /// This stream is primarily used by query watchers that can decide whether a
  /// local write can be skipped without re-reading the full query snapshot.
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

  void _markNativeCollectionChanged(
    String collection,
    CindelChangeSet Function() localChangeFactory,
  ) {
    if (_activeTransaction == _TransactionMode.write) {
      _markCollectionChanged(localChangeFactory());
      return;
    }

    final handle = _checkOpen();
    if (!_hasWatchers(collection)) {
      _bindings.discardChanges(handle);
      return;
    }
    final localChange = localChangeFactory();
    final changes = _changesFromNative(_takeNativeChangeSets(handle), {
      localChange.collection: localChange,
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
    if (nativeChanges.isEmpty) {
      return [
        for (final change in localChanges.values)
          if (change.hasUnknownDocuments || change.documents.isNotEmpty) change,
      ];
    }
    final builders = <String, _CindelChangeSetBuilder>{};
    for (final change in nativeChanges) {
      builders
          .putIfAbsent(
            change.collection,
            () => _CindelChangeSetBuilder(change.collection),
          )
          .add(_changeFromNative(change, localChanges[change.collection]));
    }
    return [for (final builder in builders.values) builder.build()];
  }

  CindelChangeSet _changeFromNative(
    WireChangeSet change,
    CindelChangeSet? localChange,
  ) {
    final nativeIds = change.documentIds.toSet();
    final ids = nativeIds.isEmpty && localChange?.documentIds != null
        ? localChange!.documentIds!.toSet()
        : nativeIds;
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
