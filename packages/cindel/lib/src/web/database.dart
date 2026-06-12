import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:cindel_annotations/cindel_annotations.dart';

import '../cindel_error.dart';
import '../generic_document.dart';
import '../native/wire.dart';
import '../schema.dart';
import '../text.dart';
import 'schema_manifest.dart';
import 'worker_bridge.dart';

/// A JSON-like document accepted by Cindel's manual API.
typedef CindelDocument = Map<String, Object?>;

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
       _schemas = schemas,
       _bridge = bridge;

  /// Browser database name used by the Web SQLite runtime.
  final String directory;

  /// Web always runs against SQLite through Worker/Wasm.
  final CindelStorageBackend backend;

  final Map<String, CindelCollectionSchema<dynamic>> _schemas;
  final CindelWebWorkerBridge _bridge;
  final Set<String> _genericDocumentCollections = <String>{};
  bool _closed = false;
  _TransactionMode? _activeTransaction;

  /// Whether SQLite can use generated native document readers for this handle.
  bool get usesSqliteNativeDocuments => true;

  /// Returns whether this collection has accepted generic document writes.
  bool collectionHasGenericDocuments(String collection) {
    return _genericDocumentCollections.contains(collection);
  }

  /// Marks a collection as containing generic document rows.
  void markCollectionHasGenericDocuments(String collection) {
    _genericDocumentCollections.add(collection);
  }

  /// Opens a Web SQLite database.
  ///
  /// The schema manifest is sent during open so the Wasm engine can validate
  /// persisted schema metadata before any typed reads or writes run.
  static Future<CindelDatabase> open({
    required String directory,
    Iterable<CindelCollectionSchema<dynamic>> schemas = const [],
    CindelStorageBackend backend = defaultCindelStorageBackend,
  }) async {
    _checkDirectory(directory);
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

  /// Closes this database.
  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    await _bridge.close();
  }

  /// Runs [action] inside a native read transaction.
  Future<T> readTxn<T>(Future<T> Function() action) {
    return _runTransaction(_TransactionMode.read, action);
  }

  /// Runs [action] inside a native write transaction.
  Future<T> writeTxn<T>(Future<T> Function() action) {
    return _runTransaction(_TransactionMode.write, action);
  }

  /// Whether this handle is currently inside a write transaction.
  bool get isInWriteTransaction => _activeTransaction == _TransactionMode.write;

  /// Allocates the next native auto-increment id for [collection].
  Future<int> allocateId(String collection) async {
    final ids = await _sendIds('allocateId', {'collection': collection});
    return ids.single;
  }

  /// Stores [value] in [collection] under [id].
  Future<void> put(String collection, int id, CindelDocument value) {
    return putAll(collection, {id: value});
  }

  /// Stores every document in [values] atomically.
  Future<void> putAll(
    String collection,
    Map<int, CindelDocument> values,
  ) async {
    _checkOpen();
    _checkCollection(collection);
    if (values.isEmpty) {
      return;
    }
    markCollectionHasGenericDocuments(collection);
    final schema = _schemas[collection];
    final writes = <WireIndexedDocumentWrite>[];
    for (final entry in values.entries) {
      _checkId(entry.key);
      final document = Map<String, Object?>.from(entry.value);
      writes.add(
        WireIndexedDocumentWrite(
          id: entry.key,
          bytes: cindelEncodeGenericDocument(document),
          indexes: schema == null
              ? const []
              : _indexEntriesFor(schema, entry.key, document),
        ),
      );
    }
    final bytes = encodeIndexedDocumentWriteBatch(writes);
    await _sendVoid('putAll', {'collection': collection, 'documents': bytes});
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

  /// Stores many documents atomically.
  Future<void> putMany(String collection, Map<int, CindelDocument> values) {
    return putAll(collection, values);
  }

  /// Returns the document stored in [collection] under [id], or `null`.
  Future<CindelDocument?> get(String collection, int id) async {
    return (await getAll(collection, [id])).single;
  }

  /// Returns documents stored under [ids], preserving input order.
  Future<List<CindelDocument?>> getAll(
    String collection,
    Iterable<int> ids,
  ) async {
    final idList = ids.toList(growable: false);
    final response = await _sendBytes('getAll', {
      'collection': collection,
      'ids': encodeIdList(idList),
    });
    return [
      for (final bytes in decodeOptionalDocumentBatch(response))
        bytes == null ? null : cindelDecodeGenericDocument(bytes),
    ];
  }

  /// Returns all documents from [collection].
  ///
  /// Generic Web documents are read through `documentIds + getAll` because the
  /// native query-plan document path is optimized for schema-backed native
  /// rows. This keeps manual `Map` writes visible through the public API.
  Future<List<CindelDocument>> queryAll(String collection) async {
    final ids = await documentIds(collection);
    return documentsByIds(collection, ids);
  }

  /// Returns documents by id.
  Future<List<CindelDocument>> documentsByIds(
    String collection,
    Iterable<int> ids,
  ) async {
    final documents = await getAll(collection, ids);
    return [
      for (final document in documents)
        if (document != null) document,
    ];
  }

  /// Returns ids for every document in [collection].
  Future<List<int>> documentIds(String collection) {
    return _sendIds('documentIds', {'collection': collection});
  }

  /// Returns documents whose indexed [field] equals [value].
  Future<List<CindelDocument>> queryEqual(
    String collection,
    String field,
    Object value,
  ) async {
    final schemaField = _indexedFieldSchema(collection, field);
    final ids = schemaField.indexType == CindelIndexType.hash
        ? _mergeQueryIds(
            await _queryIndexEqualIds(
              collection,
              field,
              _indexValueForField(value, schemaField),
            ),
            await _queryNativeIndexEqualIds(
              collection,
              field,
              value,
              schemaField,
            ),
          )
        : await queryEqualIds(collection, field, value);
    final documents = await documentsByIds(collection, ids);
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
    final genericIds = await _queryIndexEqualIds(
      collection,
      field,
      _indexValueForField(value, schemaField),
    );
    final nativeIds = await _queryNativeIndexEqualIds(
      collection,
      field,
      value,
      schemaField,
    );
    final ids = _mergeQueryIds(genericIds, nativeIds);
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
    final genericIds = await _queryIndexEqualIds(collection, indexName, value);
    final nativeIds = await queryNativePlanIds(
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
    return _mergeQueryIds(genericIds, nativeIds);
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

  Future<List<int>> _queryIndexEqualIds(
    String collection,
    String index,
    WireIndexValue value,
  ) {
    return _sendIds('queryIndexEqual', {
      'collection': collection,
      'index': index,
      'value': encodeIndexValue(value),
    });
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

  List<int> _mergeQueryIds(List<int> genericIds, List<int> nativeIds) {
    if (nativeIds.isEmpty) {
      return genericIds;
    }
    if (genericIds.isEmpty) {
      return nativeIds;
    }
    final seen = <int>{};
    return [
      for (final id in genericIds)
        if (seen.add(id)) id,
      for (final id in nativeIds)
        if (seen.add(id)) id,
    ];
  }

  List<int> _dedupeIds(List<int> ids) {
    final seen = <int>{};
    return [
      for (final id in ids)
        if (seen.add(id)) id,
    ];
  }

  /// Deletes [id] from [collection].
  Future<void> delete(String collection, int id) {
    return deleteAll(collection, [id]);
  }

  /// Deletes [ids] from [collection].
  Future<void> deleteAll(String collection, Iterable<int> ids) async {
    await _sendVoid('deleteAll', {
      'collection': collection,
      'ids': encodeIdList(ids.toList(growable: false)),
    });
  }

  /// Deletes generated native rows from [collection].
  Future<void> deleteAllNativeDocuments(String collection, Iterable<int> ids) {
    return _sendVoid('deleteNativeAll', {
      'collection': collection,
      'ids': encodeIdList(ids.toList(growable: false)),
    });
  }

  /// Executes a native query plan and returns matching documents.
  ///
  /// This is used by generated/native-row paths and internal Web plumbing. The
  /// manual `queryAll` path deliberately uses `documentIds + getAll`.
  Future<List<CindelDocument>> queryNativePlanDocuments(
    String collection,
    WireQueryPlan plan,
  ) async {
    final bytes = await _sendBytes('queryPlanDocuments', {
      'collection': collection,
      'plan': encodeQueryPlan(plan),
    });
    return [
      for (final document in decodeOptionalDocumentBatch(bytes))
        if (document != null) cindelDecodeGenericDocument(document),
    ];
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
  Future<List<int>> deleteNativePlan(String collection, WireQueryPlan plan) {
    return _sendIds('queryPlanDelete', {
      'collection': collection,
      'plan': encodeQueryPlan(plan),
    });
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
    return scalar is WireScalarInt ? scalar.value : 0;
  }

  /// Returns the schema version for [collection].
  Future<int?> schemaVersion(String collection) async {
    final response = await _bridge.send(
      operation: 'schemaVersion',
      payload: _payload({'collection': collection}),
    );
    return response.payload as int?;
  }

  /// Watches are not part of the current single-tab Web preview.
  Stream<CindelDocument?> watchDocument(
    String collection,
    int id, {
    Duration pollInterval = defaultCindelWatchPollInterval,
    bool fireImmediately = true,
  }) {
    throw UnsupportedError('Cindel Web watchers are not available yet.');
  }

  /// Watches are not part of the current single-tab Web preview.
  Stream<void> watchDocumentLazy(
    String collection,
    int id, {
    Duration pollInterval = defaultCindelWatchPollInterval,
    bool fireImmediately = false,
  }) {
    throw UnsupportedError('Cindel Web watchers are not available yet.');
  }

  /// Watches are not part of the current single-tab Web preview.
  Stream<List<CindelDocument>> watchCollection(
    String collection, {
    Duration pollInterval = defaultCindelWatchPollInterval,
    bool fireImmediately = true,
  }) {
    throw UnsupportedError('Cindel Web watchers are not available yet.');
  }

  /// Watches are not part of the current single-tab Web preview.
  Stream<void> watchCollectionLazy({
    required String collection,
    Duration pollInterval = defaultCindelWatchPollInterval,
    bool fireImmediately = false,
  }) {
    throw UnsupportedError('Cindel Web watchers are not available yet.');
  }

  Future<T> _runTransaction<T>(
    _TransactionMode mode,
    Future<T> Function() action,
  ) async {
    _checkOpen();
    if (_activeTransaction != null) {
      throw CindelTransactionError('Nested transactions are not supported.');
    }
    final begin = mode == _TransactionMode.read
        ? 'beginReadTransaction'
        : 'beginWriteTransaction';
    await _sendVoid(begin, const {});
    _activeTransaction = mode;
    try {
      final result = await action();
      await _sendVoid('commitTransaction', const {});
      return result;
    } catch (_) {
      await _sendVoid('rollbackTransaction', const {});
      rethrow;
    } finally {
      _activeTransaction = null;
    }
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

Map<String, CindelCollectionSchema<dynamic>> _schemasByCollection(
  Iterable<CindelCollectionSchema<dynamic>> schemas,
) {
  final byCollection = <String, CindelCollectionSchema<dynamic>>{};
  for (final schema in schemas) {
    byCollection[schema.name] = schema;
  }
  return byCollection;
}

List<WireIndexEntry> _indexEntriesFor(
  CindelCollectionSchema<dynamic> schema,
  int id,
  CindelDocument document,
) {
  final entries = <WireIndexEntry>[];
  for (final field in schema.fields) {
    if (!field.isIndexed || field.isId) {
      continue;
    }
    final value = document[field.name];
    if (value == null) {
      continue;
    }
    if (field.indexType == CindelIndexType.words) {
      if (value is! String) {
        throw ArgumentError.value(
          value,
          'value.${field.name}',
          'Word indexes require String values.',
        );
      }
      for (final token in cindelSplitWords(
        value,
        caseSensitive: field.indexCaseSensitive,
      )) {
        entries.add(
          WireIndexEntry(
            documentId: id,
            indexName: field.name,
            value: _indexValueForField(token, field),
          ),
        );
      }
      continue;
    }
    if (field.indexType == CindelIndexType.multiEntry) {
      if (value is! Iterable) {
        throw ArgumentError.value(
          value,
          'value.${field.name}',
          'Multi-entry indexes require List values.',
        );
      }
      for (final item in value) {
        if (item == null) {
          continue;
        }
        entries.add(
          WireIndexEntry(
            documentId: id,
            indexName: field.name,
            value: _indexValueForField(item, field),
          ),
        );
      }
      continue;
    }
    entries.add(
      WireIndexEntry(
        documentId: id,
        indexName: field.name,
        value: _indexValueForField(value, field),
      ),
    );
  }
  for (final index in schema.compositeIndexes) {
    final values = <WireIndexValue>[];
    var hasAllValues = true;
    for (final fieldName in index.fields) {
      if (!document.containsKey(fieldName) || document[fieldName] == null) {
        hasAllValues = false;
        break;
      }
      final field = _requireSchemaField(schema, fieldName);
      values.add(
        _indexValueForField(
          document[fieldName]!,
          _fieldWithCaseSensitivity(field, index.caseSensitive),
        ),
      );
    }
    if (hasAllValues) {
      entries.add(
        WireIndexEntry(
          documentId: id,
          indexName: index.name,
          value: WireIndexValue.list(values),
        ),
      );
    }
  }
  return entries;
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

void _checkId(int id) {
  if (id < 0 || id > _maximumSqliteId) {
    throw RangeError.range(id, 0, _maximumSqliteId, 'id');
  }
}
