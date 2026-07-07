import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:cindel_annotations/cindel_annotations.dart';

import '../cindel_error.dart';
import '../migration.dart';
import '../schema.dart';
import '../sync.dart';
import 'native_document_reader.dart';
import 'schema_manifest.dart';
import 'wire.dart';
import 'worker_bridge.dart';

/// Internal map-shaped document representation used by Cindel runtime bridges.
typedef CindelDocument = Map<String, Object?>;

// Reserved internal collections used only by the sync sidecar. They are
// registered with the Web schema manifest when sync is enabled and remain
// hidden from application collection APIs.
const _syncOutboxCollection = '__cindel_sync_outbox';
const _syncStateCollection = '__cindel_sync_state';

/// A collection change observed by Web Cindel watchers.
///
/// Change sets are produced after committed writes in the current Web database
/// handle or by Worker collection-revision polling while a watcher is active.
final class CindelChangeSet {
  const CindelChangeSet._({
    required this.collection,
    required this.documentIds,
    required this.documents,
    required this.hasUnknownDocuments,
    required this.isExternal,
    required this.revision,
  });

  /// Creates a change when the exact affected ids are unknown.
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

  /// Creates a change for one inserted or updated document.
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

  /// Creates a change for several inserted or updated documents.
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

  /// Creates a change for one deleted document.
  factory CindelChangeSet.delete(String collection, int id) {
    return CindelChangeSet.deletes(collection, [id]);
  }

  /// Creates a change for several deleted documents.
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

  /// Creates a change set returned by the Worker post-commit change path.
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

  /// Collection that changed.
  final String collection;

  /// Changed document ids, or `null` when the exact ids are unknown.
  final Set<int>? documentIds;

  /// Documents written by this handle, keyed by id when available.
  final Map<int, CindelDocument> documents;

  /// Whether this change includes writes whose document value is not available.
  final bool hasUnknownDocuments;

  /// Whether this change came from revision polling instead of local metadata.
  final bool isExternal;

  /// Native collection revision after the commit.
  final int? revision;

  /// Returns whether this change can affect document [id].
  bool mayAffectDocument(int id) {
    final ids = documentIds;
    return ids == null || ids.contains(id);
  }
}

// Keep ids inside JavaScript's precise integer range. Native backends can use
// wider 64-bit ids, but Web messages and dart2js numbers cannot safely round
// trip every signed 64-bit value.
const _maximumSqliteId = 0x1FFFFFFFFFFFFF;

// Flutter serves package assets below `assets/packages/...` in release builds.
// Cindel Web must consume the companion runtime from cindel_flutter_libs, not
// from an app-local copy.
const _defaultWorkerUrl =
    'assets/packages/cindel_flutter_libs/web/cindel_worker.js';

/// Native storage backend used by a Cindel database.
enum CindelStorageBackend {
  /// SQLite is the only browser storage target.
  sqlite,

  /// MDBX remains the default outside Web; Web transparently uses SQLite.
  mdbx,
}

/// The storage backend used when callers do not pass an explicit backend.
const defaultCindelStorageBackend = CindelStorageBackend.mdbx;

/// Default polling interval used by Cindel watchers.
const defaultCindelWatchPollInterval = Duration(milliseconds: 50);

enum _TransactionMode { read, write }

/// Web implementation of the public Cindel database handle.
///
/// The handle exposes the same high-level API shape as the native database, but
/// every storage operation is serialized through a browser Worker that owns the
/// SQLite/Wasm engine. MDBX remains a native backend only.
class CindelDatabase {
  CindelDatabase._({
    required this.directory,
    required Map<String, CindelCollectionSchema<dynamic>> schemas,
    required CindelWebWorkerBridge bridge,
    required CindelSyncConfig? syncConfig,
  }) : backend = CindelStorageBackend.sqlite,
       _schemas = Map.of(schemas),
       _bridge = bridge,
       _syncSession = syncConfig == null
           ? null
           : _CindelWebSyncSession(syncConfig);

  /// Browser database name used by the Web SQLite runtime.
  final String directory;

  /// Web always runs against SQLite through Worker/Wasm.
  final CindelStorageBackend backend;

  final Map<String, CindelCollectionSchema<dynamic>> _schemas;
  final CindelWebWorkerBridge _bridge;
  final _CindelWebSyncSession? _syncSession;
  final Map<String, Set<_RegisteredWatcher>> _watchersByCollection = {};
  final Map<String, _CindelChangeSetBuilder> _changesInTransaction = {};
  bool _closed = false;
  _TransactionMode? _activeTransaction;

  // Sync persists outbox/state through normal Worker storage operations. These
  // flags distinguish internal writes and remote apply from user mutations so
  // those writes do not recursively enqueue more sync work.
  bool _syncInternalWrite = false;
  bool _syncRemoteApply = false;

  /// Whether SQLite can use generated native document readers for this handle.
  bool get usesSqliteNativeDocuments => true;

  /// Opens a Web SQLite database.
  ///
  /// The schema manifest is sent during open so the Wasm engine can validate
  /// persisted schema metadata before any typed reads or writes run.
  /// When [migrationPlan] is provided, Cindel runs controlled migration
  /// callbacks before opening the final handle with [schemas].
  static Future<CindelDatabase> open({
    required String directory,
    Iterable<CindelCollectionSchema<dynamic>> schemas = const [],
    CindelStorageBackend backend = defaultCindelStorageBackend,
    CindelMigrationPlan? migrationPlan,
    CindelSyncConfig? sync,
  }) async {
    _checkDirectory(directory);
    if (migrationPlan != null) {
      await migrationPlan.run(
        directory: directory,
        targetSchemas: schemas,
        backend: backend,
      );
    }
    final schemasByCollection = _schemasByCollection(
      sync == null ? schemas : [...schemas, ..._syncWebInternalSchemas],
    );
    final bridge = CindelWebWorkerBridge(_defaultWorkerUrl);
    try {
      await bridge.init();
      final manifest = cindelEncodeWebSchemaManifest(
        schemasByCollection.values,
      );
      await bridge.send(
        operation: 'open',
        payload: _payload({'dbName': directory, 'manifest': manifest}),
      );
      final database = CindelDatabase._(
        directory: directory,
        schemas: schemasByCollection,
        bridge: bridge,
        syncConfig: sync,
      );
      await database._syncSession?.start(database);
      return database;
    } catch (_) {
      unawaited(bridge.close());
      throw CindelOpenError(backend: CindelStorageBackend.sqlite.name);
    }
  }

  /// Opens a short-lived Web SQLite database name.
  ///
  /// Browser storage does not expose the same native in-memory mode as MDBX or
  /// desktop SQLite, so this creates a unique persisted Web database name for
  /// tests and temporary work.
  static Future<CindelDatabase> openInMemory({
    Iterable<CindelCollectionSchema<dynamic>> schemas = const [],
    CindelStorageBackend backend = defaultCindelStorageBackend,
    CindelSyncConfig? sync,
  }) {
    return open(
      directory: 'cindel-memory-${DateTime.now().microsecondsSinceEpoch}',
      schemas: schemas,
      backend: backend,
      sync: sync,
    );
  }

  /// Opens a Web database handle suitable for controlled migration callbacks.
  ///
  /// This mirrors the native migration handle and lets migration callbacks read
  /// old data before registering the final target schemas.
  static Future<CindelDatabase> openForMigration({
    required String directory,
    Iterable<CindelCollectionSchema<dynamic>> schemas = const [],
    CindelStorageBackend backend = defaultCindelStorageBackend,
    CindelSyncConfig? sync,
  }) {
    return open(
      directory: directory,
      schemas: schemas,
      backend: backend,
      sync: sync,
    );
  }

  /// Closes this database.
  ///
  /// Calling [close] more than once is safe. Active Web watchers are closed
  /// before the Worker bridge is terminated.
  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    await _syncSession?.close();
    await _closeWatchers();
    await _bridge.close();
  }

  /// Runs [action] inside a Web SQLite read transaction.
  ///
  /// Read transactions provide a consistent snapshot for reads performed by
  /// this database handle. Write operations inside [readTxn] throw
  /// [CindelTransactionError].
  Future<T> readTxn<T>(Future<T> Function() action) {
    return _runTransaction(_TransactionMode.read, action);
  }

  /// Runs [action] inside a Web SQLite write transaction.
  ///
  /// All writes performed by this database handle are committed together. If
  /// [action] throws, Worker changes are rolled back and watchers are not
  /// notified.
  Future<T> writeTxn<T>(Future<T> Function() action) {
    return _runTransaction(_TransactionMode.write, action);
  }

  /// Whether this handle is currently inside a write transaction.
  bool get isInWriteTransaction => _activeTransaction == _TransactionMode.write;

  /// Allocates the next Web SQLite auto-increment id for [collection].
  Future<int> allocateId(String collection) async {
    final ids = await _sendIds('allocateId', {'collection': collection});
    return ids.single;
  }

  /// Stores generated typed objects through the Web SQLite native row path.
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
    _checkOpen();
    _checkCollection(collection);
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
    final bytes = encodeNativeDocumentWriteBatchDirect<T>(
      ids: ids,
      objects: objects,
      fieldCount: fieldTypes.length,
      writeDocument: (writer, object) => writeDocument(writer, object),
    );
    await _sendVoid('putNativeAll', {
      'collection': collection,
      'documents': bytes,
    });
    await _syncRecordNativeUpserts(collection, ids, objects, documents);
    await _markNativeCollectionChanged(
      collection,
      () => CindelChangeSet.upserts(collection, documents?.call(), ids: ids),
    );
  }

  /// Stores generated typed objects while reading ids from each object.
  Future<void> putAllNativeBinaryObjects<T>(
    String collection,
    List<T> objects,
    Uint8List fieldTypes,
    CindelGetId<T> getId,
    CindelWriteNativeDocument<T> writeDocument,
  ) {
    return putAllNativeBinaryDocuments(
      collection,
      [for (final object in objects) getId(object)],
      objects,
      fieldTypes,
      writeDocument,
    );
  }

  /// Reads generated typed objects through the Web SQLite native row reader.
  Future<List<T?>> getAllNativeBinaryDocuments<T>(
    String collection,
    Iterable<int> ids,
    Uint8List fieldTypes,
    CindelReadNativeDocument<T> readDocument,
  ) async {
    _checkOpen();
    _checkCollection(collection);
    final idList = ids.toList(growable: false);
    for (final id in idList) {
      _checkId(id);
    }
    if (idList.isEmpty) {
      return <T?>[];
    }
    final response = await _sendBytes('getAllStored', {
      'collection': collection,
      'ids': encodeIdList(idList),
    });
    final reader = CindelWebNativeDocumentReader(
      ids: idList,
      documents: decodeOptionalDocumentBatch(response),
      fieldTypes: fieldTypes,
    );
    try {
      return <T?>[
        for (var i = 0; i < reader.length; i += 1)
          if (reader.isPresent(i)) readDocument(reader, i) else null,
      ];
    } finally {
      reader.release();
    }
  }

  /// Returns generated typed objects matched by [plan].
  Future<List<T>> queryNativePlanObjects<T>(
    String collection,
    WireQueryPlan plan,
    Uint8List fieldTypes,
    CindelReadNativeDocument<T> readDocument,
  ) async {
    final ids = await queryNativePlanIds(collection, plan);
    final objects = await getAllNativeBinaryDocuments(
      collection,
      ids,
      fieldTypes,
      readDocument,
    );
    return [
      for (final object in objects)
        if (object != null) object,
    ];
  }

  /// Returns ids for every document in [collection].
  Future<List<int>> documentIds(String collection) {
    return _sendIds('documentIds', {'collection': collection});
  }

  /// Returns up to [limit] ids in [collection] after [afterId], ordered ascending.
  Future<List<int>> documentIdsPage(
    String collection, {
    int? afterId,
    int limit = 1000,
  }) {
    _checkCollection(collection);
    if (afterId != null) {
      _checkId(afterId);
    }
    _checkPageLimit(limit);
    return _sendIds('documentIdsPage', {
      'collection': collection,
      'afterId': afterId,
      'limit': limit,
    });
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
    _checkOpen();
    _checkCanWrite();
    _checkCollection(sourceCollection);
    _checkCollection(targetCollection);
    _checkId(sourceId);
    final ids = targetIds.toSet().toList(growable: false)..sort();
    for (final id in ids) {
      _checkId(id);
    }
    await _sendVoid('replaceLinks', {
      'sourceCollection': sourceCollection,
      'sourceId': sourceId,
      'linkName': linkName,
      'targetCollection': targetCollection,
      'targetIds': encodeIdList(ids),
    });
    await _syncRecordReplaceLinks(
      sourceCollection: sourceCollection,
      sourceId: sourceId,
      linkName: linkName,
      targetCollection: targetCollection,
      targetIds: ids,
    );
    await _markNativeCollectionChanged(
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
    _checkOpen();
    _checkCollection(sourceCollection);
    _checkCollection(targetCollection);
    _checkId(sourceId);
    final ids = await _sendIds('forwardLinkIds', {
      'sourceCollection': sourceCollection,
      'sourceId': sourceId,
      'linkName': linkName,
      'targetCollection': targetCollection,
    });
    return _loadTypedObjectsByIds<T>(targetCollection, ids);
  }

  /// Loads objects reached by a backlink.
  Future<List<T>> loadBacklinkObjects<T>({
    required String ownerCollection,
    required int ownerId,
    required String sourceCollection,
    required String sourceLinkName,
  }) async {
    _checkOpen();
    _checkCollection(ownerCollection);
    _checkCollection(sourceCollection);
    _checkId(ownerId);
    final ids = await _sendIds('backlinkSourceIds', {
      'targetCollection': ownerCollection,
      'targetId': ownerId,
      'sourceCollection': sourceCollection,
      'linkName': sourceLinkName,
    });
    return _loadTypedObjectsByIds<T>(sourceCollection, ids);
  }

  Future<List<T>> _loadTypedObjectsByIds<T>(
    String collection,
    List<int> ids,
  ) async {
    final schema = _schemas[collection];
    final nativeReader = schema?.readNativeDocument;
    final fieldTypes = schema == null ? null : _nativeFieldTypes(schema);
    if (schema == null || nativeReader == null || fieldTypes == null) {
      throw CindelSchemaError(
        'Collection `$collection` has no generated native reader.',
      );
    }
    final objects = await getAllNativeBinaryDocuments<dynamic>(
      collection,
      ids,
      fieldTypes,
      nativeReader,
    );
    return [
      for (final object in objects)
        if (object != null) _bindLoadedObject<T>(schema, object),
    ];
  }

  T _bindLoadedObject<T>(
    CindelCollectionSchema<dynamic> schema,
    Object object,
  ) {
    final dynamicSchema = schema as dynamic;
    dynamicSchema.bindLinks?.call(this, schema, object);
    return object as T;
  }

  /// Returns ids whose indexed [field] equals [value].
  Future<List<int>> queryEqualIds(
    String collection,
    String field,
    Object value,
  ) async {
    final schemaField = _indexedFieldSchema(collection, field);
    if (schemaField.indexType == CindelIndexType.hash) {
      throw CindelQueryError(
        'Hash index `${schemaField.name}` requires document verification.',
      );
    }
    final ids = await _queryNativeIndexEqualIds(
      collection,
      field,
      value,
      schemaField,
    );
    return schemaField.indexType == CindelIndexType.words
        ? _dedupeIds(ids)
        : ids;
  }

  /// Returns ids whose composite [indexName] equals [values].
  Future<List<int>> queryCompositeEqualIds(
    String collection,
    String indexName,
    List<Object> values,
  ) async {
    final value = _compositeIndexValue(collection, indexName, values);
    return queryNativePlanIds(
      collection,
      WireQueryPlan(
        source: WireQuerySource.indexEqual(
          indexName: indexName,
          value: value,
          dedupe: false,
        ),
        filter: null,
        sorts: const [],
        distinctFields: const [],
        offset: 0,
        limit: null,
      ),
    );
  }

  CindelFieldSchema _indexedFieldSchema(String collection, String field) {
    final schema = _schemaForLookup(collection);
    final schemaField = _requireSchemaField(schema, field);
    if (!schemaField.isIndexed) {
      throw CindelQueryError(
        'Field `$field` is not indexed for `$collection`.',
      );
    }
    return schemaField;
  }

  CindelCollectionSchema<dynamic> _schemaForLookup(String collection) {
    final schema = _schemas[collection];
    if (schema == null) {
      throw CindelSchemaError(
        'Collection `$collection` has no registered Cindel schema.',
      );
    }
    return schema;
  }

  WireIndexValue _compositeIndexValue(
    String collection,
    String indexName,
    List<Object> values,
  ) {
    final schema = _schemaForLookup(collection);
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
        webIndexValueForField(
          values[index],
          _fieldWithCaseSensitivity(
            _requireSchemaField(schema, composite.fields[index]),
            composite.caseSensitive,
          ),
        ),
    ]);
  }

  Future<List<int>> _queryNativeIndexEqualIds(
    String collection,
    String field,
    Object value,
    CindelFieldSchema schemaField,
  ) {
    if (!_canUseSqliteNativeIndexSource(collection, schemaField)) {
      return Future<List<int>>.value(const []);
    }
    return queryNativePlanIds(
      collection,
      WireQueryPlan(
        source: WireQuerySource.indexEqual(
          indexName: field,
          value: webIndexValueForField(value, schemaField),
          dedupe: schemaField.indexType == CindelIndexType.words,
        ),
        filter: null,
        sorts: const [],
        distinctFields: const [],
        offset: 0,
        limit: null,
      ),
    );
  }

  bool _canUseSqliteNativeIndexSource(
    String collection,
    CindelFieldSchema field,
  ) {
    final schema = _schemas[collection];
    final dynamic dynamicSchema = schema;
    if (schema == null ||
        dynamicSchema.writeNativeDocument == null ||
        dynamicSchema.readNativeDocument == null ||
        _nativeFieldTypes(schema) == null) {
      return false;
    }
    if (!field.indexCaseSensitive && field.binaryType == 'string') {
      return false;
    }
    return field.indexType != CindelIndexType.words &&
        field.indexType != CindelIndexType.multiEntry;
  }

  List<int> _dedupeIds(List<int> ids) {
    final seen = <int>{};
    return [
      for (final id in ids)
        if (seen.add(id)) id,
    ];
  }

  /// Deletes every object stored under [ids] atomically.
  ///
  /// Web stores generated typed objects as SQLite-native rows, so this public
  /// cross-platform API delegates to the Web native-row delete path.
  Future<void> deleteAll(String collection, Iterable<int> ids) {
    return _deleteSqliteNativeRows(collection, ids);
  }

  /// Deletes generated native rows from [collection].
  Future<void> _deleteSqliteNativeRows(
    String collection,
    Iterable<int> ids,
  ) async {
    if (_syncShouldWrapLocalWrite(collection)) {
      return writeTxn(() => _deleteSqliteNativeRows(collection, ids));
    }
    _checkOpen();
    _checkCollection(collection);
    final idList = ids.toList(growable: false);
    for (final id in idList) {
      _checkId(id);
    }
    if (idList.isEmpty) {
      return;
    }
    await _sendVoid('deleteNativeAll', {
      'collection': collection,
      'ids': encodeIdList(idList),
    });
    for (final id in idList) {
      await _syncRecordDelete(collection, id);
    }
    await _markNativeCollectionChanged(
      collection,
      () => CindelChangeSet.deletes(collection, idList),
    );
  }

  /// Executes a native query plan and returns matching ids.
  Future<List<int>> queryNativePlanIds(String collection, WireQueryPlan plan) {
    return _sendIds('queryPlanIds', {
      'collection': collection,
      'plan': encodeQueryPlan(plan),
    });
  }

  /// Counts a native query plan.
  Future<int> queryNativePlanCount(
    String collection,
    WireQueryPlan plan,
  ) async {
    final scalar = decodeScalar(
      await _sendBytes('queryPlanCount', {
        'collection': collection,
        'plan': encodeQueryPlan(plan),
      }),
    );
    return scalar is WireScalarInt ? scalar.value : 0;
  }

  /// Projects a native query plan field.
  Future<List<Object?>> queryNativePlanProjection(
    String collection,
    WireQueryPlan plan,
    String field,
  ) async {
    final rows = decodeProjectionRows(
      await _sendBytes('queryPlanProject', {
        'collection': collection,
        'plan': encodeQueryPlan(plan),
        'field': field,
      }),
    );
    return rows.cells.map(_wireValueToObject).toList(growable: false);
  }

  /// Aggregates a native query plan field.
  Future<Object?> queryNativePlanAggregate(
    String collection,
    WireQueryPlan plan,
    String field,
    String operation,
  ) async {
    return _wireScalarToObject(
      decodeScalar(
        await _sendBytes('queryPlanAggregate', {
          'collection': collection,
          'plan': encodeQueryPlan(plan),
          'field': field,
          'operation': operation,
        }),
      ),
    );
  }

  /// Deletes every row matching [plan].
  Future<List<int>> deleteNativePlan(
    String collection,
    WireQueryPlan plan,
  ) async {
    if (_syncShouldWrapLocalWrite(collection)) {
      return writeTxn(() => deleteNativePlan(collection, plan));
    }
    final ids = await _sendIds('queryPlanDelete', {
      'collection': collection,
      'plan': encodeQueryPlan(plan),
    });
    if (ids.isNotEmpty) {
      for (final id in ids) {
        await _syncRecordDelete(collection, id);
      }
      await _markNativeCollectionChanged(
        collection,
        () => CindelChangeSet.deletes(collection, ids),
      );
    }
    return ids;
  }

  /// Query updates are routed through the Worker/Wasm native planner.
  Future<int> updateNativePlan(
    String collection,
    WireQueryPlan plan,
    Map<String, WireValue> updates,
  ) async {
    _syncCheckQueryUpdate(collection);
    final scalar = decodeScalar(
      await _sendBytes('queryPlanUpdate', {
        'collection': collection,
        'plan': encodeQueryPlan(plan),
        'updates': encodeFieldUpdates(updates),
        'collectChanges': true,
      }),
    );
    final count = scalar is WireScalarInt ? scalar.value : 0;
    if (count > 0) {
      await _markNativeCollectionChanged(
        collection,
        () => CindelChangeSet.external(collection),
      );
    }
    return count;
  }

  bool _syncShouldWrapLocalWrite(String collection) {
    // Web writes outside explicit writeTxn are wrapped so the app write and
    // the outbox row cross the Worker boundary as one transaction.
    return _syncSession != null &&
        !_syncInternalWrite &&
        !_syncRemoteApply &&
        !_isWebSyncInternalCollection(collection) &&
        _activeTransaction == null;
  }

  void _syncCheckQueryUpdate(String collection) {
    // Query updates do not currently yield complete per-document snapshots for
    // sync. Keep them explicitly unsupported until the mutation shape is clear.
    if (_syncSession == null ||
        _syncInternalWrite ||
        _syncRemoteApply ||
        _isWebSyncInternalCollection(collection)) {
      return;
    }
    throw UnsupportedError(
      'Cindel sync does not support query update operations yet. Rewrite '
      'matching objects and call putAll, or open the database without sync.',
    );
  }

  Future<void> _syncRecordNativeUpserts<T>(
    String collection,
    List<int> ids,
    List<T> objects,
    Map<int, CindelDocument>? Function()? documents,
  ) async {
    // Web typed writes always use native schema rows. Build the canonical
    // document snapshot here so the adapter contract stays backend-neutral.
    final session = _syncSession;
    if (session == null ||
        _syncInternalWrite ||
        _syncRemoteApply ||
        _isWebSyncInternalCollection(collection)) {
      return;
    }
    final provided = documents?.call();
    final schema = _schemas[collection];
    if (schema == null) {
      throw CindelSchemaError('Collection `$collection` has no schema.');
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
        _isWebSyncInternalCollection(collection)) {
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
        _isWebSyncInternalCollection(sourceCollection)) {
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

  Future<void> _syncPersistMutation(_CindelWebSyncOutboxRecord record) async {
    // The Web outbox is stored as generated native rows because all app data is
    // already routed through the SQLite/Wasm Worker row path.
    await _syncRunInternalWrite(() async {
      final fieldTypes = _nativeFieldTypes(_syncWebOutboxSchema)!;
      await putAllNativeBinaryDocuments<_CindelWebSyncOutboxRecord>(
        _syncOutboxCollection,
        [record.dbId],
        [record],
        fieldTypes,
        _writeWebSyncOutboxRecord,
      );
    });
  }

  Future<void> _syncPersistState(String key, String? value) async {
    // State lives separately from the outbox so draining accepted mutations
    // cannot remove the persisted client id, checkpoint, or sequence counter.
    await _syncRunInternalWrite(() async {
      final record = _CindelWebSyncStateRecord(
        _webSyncStateId(key),
        key,
        value,
      );
      final fieldTypes = _nativeFieldTypes(_syncWebStateSchema)!;
      await putAllNativeBinaryDocuments<_CindelWebSyncStateRecord>(
        _syncStateCollection,
        [record.dbId],
        [record],
        fieldTypes,
        _writeWebSyncStateRecord,
      );
    });
  }

  Future<String?> _syncReadState(String key) async {
    final fieldTypes = _nativeFieldTypes(_syncWebStateSchema)!;
    final record =
        (await getAllNativeBinaryDocuments<_CindelWebSyncStateRecord>(
          _syncStateCollection,
          [_webSyncStateId(key)],
          fieldTypes,
          _readWebSyncStateRecord,
        )).single;
    return record?.value;
  }

  Future<List<_CindelWebSyncOutboxRecord>> _syncReadOutbox({
    required int limit,
  }) async {
    // Use document id paging to keep scheduler batching identical to native
    // backends and avoid loading the whole internal outbox.
    final ids = await documentIdsPage(_syncOutboxCollection, limit: limit);
    if (ids.isEmpty) {
      return const [];
    }
    final fieldTypes = _nativeFieldTypes(_syncWebOutboxSchema)!;
    final records =
        await getAllNativeBinaryDocuments<_CindelWebSyncOutboxRecord>(
          _syncOutboxCollection,
          ids,
          fieldTypes,
          _readWebSyncOutboxRecord,
        );
    return [
      for (final record in records)
        if (record != null) record,
    ]..sort((left, right) => left.sequence.compareTo(right.sequence));
  }

  Future<int> _syncNextOutboxSequence() async {
    // On reopen, never reuse a mutation id while pending rows exist. This scan
    // complements the persisted nextSequence state and protects adapter
    // idempotency.
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
    // Only mutations accepted by the adapter are deleted. Everything else stays
    // pending so the scheduler can retry.
    final idList = ids.toList(growable: false);
    if (idList.isEmpty) {
      return;
    }
    await _syncRunInternalWrite(
      () => _deleteSqliteNativeRows(_syncOutboxCollection, idList),
    );
  }

  Future<Map<String, int>> _syncSchemaVersions() async {
    // Adapters receive only user collections. Internal Web sync collections are
    // storage details and must not appear in pull collection filters.
    final versions = <String, int>{};
    for (final collection in _schemas.keys) {
      if (_isWebSyncInternalCollection(collection)) {
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
    // Remote apply goes through normal writeTxn so Web watchers observe the
    // change, but the remote guard prevents the apply from producing another
    // outgoing mutation.
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
        if (nativeWriter == null || fieldTypes == null) {
          throw CindelSchemaError(
            'Remote sync collection `$collection` cannot be written.',
          );
        }
        // Web remote upserts must use the generated native writer because the
        // Worker stores typed app data as SQLite rows, not MDBX-style blobs.
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
      case CindelRemoteDelete(:final collection, :final id):
        await _deleteSqliteNativeRows(collection, [id]);
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
    // Keep the guard scoped because sync state writes can happen inside an
    // outer remote-apply transaction.
    final previous = _syncInternalWrite;
    _syncInternalWrite = true;
    try {
      return await action();
    } finally {
      _syncInternalWrite = previous;
    }
  }

  /// Returns the persisted schema version for [collection], or `null`.
  Future<int?> schemaVersion(String collection) async {
    final response = await _bridge.send(
      operation: 'schemaVersion',
      payload: _payload({'collection': collection}),
    );
    return response.payload as int?;
  }

  /// Returns the persisted database data migration version, or `null`.
  ///
  /// This version is independent from per-collection schema versions and is
  /// advanced only by a successful [CindelMigrationPlan].
  Future<int?> migrationVersion() async {
    final response = await _bridge.send(operation: 'migrationVersion');
    return response.payload as int?;
  }

  /// Persists the database data migration [version].
  ///
  /// Migration plans call this only after verification and target schema
  /// registration complete.
  Future<void> setMigrationVersion(int version) async {
    _checkOpen();
    if (version < 0) {
      throw ArgumentError.value(version, 'version', 'Must not be negative.');
    }
    await _bridge.send(
      operation: 'setMigrationVersion',
      payload: _payload({'version': version}),
    );
  }

  /// Registers [schemas] after caller-controlled data migration.
  ///
  /// Unlike normal open-time schema registration, this accepts incompatible
  /// target schema changes after migration callbacks have rewritten data.
  Future<void> registerMigratedSchemas(
    Iterable<CindelCollectionSchema<dynamic>> schemas,
  ) async {
    _checkOpen();
    final schemasByCollection = _schemasByCollection(
      _syncSession == null ? schemas : [...schemas, ..._syncWebInternalSchemas],
    );
    await _bridge.send(
      operation: 'registerMigratedSchemas',
      payload: _payload({
        'manifest': cindelEncodeWebSchemaManifest(schemasByCollection.values),
      }),
    );
    _schemas
      ..clear()
      ..addAll(schemasByCollection);
  }

  /// Requests backend-level compaction for this Web SQLite database.
  ///
  /// This is intended for migration cleanup after rewritten data has been
  /// verified and the target migration version has been persisted.
  Future<void> compact() async {
    _checkOpen();
    await _bridge.send(operation: 'compact');
  }

  /// Watches raw collection change metadata for this Web database handle.
  ///
  /// This is the shared single-tab change stream used by typed object,
  /// collection, query, and lazy watchers. It does not coordinate changes
  /// across multiple browser tabs.
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
    _checkOpen();
    if (_activeTransaction != null) {
      throw CindelTransactionError('Nested transactions are not supported.');
    }
    final previousChanges = Map<String, _CindelChangeSetBuilder>.of(
      _changesInTransaction,
    );
    _changesInTransaction.clear();
    final begin = mode == _TransactionMode.read
        ? 'beginReadTransaction'
        : 'beginWriteTransaction';
    await _sendVoid(begin, const {});
    _activeTransaction = mode;
    try {
      final result = await action();
      await _sendVoid('commitTransaction', const {});
      final localChanges = {
        for (final entry in _changesInTransaction.entries)
          entry.key: entry.value.build(),
      };
      final changes = mode == _TransactionMode.write
          ? await _nativeChangesForWatchers(localChanges)
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
        await _sendVoid('rollbackTransaction', const {});
      } catch (_) {
        // Preserve the original failure from user code or commit.
      }
      _changesInTransaction
        ..clear()
        ..addAll(previousChanges);
      rethrow;
    } finally {
      _activeTransaction = null;
    }
  }

  Stream<T> _watch<T>(
    String collection, {
    required Duration pollInterval,
    required bool fireImmediately,
    required bool Function(CindelChangeSet change) shouldReadChange,
    required Future<T> Function(CindelChangeSet? change) readSnapshot,
    required bool Function(T left, T right)? areSnapshotsEqual,
  }) {
    late final _CindelWatcher<T> watcher;
    watcher = _CindelWatcher<T>(
      pollInterval: pollInterval,
      fireImmediately: fireImmediately,
      shouldPoll: () => _activeTransaction == null,
      readRevision: () => _collectionRevision(collection),
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

  Future<int> _collectionRevision(String collection) async {
    final scalar = decodeScalar(
      await _sendBytes('collectionRevision', {'collection': collection}),
    );
    return scalar is WireScalarInt ? scalar.value : 0;
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

  Future<void> _markNativeCollectionChanged(
    String collection,
    CindelChangeSet Function() localChangeFactory,
  ) async {
    if (_activeTransaction == _TransactionMode.write) {
      _markCollectionChanged(localChangeFactory());
      return;
    }

    final nativeChanges = await _takeNativeChangeSets();
    if (!_hasWatchers(collection)) {
      return;
    }
    final localChange = localChangeFactory();
    final changes = _changesFromNative(nativeChanges, {
      localChange.collection: localChange,
    });
    for (final change in changes) {
      _notifyWatchers(change);
    }
  }

  Future<List<CindelChangeSet>> _nativeChangesForWatchers(
    Map<String, CindelChangeSet> localChanges,
  ) async {
    final nativeChanges = await _takeNativeChangeSets();
    if (!localChanges.keys.any(_hasWatchers)) {
      return const [];
    }
    return _changesFromNative(nativeChanges, localChanges);
  }

  bool _hasWatchers(String collection) {
    return _watchersByCollection[collection]?.isNotEmpty ?? false;
  }

  Future<List<WireChangeSet>> _takeNativeChangeSets() async {
    return decodeChangeSetList(await _sendBytes('takeChanges', const {}));
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
    final localIds = localChange?.documentIds;
    final ids = nativeIds.isEmpty ? localIds?.toSet() : nativeIds;
    final documents = {
      for (final entry
          in (localChange?.documents ?? const <int, CindelDocument>{}).entries)
        if (ids == null || ids.contains(entry.key)) entry.key: entry.value,
    };
    if (ids == null) {
      return CindelChangeSet._(
        collection: change.collection,
        documentIds: null,
        documents: Map<int, CindelDocument>.unmodifiable(documents),
        hasUnknownDocuments: true,
        isExternal: false,
        revision: change.revision,
      );
    }
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

  Future<void> _sendVoid(String operation, Map<String, Object?> payload) async {
    _checkOpen();
    await _bridge.send(operation: operation, payload: _payload(payload));
  }

  Future<Uint8List> _sendBytes(
    String operation,
    Map<String, Object?> payload,
  ) async {
    _checkOpen();
    final response = await _bridge.send(
      operation: operation,
      payload: _payload(payload),
    );
    return _bytesFromPayload(response.payload);
  }

  Future<List<int>> _sendIds(
    String operation,
    Map<String, Object?> payload,
  ) async {
    return decodeIdList(await _sendBytes(operation, payload));
  }

  void _checkOpen() {
    if (_closed) {
      throw CindelDatabaseClosedError();
    }
  }
}

final class _CindelChangeSetBuilder {
  _CindelChangeSetBuilder(this.collection);

  final String collection;
  final Set<int> _documentIds = {};
  final Map<int, CindelDocument> _documents = {};
  bool _unknownIds = false;
  bool _hasUnknownDocuments = false;
  int? _revision;

  void add(CindelChangeSet change) {
    if (change.documentIds == null) {
      _unknownIds = true;
    } else {
      _documentIds.addAll(change.documentIds!);
    }
    _hasUnknownDocuments = _hasUnknownDocuments || change.hasUnknownDocuments;
    final revision = change.revision;
    if (revision != null) {
      final current = _revision;
      _revision = current == null || revision > current ? revision : current;
    }
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
      revision: _revision,
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
    required Future<int> Function() readRevision,
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
  final Future<int> Function() _readRevision;
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
  bool _needsPoll = false;
  bool _pendingForce = false;
  CindelChangeSet? _pendingChange;

  Stream<T> get stream => _controller.stream;

  Future<void> _prime() async {
    if (_isPolling || _controller.isClosed) {
      return;
    }
    _isPolling = true;
    try {
      _lastRevision = await _readRevision();
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
      if (!_controller.isClosed) {
        _needsPoll = true;
        _pendingForce = _pendingForce || force;
        _pendingChange ??= change;
      }
      return;
    }
    if (!force && !_shouldPoll()) {
      return;
    }
    _isPolling = true;
    try {
      final revision = change?.revision ?? await _readRevision();
      if (!force && change != null && !_shouldReadChange(change)) {
        _lastRevision = revision;
        return;
      }
      if (!force && change == null && revision == _lastRevision) {
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
      if (_needsPoll && !_controller.isClosed) {
        final pendingForce = _pendingForce;
        final pendingChange = _pendingChange;
        _needsPoll = false;
        _pendingForce = false;
        _pendingChange = null;
        unawaited(poll(force: pendingForce, change: pendingChange));
      }
    }
  }

  Future<void> close() async {
    _timer?.cancel();
    await _controller.close();
  }
}

// Web sidecar equivalent of the native sync session. It stays private so Web
// apps get the same open-time-only sync contract as native apps.
final class _CindelWebSyncSession {
  _CindelWebSyncSession(this.config);

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
    // Persist a generated client id when the app does not provide one. The id
    // is part of every mutation id, so changing it on reopen would break
    // backend idempotency.
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
    // Use the outbox as a defensive source of truth so pending rows never share
    // a mutation id with newly-created local changes after reopen.
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
    // Avoid closing the Web handle while an adapter cycle can still apply
    // changes through the Worker.
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
    // The sequence doubles as outbox row id and mutation id suffix. That keeps
    // retry deduplication stable across persisted Web storage.
    final sequence = _nextSequence++;
    final clientId = _clientId!;
    await database._syncPersistMutation(
      _CindelWebSyncOutboxRecord(
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
      ),
    );
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
        // Push is idempotent at the adapter boundary. Only accepted rows are
        // removed; unaccepted rows remain durable and will retry.
        final result = await config.adapter.push(
          CindelPushRequest(
            clientId: _clientId!,
            lastPulledCheckpoint: _checkpoint,
            schemaVersionByCollection: schemaVersions,
            mutations: [for (final record in pending) record.toMutation()],
          ),
        );
        await database.writeTxn(() async {
          await database._syncDeleteOutboxIds([
            for (final record in pending)
              if (result.acceptedMutationIds.contains(record.mutationId))
                record.dbId,
          ]);
          if (result.checkpoint != null) {
            _checkpoint = result.checkpoint;
            await database._syncPersistState('checkpoint', _checkpoint);
          }
        });
        if (result.correctedChanges.isNotEmpty) {
          // Backend corrections are applied as guarded remote writes so Web
          // watchers update but no new outgoing mutation is created.
          await database._syncApplyRemoteChanges(result.correctedChanges);
        }
      }
      // Pull after push so the client observes remote state that includes any
      // accepted local mutations and backend-side corrections.
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
    // Status is derived from persisted outbox rows so UI callbacks survive
    // reopen and do not depend on transient in-memory counters.
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

// Durable outgoing mutation row for Web SQLite storage.
final class _CindelWebSyncOutboxRecord {
  const _CindelWebSyncOutboxRecord({
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

// Key/value sync metadata that must not be deleted when accepted outbox rows
// are drained.
final class _CindelWebSyncStateRecord {
  const _CindelWebSyncStateRecord(this.dbId, this.key, this.value);

  final int dbId;
  final String key;
  final String? value;
}

Map<String, CindelCollectionSchema<dynamic>> _schemasByCollection(
  Iterable<CindelCollectionSchema<dynamic>> schemas,
) {
  final byCollection = <String, CindelCollectionSchema<dynamic>>{};
  for (final schema in schemas) {
    if (byCollection.containsKey(schema.name)) {
      throw ArgumentError.value(
        schema.name,
        'schemas',
        'Collection schemas must be unique by name.',
      );
    }
    byCollection[schema.name] = schema;
  }
  return Map.unmodifiable(byCollection);
}

bool _isWebSyncInternalCollection(String collection) {
  return collection == _syncOutboxCollection ||
      collection == _syncStateCollection;
}

int _webSyncStateId(String key) {
  return switch (key) {
    'clientId' => 1,
    'checkpoint' => 2,
    'nextSequence' => 3,
    _ => throw ArgumentError.value(key, 'key', 'Unknown sync state key.'),
  };
}

CindelFieldSchema _webSyncSchemaField({
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

// Web internal schemas are included in the Worker schema manifest only when
// sync is enabled. They are hidden implementation details, not app collections.
final _syncWebInternalSchemas = <CindelCollectionSchema<dynamic>>[
  _syncWebOutboxSchema,
  _syncWebStateSchema,
];

// Schema for durable outgoing Web sync mutations. Field order must stay aligned
// with _writeWebSyncOutboxRecord and _readWebSyncOutboxRecord.
final _syncWebOutboxSchema = CindelCollectionSchema<_CindelWebSyncOutboxRecord>(
  name: _syncOutboxCollection,
  dartName: '_CindelWebSyncOutboxRecord',
  idField: 'dbId',
  fields: [
    _webSyncSchemaField(
      name: 'dbId',
      dartType: 'int',
      binaryType: 'int',
      isId: true,
    ),
    _webSyncSchemaField(
      name: 'baseCheckpoint',
      dartType: 'String?',
      binaryType: 'string',
    ),
    _webSyncSchemaField(
      name: 'clientId',
      dartType: 'String',
      binaryType: 'string',
    ),
    _webSyncSchemaField(
      name: 'collection',
      dartType: 'String',
      binaryType: 'string',
    ),
    _webSyncSchemaField(name: 'documentId', dartType: 'int', binaryType: 'int'),
    _webSyncSchemaField(
      name: 'documentJson',
      dartType: 'String?',
      binaryType: 'string',
    ),
    _webSyncSchemaField(
      name: 'linkName',
      dartType: 'String?',
      binaryType: 'string',
    ),
    _webSyncSchemaField(
      name: 'mutationId',
      dartType: 'String',
      binaryType: 'string',
    ),
    _webSyncSchemaField(
      name: 'operation',
      dartType: 'String',
      binaryType: 'string',
    ),
    _webSyncSchemaField(name: 'sequence', dartType: 'int', binaryType: 'int'),
    _webSyncSchemaField(
      name: 'targetCollection',
      dartType: 'String?',
      binaryType: 'string',
    ),
    _webSyncSchemaField(
      name: 'targetIdsJson',
      dartType: 'String?',
      binaryType: 'string',
    ),
  ],
  toDocument: (record) => {
    'dbId': record.dbId,
    'baseCheckpoint': record.baseCheckpoint,
    'clientId': record.clientId,
    'collection': record.collection,
    'documentId': record.documentId,
    'documentJson': record.documentJson,
    'linkName': record.linkName,
    'mutationId': record.mutationId,
    'operation': record.operation,
    'sequence': record.sequence,
    'targetCollection': record.targetCollection,
    'targetIdsJson': record.targetIdsJson,
  },
  fromDocument: (document) => _CindelWebSyncOutboxRecord(
    dbId: document['dbId'] as int,
    baseCheckpoint: document['baseCheckpoint'] as String?,
    clientId: document['clientId'] as String,
    collection: document['collection'] as String,
    documentId: document['documentId'] as int,
    documentJson: document['documentJson'] as String?,
    linkName: document['linkName'] as String?,
    mutationId: document['mutationId'] as String,
    operation: document['operation'] as String,
    sequence: document['sequence'] as int,
    targetCollection: document['targetCollection'] as String?,
    targetIdsJson: document['targetIdsJson'] as String?,
  ),
  getId: (record) => record.dbId,
  setId: null,
  writeNativeDocument: _writeWebSyncOutboxRecord,
  readNativeDocument: _readWebSyncOutboxRecord,
);

// Schema for compact Web sync key/value metadata.
final _syncWebStateSchema = CindelCollectionSchema<_CindelWebSyncStateRecord>(
  name: _syncStateCollection,
  dartName: '_CindelWebSyncStateRecord',
  idField: 'dbId',
  fields: [
    _webSyncSchemaField(
      name: 'dbId',
      dartType: 'int',
      binaryType: 'int',
      isId: true,
    ),
    _webSyncSchemaField(name: 'key', dartType: 'String', binaryType: 'string'),
    _webSyncSchemaField(
      name: 'value',
      dartType: 'String?',
      binaryType: 'string',
    ),
  ],
  toDocument: (record) => {
    'dbId': record.dbId,
    'key': record.key,
    'value': record.value,
  },
  fromDocument: (document) => _CindelWebSyncStateRecord(
    document['dbId'] as int,
    document['key'] as String,
    document['value'] as String?,
  ),
  getId: (record) => record.dbId,
  setId: null,
  writeNativeDocument: _writeWebSyncStateRecord,
  readNativeDocument: _readWebSyncStateRecord,
);

void _writeWebSyncOutboxRecord(
  CindelNativeDocumentWriter writer,
  _CindelWebSyncOutboxRecord record,
) {
  _writeWebNullableString(writer, 0, record.baseCheckpoint);
  writer.writeString(1, record.clientId);
  writer.writeString(2, record.collection);
  writer.writeInt(3, record.documentId);
  _writeWebNullableString(writer, 4, record.documentJson);
  _writeWebNullableString(writer, 5, record.linkName);
  writer.writeString(6, record.mutationId);
  writer.writeString(7, record.operation);
  writer.writeInt(8, record.sequence);
  _writeWebNullableString(writer, 9, record.targetCollection);
  _writeWebNullableString(writer, 10, record.targetIdsJson);
}

_CindelWebSyncOutboxRecord _readWebSyncOutboxRecord(
  CindelNativeDocumentReader reader,
  int index,
) {
  return _CindelWebSyncOutboxRecord(
    dbId: reader.readId(index),
    baseCheckpoint: reader.readString(index, 0),
    clientId: reader.readString(index, 1)!,
    collection: reader.readString(index, 2)!,
    documentId: reader.readInt(index, 3)!,
    documentJson: reader.readString(index, 4),
    linkName: reader.readString(index, 5),
    mutationId: reader.readString(index, 6)!,
    operation: reader.readString(index, 7)!,
    sequence: reader.readInt(index, 8)!,
    targetCollection: reader.readString(index, 9),
    targetIdsJson: reader.readString(index, 10),
  );
}

void _writeWebSyncStateRecord(
  CindelNativeDocumentWriter writer,
  _CindelWebSyncStateRecord record,
) {
  writer.writeString(0, record.key);
  _writeWebNullableString(writer, 1, record.value);
}

_CindelWebSyncStateRecord _readWebSyncStateRecord(
  CindelNativeDocumentReader reader,
  int index,
) {
  return _CindelWebSyncStateRecord(
    reader.readId(index),
    reader.readString(index, 0)!,
    reader.readString(index, 1),
  );
}

void _writeWebNullableString(
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

WireIndexValue webIndexValueForField(Object value, CindelFieldSchema field) {
  final normalizedType = _nonNullableDartType(field.dartType);
  final wireValue = switch ((normalizedType, value)) {
    ('bool', final bool value) => WireIndexValue.bool(value),
    ('int', final int value) => WireIndexValue.int(
      _checkSqliteInteger(value, 'value'),
    ),
    ('double', final double value) when value.isFinite => WireIndexValue.double(
      value,
    ),
    ('String', final String value) => _stringIndexValue(value, field),
    ('DateTime', final DateTime value) => WireIndexValue.int(
      _checkSqliteInteger(value.microsecondsSinceEpoch, 'value'),
    ),
    ('DateTime', final int value) => WireIndexValue.int(
      _checkSqliteInteger(value, 'value'),
    ),
    ('Duration', final Duration value) => WireIndexValue.int(
      _checkSqliteInteger(value.inMicroseconds, 'value'),
    ),
    ('Duration', final int value) => WireIndexValue.int(
      _checkSqliteInteger(value, 'value'),
    ),
    ('double', final double value) => throw ArgumentError.value(
      value,
      'value',
      'Must be finite.',
    ),
    (_, final bool value) => WireIndexValue.bool(value),
    (_, final int value) => WireIndexValue.int(
      _checkSqliteInteger(value, 'value'),
    ),
    (_, final double value) when value.isFinite => WireIndexValue.double(value),
    (_, final String value) =>
      field.indexType == CindelIndexType.multiEntry
          ? _stringIndexValue(value, field)
          : WireIndexValue.string(value),
    (_, final double value) => throw ArgumentError.value(
      value,
      'value',
      'Must be finite.',
    ),
    _ => throw ArgumentError.value(
      value,
      'value',
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

WireIndexValue _stringIndexValue(String value, CindelFieldSchema field) {
  return WireIndexValue.string(
    field.indexCaseSensitive ? value : value.toLowerCase(),
  );
}

int _stableHashBytes(Uint8List value) {
  final offsetBasis = BigInt.parse('cbf29ce484222325', radix: 16);
  final prime = BigInt.parse('100000001b3', radix: 16);
  final mask = BigInt.parse('7fffffffffffffff', radix: 16);
  var hash = offsetBasis;
  for (final byte in value) {
    hash ^= BigInt.from(byte);
    hash = (hash * prime) & mask;
  }
  return hash.toInt();
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

Uint8List? _nativeFieldTypes(CindelCollectionSchema<dynamic> schema) {
  final fields = schema.fields.toList(growable: false)
    ..sort((left, right) => left.name.compareTo(right.name));
  final nativeFields = fields
      .where((field) => !field.isId)
      .toList(growable: false);
  final bytes = Uint8List(nativeFields.length);
  for (var i = 0; i < nativeFields.length; i += 1) {
    final value = switch (nativeFields[i].binaryType) {
      'bool' => 0,
      'int' => 1,
      'double' => 2,
      'string' => 3,
      'list' => 4,
      'object' => 5,
      _ => null,
    };
    if (value == null) {
      return null;
    }
    bytes[i] = value;
  }
  return bytes;
}

CindelFieldSchema _fieldWithCaseSensitivity(
  CindelFieldSchema field,
  bool caseSensitive,
) {
  return CindelFieldSchema(
    name: field.name,
    dartType: field.dartType,
    binaryType: field.binaryType,
    isId: field.isId,
    isIndexed: field.isIndexed,
    isIndexUnique: field.isIndexUnique,
    isIndexReplace: field.isIndexReplace,
    indexCaseSensitive: caseSensitive,
    indexType: field.indexType,
  );
}

CindelFieldSchema _requireSchemaField(
  CindelCollectionSchema<dynamic> schema,
  String field,
) {
  for (final schemaField in schema.fields) {
    if (schemaField.name == field) {
      return schemaField;
    }
  }
  throw CindelSchemaError(
    'Field `$field` is not registered for `${schema.name}`.',
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
    WireListValue(:final values) =>
      values.map(_wireValueToObject).toList(growable: false),
    WireObjectValue(:final fields) => {
      for (final field in fields) field.name: _wireValueToObject(field.value),
    },
  };
}

JSObject _payload(Map<String, Object?> values) {
  final object = JSObject();
  for (final entry in values.entries) {
    object.setProperty(entry.key.toJS, _toJs(entry.value));
  }
  return object;
}

JSAny? _toJs(Object? value) {
  // Keep this conversion intentionally small. Worker payloads are structured
  // objects plus binary buffers; nested documents must cross as Cindel wire
  // bytes, not ad hoc JS maps.
  return switch (value) {
    null => null,
    String() => value.toJS,
    bool() => value.toJS,
    int() => value.toJS,
    double() => value.toJS,
    Uint8List() => value.toJS,
    _ => throw ArgumentError.value(value, 'value', 'Unsupported JS payload.'),
  };
}

Uint8List _bytesFromPayload(Object? payload) {
  if (payload is JSUint8Array) {
    return payload.toDart;
  }
  throw StateError('Cindel Web worker returned a non-binary payload.');
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
  if (id < 0 || id > _maximumSqliteId) {
    throw RangeError.range(id, 0, _maximumSqliteId, 'id');
  }
}

void _checkPageLimit(int limit) {
  if (limit <= 0) {
    throw ArgumentError.value(limit, 'limit', 'Must be greater than zero.');
  }
}
