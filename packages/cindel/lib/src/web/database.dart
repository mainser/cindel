import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:cindel_annotations/cindel_annotations.dart';

import '../cindel_error.dart';
import '../migration.dart';
import '../schema.dart';
import 'native_document_reader.dart';
import 'schema_manifest.dart';
import 'wire.dart';
import 'worker_bridge.dart';

/// Internal map-shaped document representation used by Cindel runtime bridges.
typedef CindelDocument = Map<String, Object?>;

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
  }) : backend = CindelStorageBackend.sqlite,
       _schemas = Map.of(schemas),
       _bridge = bridge;

  /// Browser database name used by the Web SQLite runtime.
  final String directory;

  /// Web always runs against SQLite through Worker/Wasm.
  final CindelStorageBackend backend;

  final Map<String, CindelCollectionSchema<dynamic>> _schemas;
  final CindelWebWorkerBridge _bridge;
  final Map<String, Set<_RegisteredWatcher>> _watchersByCollection = {};
  final Map<String, _CindelChangeSetBuilder> _changesInTransaction = {};
  bool _closed = false;
  _TransactionMode? _activeTransaction;

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
  }) async {
    _checkDirectory(directory);
    if (migrationPlan != null) {
      await migrationPlan.run(
        directory: directory,
        targetSchemas: schemas,
        backend: backend,
      );
    }
    final schemasByCollection = _schemasByCollection(schemas);
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
      return CindelDatabase._(
        directory: directory,
        schemas: schemasByCollection,
        bridge: bridge,
      );
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
  }) {
    return open(
      directory: 'cindel-memory-${DateTime.now().microsecondsSinceEpoch}',
      schemas: schemas,
      backend: backend,
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
  }) {
    return open(directory: directory, schemas: schemas, backend: backend);
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
        _indexValueForField(
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
          value: _indexValueForField(value, schemaField),
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
    if (schema == null ||
        schema.writeNativeDocument == null ||
        schema.readNativeDocument == null ||
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

  /// Deletes generated native rows from [collection].
  Future<void> deleteAllNativeDocuments(
    String collection,
    Iterable<int> ids,
  ) async {
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
    final ids = await _sendIds('queryPlanDelete', {
      'collection': collection,
      'plan': encodeQueryPlan(plan),
    });
    if (ids.isNotEmpty) {
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
    final schemasByCollection = _schemasByCollection(schemas);
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

Map<String, CindelCollectionSchema<dynamic>> _schemasByCollection(
  Iterable<CindelCollectionSchema<dynamic>> schemas,
) {
  final byCollection = <String, CindelCollectionSchema<dynamic>>{};
  for (final schema in schemas) {
    byCollection[schema.name] = schema;
  }
  return byCollection;
}

WireIndexValue _indexValueForField(Object value, CindelFieldSchema field) {
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
