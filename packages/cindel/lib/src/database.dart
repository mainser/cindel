import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:cindel_annotations/cindel_annotations.dart';

import 'binary_document.dart';
import 'cindel_error.dart';
import 'migration.dart';
import 'native/bindings.dart';
import 'native/wire.dart';
import 'schema.dart';
import 'sync.dart';

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

// Reserved internal collections used only by the sync sidecar. They are added
// to the schema manifest when sync is enabled, but never become part of the
// generated app-facing typed API.
const _syncOutboxCollection = '__cindel_sync_outbox';
const _syncStateCollection = '__cindel_sync_state';

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
    required CindelSyncConfig? syncConfig,
  }) : _bindings = bindings,
       _handle = handle,
       _schemas = Map.of(schemas),
       _schemasWereRegisteredOnOpen = schemasWereRegisteredOnOpen,
       _syncSession = syncConfig == null
           ? null
           : _CindelSyncSession(syncConfig);

  /// The directory where the database files are stored.
  final String directory;

  /// The native storage backend selected for this database handle.
  final CindelStorageBackend backend;

  final CindelNativeBindings _bindings;
  final Map<String, CindelCollectionSchema<dynamic>> _schemas;
  bool _schemasWereRegisteredOnOpen;
  final Map<String, Set<_RegisteredWatcher>> _watchersByCollection = {};
  final Map<String, _CindelChangeSetBuilder> _changesInTransaction = {};
  final _CindelSyncSession? _syncSession;
  Pointer<Void>? _handle;
  _TransactionMode? _activeTransaction;

  // Sync writes its own outbox/state rows through the same storage paths as app
  // data. These flags prevent those internal writes and remote apply writes
  // from recursively creating new outgoing sync mutations.
  bool _syncInternalWrite = false;
  bool _syncRemoteApply = false;

  /// Whether SQLite can use generated native document readers for this handle.
  bool get usesSqliteNativeDocuments =>
      backend == CindelStorageBackend.sqlite && _schemasWereRegisteredOnOpen;

  // Opening and lifecycle.

  /// Opens a database stored under [directory].
  ///
  /// When [migrationPlan] is provided, Cindel runs controlled migration
  /// callbacks before opening the final handle with [schemas].
  ///
  /// Throws an [ArgumentError] when [directory] is empty and a
  /// [CindelOpenError] when the native engine cannot be opened.
  static Future<CindelDatabase> open({
    required String directory,
    Iterable<CindelCollectionSchema<dynamic>> schemas = const [],
    CindelStorageBackend backend = defaultCindelStorageBackend,
    CindelMigrationPlan? migrationPlan,
    CindelSyncConfig? sync,
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
      sync: sync,
    );
  }

  /// Opens an in-memory database.
  ///
  /// Data is discarded when this database is closed.
  static Future<CindelDatabase> openInMemory({
    Iterable<CindelCollectionSchema<dynamic>> schemas = const [],
    CindelStorageBackend backend = defaultCindelStorageBackend,
    CindelSyncConfig? sync,
  }) {
    return _openUnchecked(
      directory: _inMemoryDirectory,
      schemas: schemas,
      backend: backend,
      sync: sync,
    );
  }

  /// Opens a database handle suitable for controlled migration callbacks.
  ///
  /// This bypasses normal target-schema registration so a migration step can
  /// read old data, rewrite it, and then call [registerMigratedSchemas].
  static Future<CindelDatabase> openForMigration({
    required String directory,
    Iterable<CindelCollectionSchema<dynamic>> schemas = const [],
    CindelStorageBackend backend = defaultCindelStorageBackend,
    CindelSyncConfig? sync,
  }) {
    _checkDirectory(directory);
    return _openUnchecked(
      directory: directory,
      schemas: schemas,
      backend: backend,
      persistSchemaMetadata: true,
      sync: sync,
    );
  }

  static Future<CindelDatabase> _openUnchecked({
    required String directory,
    required Iterable<CindelCollectionSchema<dynamic>> schemas,
    required CindelStorageBackend backend,
    bool persistSchemaMetadata = false,
    CindelSyncConfig? sync,
  }) async {
    final schemasByCollection = _schemasByCollection(
      sync == null ? schemas : [...schemas, ..._syncInternalSchemas],
    );
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
      sync: sync,
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
    await database._syncSession?.start(database);
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
    required CindelSyncConfig? sync,
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
      syncConfig: sync,
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
    await _syncSession?.close();
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
    if (_syncShouldWrapLocalWrite(collection)) {
      return writeTxn(
        () => putBinaryDocument(collection, id, bytes, document: document),
      );
    }
    final handle = _checkOpen();
    _checkCanWrite();
    _checkBinaryBackend();
    _checkCollection(collection);
    _checkId(id);
    _syncCheckCanonicalUpsert(collection, id, document);

    _bindings.putIndexed(handle, collection, id, bytes, Uint8List(0));
    await _syncRecordUpsert(collection, id, document);
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
    if (_syncShouldWrapLocalWrite(collection)) {
      return writeTxn(
        () => putAllBinaryDocuments(collection, values, documents: documents),
      );
    }
    final handle = _checkOpen();
    _checkCanWrite();
    _checkBinaryBackend();
    _checkCollection(collection);
    if (values.isEmpty) {
      return;
    }
    for (final id in values.keys) {
      _checkId(id);
      _syncCheckCanonicalUpsert(collection, id, documents?[id]);
    }

    _bindings.putManyStored(
      handle,
      collection,
      _encodeBinaryBatchPutEntries(values),
    );
    for (final id in values.keys) {
      await _syncRecordUpsert(collection, id, documents?[id]);
    }
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
    if (_syncShouldWrapLocalWrite(collection)) {
      return writeTxn(
        () => putAllNativeBinaryDocuments(
          collection,
          ids,
          objects,
          fieldTypes,
          writeDocument,
          documents: documents,
        ),
      );
    }
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
    await _syncRecordNativeUpserts(collection, ids, objects, documents);
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
    if (_syncShouldWrapLocalWrite(collection)) {
      return writeTxn(
        () => putAllNativeBinaryObjects(
          collection,
          objects,
          fieldTypes,
          getId,
          writeDocument,
        ),
      );
    }
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
    await _syncRecordNativeUpserts(
      collection,
      [for (final object in objects) getId(object)],
      objects,
      null,
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

  /// Returns up to [limit] ids in [collection] after [afterId], ordered ascending.
  ///
  /// This is intended for backup/export and maintenance flows that need to
  /// scan very large collections without materializing every id at once.
  Future<List<int>> documentIdsPage(
    String collection, {
    int? afterId,
    int limit = 1000,
  }) async {
    final handle = _checkOpen();
    _checkCollection(collection);
    if (afterId != null) {
      _checkId(afterId);
    }
    _checkPageLimit(limit);

    return _bindings.documentIdsPage(
      handle,
      collection,
      afterId: afterId,
      limit: limit,
    );
  }

  /// Returns the generated id for [object] in [collection].
  int cindelObjectId(String collection, Object object) {
    final schema = _schemas[collection];
    final dynamic dynamicSchema = schema;
    if (schema == null || dynamicSchema.getId == null) {
      throw CindelSchemaError(
        'Collection `$collection` has no generated id accessor.',
      );
    }
    final id = dynamicSchema.getId(object) as int;
    _checkId(id);
    if (id == autoIncrement) {
      throw StateError('Linked objects must be persisted before save().');
    }
    return id;
  }

  /// Replaces persisted relation ids for one forward link.
  Future<void> saveLinkIds({
    required String sourceCollection,
    required int sourceId,
    required String linkName,
    required String targetCollection,
    required Iterable<int> targetIds,
  }) async {
    if (_syncShouldWrapLocalWrite(sourceCollection)) {
      return writeTxn(
        () => saveLinkIds(
          sourceCollection: sourceCollection,
          sourceId: sourceId,
          linkName: linkName,
          targetCollection: targetCollection,
          targetIds: targetIds,
        ),
      );
    }
    final handle = _checkOpen();
    _checkCanWrite();
    _checkCollection(sourceCollection);
    _checkCollection(targetCollection);
    _checkId(sourceId);
    final ids = targetIds.toSet().toList(growable: false)..sort();
    for (final id in ids) {
      _checkId(id);
    }
    _bindings.replaceLinks(
      handle,
      sourceCollection: sourceCollection,
      sourceId: sourceId,
      linkName: linkName,
      targetCollection: targetCollection,
      targetIds: _encodeIds(ids),
    );
    await _syncRecordReplaceLinks(
      sourceCollection: sourceCollection,
      sourceId: sourceId,
      linkName: linkName,
      targetCollection: targetCollection,
      targetIds: ids,
    );
    _markNativeCollectionChanged(
      sourceCollection,
      () => CindelChangeSet.upsert(sourceCollection, sourceId, null),
    );
  }

  /// Loads objects reached by a forward link.
  Future<List<T>> loadLinkedObjects<T>({
    required String sourceCollection,
    required int sourceId,
    required String linkName,
    required String targetCollection,
  }) async {
    final handle = _checkOpen();
    _checkCollection(sourceCollection);
    _checkCollection(targetCollection);
    _checkId(sourceId);
    final ids = _bindings.forwardLinkIds(
      handle,
      sourceCollection: sourceCollection,
      sourceId: sourceId,
      linkName: linkName,
      targetCollection: targetCollection,
    );
    return _loadTypedObjectsByIds<T>(targetCollection, ids);
  }

  /// Loads objects reached by a backlink.
  Future<List<T>> loadBacklinkObjects<T>({
    required String ownerCollection,
    required int ownerId,
    required String sourceCollection,
    required String sourceLinkName,
  }) async {
    final handle = _checkOpen();
    _checkCollection(ownerCollection);
    _checkCollection(sourceCollection);
    _checkId(ownerId);
    final ids = _bindings.backlinkSourceIds(
      handle,
      targetCollection: ownerCollection,
      targetId: ownerId,
      sourceCollection: sourceCollection,
      linkName: sourceLinkName,
    );
    return _loadTypedObjectsByIds<T>(sourceCollection, ids);
  }

  Future<List<T>> _loadTypedObjectsByIds<T>(
    String collection,
    List<int> ids,
  ) async {
    final schema = _schemas[collection];
    if (schema == null) {
      throw CindelSchemaError(
        'Collection `$collection` has no registered Cindel schema.',
      );
    }
    final objects = usesSqliteNativeDocuments
        ? await _loadNativeObjectsByIds<T>(schema, ids)
        : await _loadBinaryObjectsByIds<T>(schema, ids);
    return [
      for (final object in objects)
        if (object != null) object,
    ];
  }

  Future<List<T?>> _loadBinaryObjectsByIds<T>(
    CindelCollectionSchema<dynamic> schema,
    List<int> ids,
  ) async {
    final documents = await getAllBinaryDocuments(schema.name, ids);
    return [
      for (var i = 0; i < documents.length; i += 1)
        if (documents[i] == null)
          null
        else
          _bindLoadedObject<T>(
            schema,
            schema.fromBinaryDocument!(documents[i]!),
            ids[i],
          ),
    ];
  }

  Future<List<T?>> _loadNativeObjectsByIds<T>(
    CindelCollectionSchema<dynamic> schema,
    List<int> ids,
  ) {
    final nativeReader = schema.readNativeDocument;
    final fieldTypes = _nativeFieldTypes(schema);
    if (nativeReader == null || fieldTypes == null) {
      return _loadBinaryObjectsByIds<T>(schema, ids);
    }
    return getAllNativeBinaryDocuments<dynamic>(
      schema.name,
      ids,
      fieldTypes,
      nativeReader,
    ).then((objects) {
      return [
        for (final object in objects)
          if (object == null)
            null
          else
            _bindLoadedObject<T>(schema, object, null),
      ];
    });
  }

  T _bindLoadedObject<T>(
    CindelCollectionSchema<dynamic> schema,
    Object object,
    int? id,
  ) {
    final dynamicSchema = schema as dynamic;
    if (id != null) {
      dynamicSchema.setId?.call(object, id);
    }
    dynamicSchema.bindLinks?.call(this, schema, object);
    return object as T;
  }

  // Deletes.

  /// Deletes the document stored in [collection] under [id], if it exists.
  ///
  /// Throws an [ArgumentError] when [collection] or [id] is invalid. Throws a
  /// [CindelDatabaseClosedError] when this database is already closed or a
  /// [CindelNativeError] when the native delete fails.
  Future<void> delete(String collection, int id) async {
    if (_syncShouldWrapLocalWrite(collection)) {
      return writeTxn(() => delete(collection, id));
    }
    final handle = _checkOpen();
    _checkCanWrite();
    _checkCollection(collection);
    _checkId(id);

    _bindings.delete(handle, collection, id);
    await _syncRecordDelete(collection, id);
    _markNativeCollectionChanged(
      collection,
      () => CindelChangeSet.delete(collection, id),
    );
  }

  /// Deletes every document under [ids] atomically.
  ///
  /// Empty [ids] is a no-op.
  Future<void> deleteAll(String collection, Iterable<int> ids) async {
    if (_syncShouldWrapLocalWrite(collection)) {
      return writeTxn(() => deleteAll(collection, ids));
    }
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
    for (final id in idList) {
      await _syncRecordDelete(collection, id);
    }
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
    if (_syncShouldWrapLocalWrite(collection)) {
      return writeTxn(() => deleteAllNativeDocuments(collection, ids));
    }
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
    for (final id in idList) {
      await _syncRecordDelete(collection, id);
    }
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
    if (_syncShouldWrapLocalWrite(collection)) {
      return writeTxn(() => deleteNativePlan(collection, plan));
    }
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
      for (final id in ids) {
        await _syncRecordDelete(collection, id);
      }
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
    _syncCheckQueryUpdate(collection);
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
  ///
  /// This version is independent from per-collection schema versions and is
  /// advanced only by a successful [CindelMigrationPlan].
  Future<int?> migrationVersion() async {
    final handle = _checkOpen();
    return _bindings.migrationVersion(handle);
  }

  /// Persists the database data migration [version].
  ///
  /// Migration plans call this only after verification and target schema
  /// registration complete.
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
    final schemasByCollection = _schemasByCollection(
      _syncSession == null ? schemas : [...schemas, ..._syncInternalSchemas],
    );
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
  ///
  /// This is intended for migration cleanup after rewritten data has been
  /// verified and the target migration version has been persisted.
  Future<void> compact() async {
    final handle = _checkOpen();
    _checkCanWrite();
    _bindings.compact(handle);
  }

  bool _syncShouldWrapLocalWrite(String collection) {
    // A local write outside an explicit writeTxn must be wrapped so the app
    // mutation and its outbox row commit atomically.
    return _syncSession != null &&
        !_syncInternalWrite &&
        !_syncRemoteApply &&
        !_isSyncInternalCollection(collection) &&
        _activeTransaction == null;
  }

  void _syncCheckCanonicalUpsert(
    String collection,
    int id,
    CindelDocument? document,
  ) {
    // Sync sends complete document snapshots for upserts. Generated typed paths
    // provide that canonical map; raw low-level writes must opt in by passing
    // one explicitly or Cindel cannot produce a safe backend mutation.
    if (_syncSession == null ||
        _syncInternalWrite ||
        _syncRemoteApply ||
        _isSyncInternalCollection(collection)) {
      return;
    }
    if (document == null) {
      throw UnsupportedError(
        'Cindel sync requires a canonical document for raw writes to '
        '`$collection.$id`.',
      );
    }
  }

  void _syncCheckQueryUpdate(String collection) {
    // Query updates can affect many rows but currently do not produce
    // per-document snapshots. Reject them while sync is enabled instead of
    // silently sending incomplete mutations.
    if (_syncSession == null ||
        _syncInternalWrite ||
        _syncRemoteApply ||
        _isSyncInternalCollection(collection)) {
      return;
    }
    throw UnsupportedError(
      'Cindel sync does not support query update operations yet. Rewrite '
      'matching objects and call putAll, or open the database without sync.',
    );
  }

  Future<void> _syncRecordUpsert(
    String collection,
    int id,
    CindelDocument? document,
  ) async {
    // Called from write paths after the storage mutation has been accepted by
    // the backend bridge but before the surrounding write transaction commits.
    final session = _syncSession;
    if (session == null ||
        _syncInternalWrite ||
        _syncRemoteApply ||
        _isSyncInternalCollection(collection)) {
      return;
    }
    _syncCheckCanonicalUpsert(collection, id, document);
    await session.recordUpsert(collection, id, document!);
  }

  Future<void> _syncRecordNativeUpserts<T>(
    String collection,
    List<int> ids,
    List<T> objects,
    Map<int, CindelDocument>? Function()? documents,
  ) async {
    // Native typed writes may receive document snapshots from the generated
    // collection path. When they do not, rebuild the snapshot from the schema so
    // the adapter still sees a collection-agnostic mutation.
    final session = _syncSession;
    if (session == null ||
        _syncInternalWrite ||
        _syncRemoteApply ||
        _isSyncInternalCollection(collection)) {
      return;
    }
    final provided = documents?.call();
    final schema = _schemas[collection];
    if (schema == null) {
      throw CindelSchemaError('Collection `$collection` has no schema.');
    }
    if (ids.length != objects.length) {
      throw ArgumentError.value(ids.length, 'ids');
    }
    for (var i = 0; i < ids.length; i += 1) {
      final id = ids[i];
      final document =
          provided?[id] ?? _syncDocumentFromObject(schema, objects[i], id);
      await session.recordUpsert(collection, id, document);
    }
  }

  Future<void> _syncRecordDelete(String collection, int id) async {
    final session = _syncSession;
    if (session == null ||
        _syncInternalWrite ||
        _syncRemoteApply ||
        _isSyncInternalCollection(collection)) {
      return;
    }
    await session.recordDelete(collection, id);
  }

  Future<void> _syncRecordReplaceLinks({
    required String sourceCollection,
    required int sourceId,
    required String linkName,
    required String targetCollection,
    required List<int> targetIds,
  }) async {
    final session = _syncSession;
    if (session == null ||
        _syncInternalWrite ||
        _syncRemoteApply ||
        _isSyncInternalCollection(sourceCollection)) {
      return;
    }
    await session.recordReplaceLinks(
      sourceCollection: sourceCollection,
      sourceId: sourceId,
      linkName: linkName,
      targetCollection: targetCollection,
      targetIds: targetIds,
    );
  }

  CindelDocument _syncDocumentFromObject(
    CindelCollectionSchema<dynamic> schema,
    Object? object,
    int id,
  ) {
    final dynamic dynamicSchema = schema;
    final document = Map<String, Object?>.from(
      dynamicSchema.toDocument(object) as Map,
    );
    document[schema.idField] = id;
    return document;
  }

  Future<void> _syncPersistMutation(_CindelSyncOutboxRecord record) async {
    // SQLite uses native row storage for the internal outbox. MDBX keeps these
    // records as binary documents because its app-data path is binary-first.
    await _syncRunInternalWrite(() async {
      if (backend == CindelStorageBackend.mdbx) {
        await putAllBinaryDocuments(
          _syncOutboxCollection,
          {record.dbId: _encodeSyncOutboxRecord(record)},
          documents: {record.dbId: _syncOutboxSchema.toDocument(record)},
        );
        return;
      }
      final fieldTypes = _nativeFieldTypes(_syncOutboxSchema)!;
      await putAllNativeBinaryDocuments<_CindelSyncOutboxRecord>(
        _syncOutboxCollection,
        [record.dbId],
        [record],
        fieldTypes,
        _writeSyncOutboxRecord,
      );
    });
  }

  Future<void> _syncPersistState(String key, String? value) async {
    // State is kept in a separate internal collection so accepted outbox rows
    // can be deleted without losing client/checkpoint metadata.
    await _syncRunInternalWrite(() async {
      final record = _CindelSyncStateRecord(_syncStateId(key), key, value);
      if (backend == CindelStorageBackend.mdbx) {
        await putAllBinaryDocuments(
          _syncStateCollection,
          {record.dbId: _encodeSyncStateRecord(record)},
          documents: {record.dbId: _syncStateSchema.toDocument(record)},
        );
        return;
      }
      final fieldTypes = _nativeFieldTypes(_syncStateSchema)!;
      await putAllNativeBinaryDocuments<_CindelSyncStateRecord>(
        _syncStateCollection,
        [record.dbId],
        [record],
        fieldTypes,
        _writeSyncStateRecord,
      );
    });
  }

  Future<String?> _syncReadState(String key) async {
    if (backend == CindelStorageBackend.mdbx) {
      final bytes = (await getAllBinaryDocuments(_syncStateCollection, [
        _syncStateId(key),
      ])).single;
      return bytes == null ? null : _decodeSyncStateRecord(bytes).value;
    }
    final fieldTypes = _nativeFieldTypes(_syncStateSchema)!;
    final record = (await getAllNativeBinaryDocuments<_CindelSyncStateRecord>(
      _syncStateCollection,
      [_syncStateId(key)],
      fieldTypes,
      _readSyncStateRecord,
    )).single;
    return record?.value;
  }

  Future<List<_CindelSyncOutboxRecord>> _syncReadOutbox({
    required int limit,
  }) async {
    // Read by id page first so both MDBX binary rows and SQLite native rows use
    // the same scheduling order and batch-size behavior.
    final ids = await documentIdsPage(_syncOutboxCollection, limit: limit);
    if (ids.isEmpty) {
      return const [];
    }
    if (backend == CindelStorageBackend.mdbx) {
      final documents = await getAllBinaryDocuments(_syncOutboxCollection, ids);
      return [
        for (var i = 0; i < documents.length; i += 1)
          if (documents[i] != null)
            _decodeSyncOutboxRecord(ids[i], documents[i]!),
      ]..sort((left, right) => left.sequence.compareTo(right.sequence));
    }
    final fieldTypes = _nativeFieldTypes(_syncOutboxSchema)!;
    final records = await getAllNativeBinaryDocuments<_CindelSyncOutboxRecord>(
      _syncOutboxCollection,
      ids,
      fieldTypes,
      _readSyncOutboxRecord,
    );
    return [
      for (final record in records)
        if (record != null) record,
    ]..sort((left, right) => left.sequence.compareTo(right.sequence));
  }

  Future<int> _syncNextOutboxSequence() async {
    // Reopen must never reuse a mutation id while pending rows remain. The
    // persisted nextSequence state is the normal source, and this outbox scan is
    // the defensive fallback that caught the duplicate-id regression.
    var nextSequence = 1;
    int? afterId;
    while (true) {
      final ids = await documentIdsPage(
        _syncOutboxCollection,
        afterId: afterId,
      );
      if (ids.isEmpty) {
        return nextSequence;
      }
      nextSequence = ids.last + 1;
      afterId = ids.last;
    }
  }

  Future<void> _syncDeleteOutboxIds(Iterable<int> ids) async {
    // Accepted mutations are removed only after the adapter confirms their
    // mutation ids. Rejected or unknown ids stay pending for retry.
    final idList = ids.toList(growable: false);
    if (idList.isEmpty) {
      return;
    }
    await _syncRunInternalWrite(() {
      return backend == CindelStorageBackend.mdbx
          ? deleteAll(_syncOutboxCollection, idList)
          : deleteAllNativeDocuments(_syncOutboxCollection, idList);
    });
  }

  Future<Map<String, int>> _syncSchemaVersions() async {
    // Adapters should see only application collections. Internal sync
    // collections are implementation detail and must not leak into backend
    // collection lists.
    final versions = <String, int>{};
    for (final collection in _schemas.keys) {
      if (_isSyncInternalCollection(collection)) {
        continue;
      }
      versions[collection] = await schemaVersion(collection) ?? 1;
    }
    return versions;
  }

  Future<void> _syncApplyRemoteChanges(
    List<CindelRemoteChange> changes, {
    String? checkpoint,
  }) async {
    // Remote apply is still a normal write transaction so watchers update and
    // local storage stays atomic. The remote guard prevents echoing those
    // writes back into the outbox.
    if (changes.isEmpty && checkpoint == null) {
      return;
    }
    await writeTxn(() async {
      _syncRemoteApply = true;
      try {
        for (final change in changes) {
          await _syncApplyRemoteChange(change);
        }
        if (checkpoint != null) {
          await _syncPersistState('checkpoint', checkpoint);
        }
      } finally {
        _syncRemoteApply = false;
      }
    });
  }

  Future<void> _syncApplyRemoteChange(CindelRemoteChange change) async {
    switch (change) {
      case CindelRemoteUpsert(:final collection, :final id, :final document):
        final schema = _schemas[collection];
        if (schema == null) {
          throw CindelSchemaError(
            'Remote sync collection `$collection` is not registered.',
          );
        }
        final dynamic dynamicSchema = schema;
        final object = dynamicSchema.fromDocument({
          ...document,
          schema.idField: id,
        });
        final fieldTypes = _nativeFieldTypes(schema);
        final nativeWriter = dynamicSchema.writeNativeDocument as Function?;
        // SQLite prefers generated native row writes when available so remote
        // apply uses the same indexed storage shape as local typed puts.
        if (usesSqliteNativeDocuments &&
            nativeWriter != null &&
            fieldTypes != null) {
          await putAllNativeBinaryDocuments(
            collection,
            [id],
            [object],
            fieldTypes,
            (writer, value) => Function.apply(nativeWriter, [writer, value]),
            documents: () => {
              id: {...document, schema.idField: id},
            },
          );
          return;
        }
        final binaryWriter = dynamicSchema.toBinaryDocument as Function?;
        // MDBX and non-native typed paths write the generated binary document
        // body and keep the id outside the payload, matching local typed puts.
        if (binaryWriter != null) {
          await putBinaryDocument(
            collection,
            id,
            Function.apply(binaryWriter, [object]) as Uint8List,
            document: {...document, schema.idField: id},
          );
          return;
        }
        throw CindelSchemaError(
          'Remote sync collection `$collection` cannot be written.',
        );
      case CindelRemoteDelete(:final collection, :final id):
        if (usesSqliteNativeDocuments) {
          await deleteAllNativeDocuments(collection, [id]);
        } else {
          await delete(collection, id);
        }
      case CindelRemoteReplaceLinks(
        :final collection,
        :final id,
        :final linkName,
        :final targetCollection,
        :final targetIds,
      ):
        await saveLinkIds(
          sourceCollection: collection,
          sourceId: id,
          linkName: linkName,
          targetCollection: targetCollection,
          targetIds: targetIds,
        );
    }
  }

  Future<T> _syncRunInternalWrite<T>(Future<T> Function() action) async {
    // This is deliberately scoped and restorable because sync can write state
    // while already inside a remote-apply transaction.
    final previous = _syncInternalWrite;
    _syncInternalWrite = true;
    try {
      return await action();
    } finally {
      _syncInternalWrite = previous;
    }
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
        _syncSession?._wake();
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

// Internal sidecar that owns scheduling and adapter calls for one open
// database handle. It is intentionally not exposed from CindelDatabase: app code
// opts in at open time, then continues using typed collections.
final class _CindelSyncSession {
  _CindelSyncSession(this.config);

  final CindelSyncConfig config;
  CindelDatabase? _database;
  Timer? _timer;
  bool _closed = false;
  bool _syncing = false;
  String? _clientId;
  String? _checkpoint;
  int _nextSequence = 1;
  DateTime? _lastSyncAt;

  Future<void> start(CindelDatabase database) async {
    _database = database;
    // The client id may be supplied by the app for backend identity. If it is
    // omitted, persist a generated id so mutation ids remain stable after
    // closing and reopening the same local database.
    _clientId = config.clientId ?? await database._syncReadState('clientId');
    if (_clientId == null) {
      _clientId = 'cindel-${DateTime.now().microsecondsSinceEpoch}';
      await database.writeTxn(
        () => database._syncPersistState('clientId', _clientId),
      );
    }
    _checkpoint = await database._syncReadState('checkpoint');
    final persistedNextSequence =
        int.tryParse(await database._syncReadState('nextSequence') ?? '') ?? 1;
    final outboxNextSequence = await database._syncNextOutboxSequence();
    // Use the greater value so pending outbox rows can never collide with
    // newly-created mutation ids, even if the auxiliary state row is stale.
    _nextSequence = persistedNextSequence > outboxNextSequence
        ? persistedNextSequence
        : outboxNextSequence;
    await _emit(CindelSyncPhase.idle);
    if (config.autoStart) {
      _timer = Timer.periodic(config.interval, (_) => _wake());
      _wake();
    }
  }

  Future<void> close() async {
    // Closing waits for an in-flight sync cycle so the adapter cannot keep
    // writing into a handle that is about to close.
    _closed = true;
    _timer?.cancel();
    while (_syncing) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
  }

  Future<void> recordUpsert(
    String collection,
    int id,
    CindelDocument document,
  ) {
    return _record(
      collection: collection,
      documentId: id,
      operation: CindelSyncOperation.upsert,
      document: document,
    );
  }

  Future<void> recordDelete(String collection, int id) {
    return _record(
      collection: collection,
      documentId: id,
      operation: CindelSyncOperation.delete,
    );
  }

  Future<void> recordReplaceLinks({
    required String sourceCollection,
    required int sourceId,
    required String linkName,
    required String targetCollection,
    required List<int> targetIds,
  }) {
    return _record(
      collection: sourceCollection,
      documentId: sourceId,
      operation: CindelSyncOperation.replaceLinks,
      linkName: linkName,
      targetCollection: targetCollection,
      targetIds: targetIds,
    );
  }

  Future<void> _record({
    required String collection,
    required int documentId,
    required CindelSyncOperation operation,
    CindelDocument? document,
    String? linkName,
    String? targetCollection,
    List<int> targetIds = const [],
  }) async {
    final database = _database!;
    if (!database.isInWriteTransaction) {
      throw StateError('Cindel sync mutations must be recorded in writeTxn.');
    }
    // The sequence is both the outbox row id and the suffix of mutationId.
    // Keeping those aligned makes deduplication and pending-row cleanup simple.
    final sequence = _nextSequence++;
    final clientId = _clientId!;
    final record = _CindelSyncOutboxRecord(
      dbId: sequence,
      mutationId: '$clientId:$sequence',
      clientId: clientId,
      sequence: sequence,
      collection: collection,
      documentId: documentId,
      operation: operation.name,
      documentJson: document == null ? null : jsonEncode(document),
      linkName: linkName,
      targetCollection: targetCollection,
      targetIdsJson: targetIds.isEmpty ? null : jsonEncode(targetIds),
      baseCheckpoint: _checkpoint,
      createdAtMicros: DateTime.now().toUtc().microsecondsSinceEpoch,
      attemptCount: 0,
      lastError: null,
      state: 'pending',
    );
    await database._syncPersistMutation(record);
    await database._syncPersistState('nextSequence', '$_nextSequence');
  }

  void _wake() {
    if (_closed || _syncing) {
      return;
    }
    unawaited(_syncOnce());
  }

  Future<void> _syncOnce() async {
    if (_closed || _syncing) {
      return;
    }
    final database = _database;
    if (database == null) {
      return;
    }
    _syncing = true;
    try {
      await _emit(CindelSyncPhase.syncing);
      final schemaVersions = await database._syncSchemaVersions();
      final pending = await database._syncReadOutbox(limit: config.batchSize);
      if (pending.isNotEmpty) {
        // Push drains only adapter-accepted ids. Unaccepted rows remain in the
        // durable outbox and will be retried by a later scheduler tick.
        final result = await config.adapter.push(
          CindelPushRequest(
            clientId: _clientId!,
            lastPulledCheckpoint: _checkpoint,
            schemaVersionByCollection: schemaVersions,
            mutations: [for (final record in pending) record.toMutation()],
          ),
        );
        final acceptedIds = <int>[
          for (final record in pending)
            if (result.acceptedMutationIds.contains(record.mutationId))
              record.dbId,
        ];
        await database.writeTxn(() async {
          await database._syncDeleteOutboxIds(acceptedIds);
          if (result.checkpoint != null) {
            _checkpoint = result.checkpoint;
            await database._syncPersistState('checkpoint', _checkpoint);
          }
        });
        if (result.correctedChanges.isNotEmpty) {
          // Corrections are backend truth for optimistic writes. Apply them
          // after deleting accepted outbox rows so the local view converges.
          await database._syncApplyRemoteChanges(result.correctedChanges);
        }
      }

      // Pull always runs after push so this client observes remote changes and
      // backend-side effects after its accepted mutations.
      final pull = await config.adapter.pull(
        CindelPullRequest(
          clientId: _clientId!,
          checkpoint: _checkpoint,
          schemaVersionByCollection: schemaVersions,
          collections: schemaVersions.keys.toSet(),
        ),
      );
      _checkpoint = pull.checkpoint;
      await database._syncApplyRemoteChanges(
        pull.changes,
        checkpoint: pull.checkpoint,
      );
      _lastSyncAt = DateTime.now().toUtc();
      await _emit(CindelSyncPhase.idle);
    } catch (error, stackTrace) {
      final phase = error.toString().toLowerCase().contains('offline')
          ? CindelSyncPhase.offline
          : CindelSyncPhase.error;
      await _emit(phase, error);
      config.onError?.call(error, stackTrace);
    } finally {
      _syncing = false;
    }
  }

  Future<void> _emit(CindelSyncPhase phase, [Object? error]) async {
    // Status is informational only. It reports pending count by reading the
    // internal outbox rather than trusting in-memory state.
    final database = _database;
    final pending = database == null
        ? 0
        : (await database._syncReadOutbox(limit: config.batchSize)).length;
    config.onStatusChanged?.call(
      CindelSyncStatus(
        phase: phase,
        pendingCount: pending,
        lastSyncAt: _lastSyncAt,
        lastError: error,
      ),
    );
  }
}

// Durable outgoing mutation row. The public CindelSyncMutation is derived from
// this record when the scheduler calls the adapter.
final class _CindelSyncOutboxRecord {
  const _CindelSyncOutboxRecord({
    required this.dbId,
    required this.mutationId,
    required this.clientId,
    required this.sequence,
    required this.collection,
    required this.documentId,
    required this.operation,
    required this.documentJson,
    required this.linkName,
    required this.targetCollection,
    required this.targetIdsJson,
    required this.baseCheckpoint,
    required this.createdAtMicros,
    required this.attemptCount,
    required this.lastError,
    required this.state,
  });

  final int dbId;
  final String mutationId;
  final String clientId;
  final int sequence;
  final String collection;
  final int documentId;
  final String operation;
  final String? documentJson;
  final String? linkName;
  final String? targetCollection;
  final String? targetIdsJson;
  final String? baseCheckpoint;
  final int createdAtMicros;
  final int attemptCount;
  final String? lastError;
  final String state;

  CindelSyncMutation toMutation() {
    return CindelSyncMutation(
      mutationId: mutationId,
      clientId: clientId,
      sequence: sequence,
      collection: collection,
      operation: CindelSyncOperation.values.byName(operation),
      documentId: documentId,
      document: documentJson == null
          ? null
          : Map<String, Object?>.from(jsonDecode(documentJson!) as Map),
      linkName: linkName,
      targetCollection: targetCollection,
      targetIds: targetIdsJson == null
          ? const []
          : [
              for (final id in jsonDecode(targetIdsJson!) as List<Object?>)
                id as int,
            ],
      baseCheckpoint: baseCheckpoint,
    );
  }
}

// Small key/value store for sync metadata that should survive outbox drains.
final class _CindelSyncStateRecord {
  const _CindelSyncStateRecord(this.dbId, this.key, this.value);

  final int dbId;
  final String key;
  final String? value;
}

bool _isSyncInternalCollection(String collection) {
  return collection == _syncOutboxCollection ||
      collection == _syncStateCollection;
}

int _syncStateId(String key) {
  return switch (key) {
    'clientId' => 1,
    'checkpoint' => 2,
    'nextSequence' => 3,
    _ => throw ArgumentError.value(key, 'key', 'Unknown sync state key.'),
  };
}

CindelFieldSchema _syncSchemaField({
  required String name,
  required String dartType,
  required String binaryType,
  bool isId = false,
}) {
  return CindelFieldSchema(
    name: name,
    dartType: dartType,
    binaryType: binaryType,
    isId: isId,
    isIndexed: false,
  );
}

// Internal schemas are appended to the user schema set only when sync is
// enabled. They use normal Cindel storage so migrations, transactions, and
// watcher behavior stay on the same backend primitives.
final _syncInternalSchemas = <CindelCollectionSchema<dynamic>>[
  _syncOutboxSchema,
  _syncStateSchema,
];

// Schema for durable outgoing mutations. Field order must stay aligned with
// _writeSyncOutboxRecord, _readSyncOutboxRecord, and the MDBX binary fallback
// below.
final _syncOutboxSchema = CindelCollectionSchema<_CindelSyncOutboxRecord>(
  name: _syncOutboxCollection,
  dartName: '_CindelSyncOutboxRecord',
  idField: 'dbId',
  fields: [
    _syncSchemaField(
      name: 'dbId',
      dartType: 'int',
      binaryType: 'int',
      isId: true,
    ),
    _syncSchemaField(
      name: 'baseCheckpoint',
      dartType: 'String?',
      binaryType: 'string',
    ),
    _syncSchemaField(
      name: 'clientId',
      dartType: 'String',
      binaryType: 'string',
    ),
    _syncSchemaField(
      name: 'collection',
      dartType: 'String',
      binaryType: 'string',
    ),
    _syncSchemaField(
      name: 'createdAtMicros',
      dartType: 'int',
      binaryType: 'int',
    ),
    _syncSchemaField(name: 'documentId', dartType: 'int', binaryType: 'int'),
    _syncSchemaField(
      name: 'documentJson',
      dartType: 'String?',
      binaryType: 'string',
    ),
    _syncSchemaField(
      name: 'lastError',
      dartType: 'String?',
      binaryType: 'string',
    ),
    _syncSchemaField(
      name: 'linkName',
      dartType: 'String?',
      binaryType: 'string',
    ),
    _syncSchemaField(
      name: 'mutationId',
      dartType: 'String',
      binaryType: 'string',
    ),
    _syncSchemaField(
      name: 'operation',
      dartType: 'String',
      binaryType: 'string',
    ),
    _syncSchemaField(name: 'sequence', dartType: 'int', binaryType: 'int'),
    _syncSchemaField(name: 'state', dartType: 'String', binaryType: 'string'),
    _syncSchemaField(
      name: 'targetCollection',
      dartType: 'String?',
      binaryType: 'string',
    ),
    _syncSchemaField(
      name: 'targetIdsJson',
      dartType: 'String?',
      binaryType: 'string',
    ),
    _syncSchemaField(name: 'attemptCount', dartType: 'int', binaryType: 'int'),
  ],
  toDocument: (record) => {
    'dbId': record.dbId,
    'baseCheckpoint': record.baseCheckpoint,
    'clientId': record.clientId,
    'collection': record.collection,
    'createdAtMicros': record.createdAtMicros,
    'documentId': record.documentId,
    'documentJson': record.documentJson,
    'lastError': record.lastError,
    'linkName': record.linkName,
    'mutationId': record.mutationId,
    'operation': record.operation,
    'sequence': record.sequence,
    'state': record.state,
    'targetCollection': record.targetCollection,
    'targetIdsJson': record.targetIdsJson,
    'attemptCount': record.attemptCount,
  },
  fromDocument: (document) => _CindelSyncOutboxRecord(
    dbId: document['dbId'] as int,
    baseCheckpoint: document['baseCheckpoint'] as String?,
    clientId: document['clientId'] as String,
    collection: document['collection'] as String,
    createdAtMicros: document['createdAtMicros'] as int,
    documentId: document['documentId'] as int,
    documentJson: document['documentJson'] as String?,
    lastError: document['lastError'] as String?,
    linkName: document['linkName'] as String?,
    mutationId: document['mutationId'] as String,
    operation: document['operation'] as String,
    sequence: document['sequence'] as int,
    state: document['state'] as String,
    targetCollection: document['targetCollection'] as String?,
    targetIdsJson: document['targetIdsJson'] as String?,
    attemptCount: document['attemptCount'] as int,
  ),
  getId: (record) => record.dbId,
  setId: null,
  writeNativeDocument: _writeSyncOutboxRecord,
  readNativeDocument: _readSyncOutboxRecord,
);

// Schema for compact sync key/value metadata.
final _syncStateSchema = CindelCollectionSchema<_CindelSyncStateRecord>(
  name: _syncStateCollection,
  dartName: '_CindelSyncStateRecord',
  idField: 'dbId',
  fields: [
    _syncSchemaField(
      name: 'dbId',
      dartType: 'int',
      binaryType: 'int',
      isId: true,
    ),
    _syncSchemaField(name: 'key', dartType: 'String', binaryType: 'string'),
    _syncSchemaField(name: 'value', dartType: 'String?', binaryType: 'string'),
  ],
  toDocument: (record) => {
    'dbId': record.dbId,
    'key': record.key,
    'value': record.value,
  },
  fromDocument: (document) => _CindelSyncStateRecord(
    document['dbId'] as int,
    document['key'] as String,
    document['value'] as String?,
  ),
  getId: (record) => record.dbId,
  setId: null,
  writeNativeDocument: _writeSyncStateRecord,
  readNativeDocument: _readSyncStateRecord,
);

void _writeSyncOutboxRecord(
  CindelNativeDocumentWriter writer,
  _CindelSyncOutboxRecord record,
) {
  writer.writeInt(0, record.attemptCount);
  _writeNullableString(writer, 1, record.baseCheckpoint);
  writer.writeString(2, record.clientId);
  writer.writeString(3, record.collection);
  writer.writeInt(4, record.createdAtMicros);
  writer.writeInt(5, record.documentId);
  _writeNullableString(writer, 6, record.documentJson);
  _writeNullableString(writer, 7, record.lastError);
  _writeNullableString(writer, 8, record.linkName);
  writer.writeString(9, record.mutationId);
  writer.writeString(10, record.operation);
  writer.writeInt(11, record.sequence);
  writer.writeString(12, record.state);
  _writeNullableString(writer, 13, record.targetCollection);
  _writeNullableString(writer, 14, record.targetIdsJson);
}

_CindelSyncOutboxRecord _readSyncOutboxRecord(
  CindelNativeDocumentReader reader,
  int index,
) {
  return _CindelSyncOutboxRecord(
    dbId: reader.readId(index),
    attemptCount: reader.readInt(index, 0)!,
    baseCheckpoint: reader.readString(index, 1),
    clientId: reader.readString(index, 2)!,
    collection: reader.readString(index, 3)!,
    createdAtMicros: reader.readInt(index, 4)!,
    documentId: reader.readInt(index, 5)!,
    documentJson: reader.readString(index, 6),
    lastError: reader.readString(index, 7),
    linkName: reader.readString(index, 8),
    mutationId: reader.readString(index, 9)!,
    operation: reader.readString(index, 10)!,
    sequence: reader.readInt(index, 11)!,
    state: reader.readString(index, 12)!,
    targetCollection: reader.readString(index, 13),
    targetIdsJson: reader.readString(index, 14),
  );
}

void _writeSyncStateRecord(
  CindelNativeDocumentWriter writer,
  _CindelSyncStateRecord record,
) {
  writer.writeString(0, record.key);
  _writeNullableString(writer, 1, record.value);
}

_CindelSyncStateRecord _readSyncStateRecord(
  CindelNativeDocumentReader reader,
  int index,
) {
  return _CindelSyncStateRecord(
    reader.readId(index),
    reader.readString(index, 0)!,
    reader.readString(index, 1),
  );
}

void _writeNullableString(
  CindelNativeDocumentWriter writer,
  int fieldIndex,
  String? value,
) {
  if (value == null) {
    writer.writeNull(fieldIndex);
  } else {
    writer.writeString(fieldIndex, value);
  }
}

// MDBX internal sync rows are encoded as schema binary documents. Keep this
// order exactly in sync with _encodeSyncOutboxRecord and
// _decodeSyncOutboxRecord.
final _syncOutboxBinaryTypes = <CindelBinaryFieldType>[
  CindelBinaryFieldType.stringValue,
  CindelBinaryFieldType.stringValue,
  CindelBinaryFieldType.stringValue,
  CindelBinaryFieldType.intValue,
  CindelBinaryFieldType.intValue,
  CindelBinaryFieldType.stringValue,
  CindelBinaryFieldType.stringValue,
  CindelBinaryFieldType.stringValue,
  CindelBinaryFieldType.stringValue,
  CindelBinaryFieldType.stringValue,
  CindelBinaryFieldType.intValue,
  CindelBinaryFieldType.stringValue,
  CindelBinaryFieldType.stringValue,
  CindelBinaryFieldType.stringValue,
  CindelBinaryFieldType.intValue,
];

Uint8List _encodeSyncOutboxRecord(_CindelSyncOutboxRecord record) {
  return cindelEncodeSchemaBinaryDocument([
    record.baseCheckpoint,
    record.clientId,
    record.collection,
    record.createdAtMicros,
    record.documentId,
    record.documentJson,
    record.lastError,
    record.linkName,
    record.mutationId,
    record.operation,
    record.sequence,
    record.state,
    record.targetCollection,
    record.targetIdsJson,
    record.attemptCount,
  ], _syncOutboxBinaryTypes);
}

_CindelSyncOutboxRecord _decodeSyncOutboxRecord(int id, Uint8List bytes) {
  final values = cindelDecodeSchemaBinaryDocument(
    bytes,
    _syncOutboxBinaryTypes,
  );
  return _CindelSyncOutboxRecord(
    dbId: id,
    baseCheckpoint: values[0] as String?,
    clientId: values[1] as String,
    collection: values[2] as String,
    createdAtMicros: values[3] as int,
    documentId: values[4] as int,
    documentJson: values[5] as String?,
    lastError: values[6] as String?,
    linkName: values[7] as String?,
    mutationId: values[8] as String,
    operation: values[9] as String,
    sequence: values[10] as int,
    state: values[11] as String,
    targetCollection: values[12] as String?,
    targetIdsJson: values[13] as String?,
    attemptCount: values[14] as int,
  );
}

// Binary shape for MDBX sync state rows.
final _syncStateBinaryTypes = <CindelBinaryFieldType>[
  CindelBinaryFieldType.stringValue,
  CindelBinaryFieldType.stringValue,
];

Uint8List _encodeSyncStateRecord(_CindelSyncStateRecord record) {
  return cindelEncodeSchemaBinaryDocument([
    record.key,
    record.value,
  ], _syncStateBinaryTypes);
}

_CindelSyncStateRecord _decodeSyncStateRecord(Uint8List bytes) {
  final values = cindelDecodeSchemaBinaryDocument(bytes, _syncStateBinaryTypes);
  return _CindelSyncStateRecord(
    autoIncrement,
    values[0] as String,
    values[1] as String?,
  );
}
