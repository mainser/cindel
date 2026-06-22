import 'dart:async';
import 'dart:typed_data';

import 'package:cindel_annotations/cindel_annotations.dart';

import 'cindel_error.dart';
import 'database.dart';
import 'query.dart';
import 'schema.dart';

// Typed collection bridge between generated schemas and the database runtime.
// Public methods expose `T` objects and require generated typed storage.
final _nativeFieldTypesCache = Expando<Uint8List>('cindelNativeFieldTypes');

/// Adds typed collection access to [CindelDatabase].
extension CindelTypedCollectionAccess on CindelDatabase {
  /// Returns typed access for the generated [schema].
  ///
  /// Generated extension getters usually call this helper so application code
  /// can use `database.todos` instead of manually wiring schemas.
  CindelTypedCollection<T> typedCollection<T>(
    CindelCollectionSchema<T> schema,
  ) {
    return CindelTypedCollection<T>(this, schema);
  }
}

/// Generated typed access to a Cindel collection.
///
/// Instances are usually created by generated extension getters, for example
/// `database.todos`, instead of being constructed directly by app code.
///
/// This class keeps the public typed API small and delegates persistence details
/// to [CindelDatabase]. Generated schemas must provide binary or native
/// readers/writers for the selected backend.
final class CindelTypedCollection<T> {
  /// Creates typed collection access over [database] using [schema].
  const CindelTypedCollection(this.database, this.schema);

  /// The database that owns this collection.
  final CindelDatabase database;

  /// Generated schema metadata for this collection.
  final CindelCollectionSchema<T> schema;

  /// Starts a typed query over every object in this collection.
  ///
  /// Generated `where()` helpers build on this query and add indexed sources or
  /// filters before execution.
  CindelQuery<T> all() {
    return CindelQuery.all(database: database, schema: schema);
  }

  /// Stores [object] using the id field declared by [schema].
  ///
  /// If the id is [autoIncrement], the next database id is allocated and written
  /// back through the generated id setter before persistence.
  Future<void> put(T object) async {
    if (_usesSqliteNativeDocuments && schema.getId != null) {
      await _putAllBinaryObjects([object]);
      return;
    }
    if (schema.getId == null) {
      _throwMissingGeneratedId();
    }
    var id = _idFromObject(object);
    if (id == autoIncrement) {
      final setId = _idSetter();
      id = await database.allocateId(schema.name);
      setId(object, id);
    }
    if (_usesBinaryDocuments) {
      await database.putBinaryDocument(
        schema.name,
        id,
        schema.toBinaryDocument!(object),
      );
      _bindLinks(object);
      return;
    }
    _throwMissingTypedStorage();
  }

  /// Stores every object atomically.
  ///
  /// Duplicate ids are rejected before the batch reaches storage. Empty batches
  /// are treated as a no-op.
  Future<void> putAll(Iterable<T> objects) async {
    final objectList = objects is List<T>
        ? objects
        : objects.toList(growable: false);
    if (objectList.isEmpty) {
      return;
    }

    if ((_usesBinaryDocuments || _usesSqliteNativeDocuments) &&
        schema.getId != null) {
      return _putAllBinaryObjects(objectList);
    }

    if (schema.getId == null) {
      _throwMissingGeneratedId();
    }

    final binaryValues = _usesBinaryDocuments ? <int, Uint8List>{} : null;
    final seenIds = <int>{};
    CindelSetId<T>? setId;
    for (final object in objectList) {
      var id = _idFromObject(object);
      if (id == autoIncrement) {
        setId ??= _idSetter();
        id = await database.allocateId(schema.name);
        setId(object, id);
      }
      if (!seenIds.add(id)) {
        throw ArgumentError.value(
          id,
          'objects',
          'Bulk writes cannot contain duplicate ids.',
        );
      }
      if (binaryValues != null) {
        binaryValues[id] = schema.toBinaryDocument!(object);
      }
    }

    if (binaryValues != null) {
      return database.putAllBinaryDocuments(schema.name, binaryValues);
    }
    _throwMissingTypedStorage();
  }

  // Shared binary/native batch write path for schemas that expose generated id
  // accessors. Native writers avoid building intermediate binary documents when
  // the backend can accept generated objects directly.
  Future<void> _putAllBinaryObjects(List<T> objects) async {
    final nativeWriter = schema.writeNativeDocument;
    final nativeFieldTypes = _nativeFieldTypes();
    final useNativeWriter = nativeWriter != null && nativeFieldTypes != null;
    final getId = schema.getId!;

    final binaryValues = useNativeWriter ? null : <int, Uint8List>{};
    final seenIds = <int>{};
    final ids = <int>[];
    CindelSetId<T>? setId;

    for (final object in objects) {
      var id = getId(object);
      if (id == autoIncrement) {
        setId ??= _idSetter();
        id = await database.allocateId(schema.name);
        setId(object, id);
      }
      if (!seenIds.add(id)) {
        throw ArgumentError.value(
          id,
          'objects',
          'Bulk writes cannot contain duplicate ids.',
        );
      }
      ids.add(id);
      if (!useNativeWriter) {
        binaryValues![id] = schema.toBinaryDocument!(object);
      }
    }

    if (useNativeWriter) {
      await database.putAllNativeBinaryDocuments(
        schema.name,
        ids,
        objects,
        nativeFieldTypes,
        nativeWriter,
      );
      for (final object in objects) {
        _bindLinks(object);
      }
      return;
    }
    await database.putAllBinaryDocuments(schema.name, binaryValues!);
    for (final object in objects) {
      _bindLinks(object);
    }
  }

  /// Stores many objects atomically.
  ///
  /// Alias for [putAll], provided for APIs that prefer `many` naming.
  Future<void> putMany(Iterable<T> objects) {
    return putAll(objects);
  }

  /// Stores [object] by a unique replace index, reusing an existing id.
  Future<void> putByUniqueIndex(
    T object, {
    required String indexName,
    required List<Object?> values,
    required bool isComposite,
  }) async {
    Future<void> writeObject() async {
      await _reuseUniqueIndexId(
        object,
        indexName: indexName,
        values: values,
        isComposite: isComposite,
      );
      await put(object);
    }

    if (database.isInWriteTransaction) {
      await writeObject();
    } else {
      await database.writeTxn(writeObject);
    }
  }

  /// Stores every object by a unique replace index.
  Future<void> putAllByUniqueIndex(
    Iterable<T> objects, {
    required String indexName,
    required List<Object?> Function(T object) values,
    required bool isComposite,
  }) async {
    final objectList = objects is List<T>
        ? objects
        : objects.toList(growable: false);
    if (objectList.isEmpty) {
      return;
    }
    Future<void> writeObjects() async {
      for (final object in objectList) {
        await _reuseUniqueIndexId(
          object,
          indexName: indexName,
          values: values(object),
          isComposite: isComposite,
        );
      }
      await putAll(objectList);
    }

    if (database.isInWriteTransaction) {
      await writeObjects();
    } else {
      await database.writeTxn(writeObjects);
    }
  }

  /// Returns the typed object stored under [id], or `null`.
  Future<T?> get(int id) async {
    if (_usesSqliteNativeDocuments) {
      return (await getAll([id])).single;
    }
    if (_usesBinaryDocuments) {
      final bytes = await database.getBinaryDocument(schema.name, id);
      return bytes == null ? null : _objectFromBinaryDocument(bytes, id);
    }
    _throwMissingTypedStorage();
  }

  /// Returns typed objects stored under [ids], preserving input order.
  ///
  /// Missing ids are returned as `null`.
  Future<List<T?>> getAll(Iterable<int> ids) async {
    final idList = ids.toList(growable: false);
    if (_usesBinaryDocuments || _usesSqliteNativeDocuments) {
      final nativeReader = schema.readNativeDocument;
      final nativeFieldTypes = _nativeFieldTypes();
      if (nativeReader != null && nativeFieldTypes != null) {
        final objects = await database.getAllNativeBinaryDocuments(
          schema.name,
          idList,
          nativeFieldTypes,
          nativeReader,
        );
        return [
          for (final object in objects)
            if (object == null) null else _bindLinks(object),
        ];
      }
      final documents = await database.getAllBinaryDocuments(
        schema.name,
        idList,
      );
      return [
        for (var i = 0; i < documents.length; i += 1)
          documents[i] == null
              ? null
              : _objectFromBinaryDocument(documents[i]!, idList[i]),
      ];
    }
    _throwMissingTypedStorage();
  }

  /// Deletes the object stored under [id], if it exists.
  Future<void> delete(int id) {
    if (_usesSqliteNativeDocuments) {
      return database.deleteAllNativeDocuments(schema.name, [id]);
    }
    return database.delete(schema.name, id);
  }

  /// Deletes every object stored under [ids] atomically.
  Future<void> deleteAll(Iterable<int> ids) {
    if (_usesSqliteNativeDocuments) {
      return database.deleteAllNativeDocuments(schema.name, ids);
    }
    return database.deleteAll(schema.name, ids);
  }

  /// Watches the typed object stored under [id].
  ///
  /// The stream emits the current value when [fireImmediately] is true, then
  /// emits again when the underlying document changes.
  Stream<T?> watchObject(
    int id, {
    Duration pollInterval = defaultCindelWatchPollInterval,
    bool fireImmediately = true,
  }) {
    if (_usesBinaryDocuments || _usesSqliteNativeDocuments) {
      final snapshots = database
          .watchCollectionChanges(
            schema.name,
            pollInterval: pollInterval,
            fireImmediately: true,
          )
          .where((change) => change.mayAffectDocument(id))
          .asyncMap((_) => get(id))
          .transform(_distinctObjectSnapshots());
      return fireImmediately ? snapshots : snapshots.skip(1);
    }
    _throwMissingTypedStorage();
  }

  /// Watches one object and emits without returning the object value.
  Stream<void> watchObjectLazy(
    int id, {
    Duration pollInterval = defaultCindelWatchPollInterval,
    bool fireImmediately = false,
  }) {
    if (_usesBinaryDocuments || _usesSqliteNativeDocuments) {
      return watchObject(
        id,
        pollInterval: pollInterval,
        fireImmediately: fireImmediately,
      ).map((_) {});
    }
    _throwMissingTypedStorage();
  }

  /// Watches the entire typed collection.
  ///
  /// Each event contains the full decoded collection snapshot.
  Stream<List<T>> watchCollection({
    Duration pollInterval = defaultCindelWatchPollInterval,
    bool fireImmediately = true,
  }) {
    if (_usesBinaryDocuments || _usesSqliteNativeDocuments) {
      final snapshots = database
          .watchCollectionChanges(
            schema.name,
            pollInterval: pollInterval,
            fireImmediately: true,
          )
          .asyncMap((_) => all().findAll())
          .transform(_distinctCollectionSnapshots());
      return fireImmediately ? snapshots : snapshots.skip(1);
    }
    _throwMissingTypedStorage();
  }

  /// Watches the entire typed collection and emits without returning objects.
  Stream<void> watchCollectionLazy({
    Duration pollInterval = defaultCindelWatchPollInterval,
    bool fireImmediately = false,
  }) {
    if (_usesBinaryDocuments || _usesSqliteNativeDocuments) {
      return watchCollection(
        pollInterval: pollInterval,
        fireImmediately: fireImmediately,
      ).map((_) {});
    }
    _throwMissingTypedStorage();
  }

  StreamTransformer<T?, T?> _distinctObjectSnapshots() {
    T? previous;
    var hasPrevious = false;
    return StreamTransformer<T?, T?>.fromHandlers(
      handleData: (snapshot, sink) {
        if (hasPrevious && _objectsEqual(previous, snapshot)) {
          previous = snapshot;
          return;
        }
        previous = snapshot;
        hasPrevious = true;
        sink.add(snapshot);
      },
    );
  }

  StreamTransformer<List<T>, List<T>> _distinctCollectionSnapshots() {
    List<T>? previous;
    return StreamTransformer<List<T>, List<T>>.fromHandlers(
      handleData: (snapshot, sink) {
        final last = previous;
        if (last != null && _objectListsEqual(last, snapshot)) {
          previous = snapshot;
          return;
        }
        previous = snapshot;
        sink.add(snapshot);
      },
    );
  }

  bool _objectListsEqual(List<T> left, List<T> right) {
    if (left.length != right.length) {
      return false;
    }
    for (var i = 0; i < left.length; i += 1) {
      if (!_objectsEqual(left[i], right[i])) {
        return false;
      }
    }
    return true;
  }

  bool _objectsEqual(T? left, T? right) {
    if (left == null || right == null) {
      return left == right;
    }
    final getId = schema.getId;
    if (getId != null && getId(left) != getId(right)) {
      return false;
    }
    return _documentsEqual(schema.toDocument(left), schema.toDocument(right));
  }

  bool _documentsEqual(Object? left, Object? right) {
    if (identical(left, right)) {
      return true;
    }
    if (left is Map && right is Map) {
      if (left.length != right.length) {
        return false;
      }
      for (final entry in left.entries) {
        if (!right.containsKey(entry.key) ||
            !_documentsEqual(entry.value, right[entry.key])) {
          return false;
        }
      }
      return true;
    }
    if (left is List && right is List) {
      if (left.length != right.length) {
        return false;
      }
      for (var i = 0; i < left.length; i += 1) {
        if (!_documentsEqual(left[i], right[i])) {
          return false;
        }
      }
      return true;
    }
    return left == right;
  }

  bool get _usesBinaryDocuments {
    return database.backend == CindelStorageBackend.mdbx &&
        schema.toBinaryDocument != null &&
        schema.fromBinaryDocument != null;
  }

  // SQLite native documents use generated object readers/writers directly.
  bool get _usesSqliteNativeDocuments {
    return database.usesSqliteNativeDocuments &&
        schema.writeNativeDocument != null &&
        schema.readNativeDocument != null;
  }

  // Encodes the generated field type layout expected by native readers/writers.
  // The result is cached per schema because the layout is stable for a database
  // handle and sorting fields repeatedly is unnecessary.
  Uint8List? _nativeFieldTypes() {
    final cached = _nativeFieldTypesCache[schema];
    if (cached != null) {
      return cached;
    }
    final fields = schema.fields.toList(growable: false)
      ..sort((left, right) => left.name.compareTo(right.name));
    final binaryFields = fields
        .where((field) => !field.isId)
        .toList(growable: false);
    final bytes = Uint8List(binaryFields.length);
    for (var i = 0; i < binaryFields.length; i += 1) {
      final type = binaryFields[i].binaryType;
      final value = switch (type) {
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
    _nativeFieldTypesCache[schema] = bytes;
    return bytes;
  }

  // Decodes schema-backed binary document bytes and reattaches the external id
  // when the payload stores ids outside the binary body.
  T _objectFromBinaryDocument(Uint8List bytes, int id) {
    final object = schema.fromBinaryDocument!(bytes);
    schema.setId?.call(object, id);
    return _bindLinks(object);
  }

  T _bindLinks(T object) {
    schema.bindLinks?.call(database, schema, object);
    return object;
  }

  // Reads the id through the generated accessor when available, otherwise from
  // the generated document map.
  int _idFromObject(T object) {
    final getId = schema.getId;
    if (getId != null) {
      return getId(object);
    }
    _throwMissingGeneratedId();
  }

  Future<void> _reuseUniqueIndexId(
    T object, {
    required String indexName,
    required List<Object?> values,
    required bool isComposite,
  }) async {
    if (values.any((value) => value == null)) {
      return;
    }
    final existingIds = isComposite
        ? database.queryCompositeEqualIds(
            schema.name,
            indexName,
            values.cast<Object>(),
          )
        : await _queryUniqueFieldIds(indexName, values.single as Object);
    if (existingIds.isEmpty) {
      return;
    }
    final existingId = existingIds.first;
    if (existingIds.any((id) => id != existingId)) {
      throw StateError(
        'Unique index `$indexName` returned more than one existing id.',
      );
    }
    final currentId = _idFromObject(object);
    if (currentId != existingId) {
      final setId = _idSetter();
      setId(object, existingId);
    }
  }

  Future<List<int>> _queryUniqueFieldIds(String fieldName, Object value) async {
    final field = schema.fields.firstWhere(
      (field) => field.name == fieldName,
      orElse: () => throw StateError(
        'Unique index `$fieldName` is not declared in `${schema.name}`.',
      ),
    );
    if (field.indexType == CindelIndexType.hash) {
      throw CindelQueryError(
        'Hash unique replace index `$fieldName` requires document '
        'verification and is not supported by typed id lookup.',
      );
    }
    return database.queryEqualIds(schema.name, fieldName, value);
  }

  Never _throwMissingGeneratedId() {
    throw StateError(
      'Generated schema `${schema.dartName}` must provide typed id accessors.',
    );
  }

  Never _throwMissingTypedStorage() {
    throw StateError(
      'Generated schema `${schema.dartName}` does not expose a typed storage '
      'path for backend `${database.backend.name}`.',
    );
  }

  // Returns the generated id setter required by auto-increment writes.
  CindelSetId<T> _idSetter() {
    final setId = schema.setId;
    if (setId == null) {
      throw StateError(
        'Generated schema `${schema.dartName}` uses autoIncrement but did not '
        'provide an id setter.',
      );
    }
    return setId;
  }
}
