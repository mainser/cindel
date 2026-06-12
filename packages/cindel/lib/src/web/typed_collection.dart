import 'dart:async';
import 'dart:typed_data';

import 'package:cindel_annotations/cindel_annotations.dart';

import '../cindel_error.dart';
import '../schema.dart';
import 'database.dart';
import 'query.dart';

final _nativeFieldTypesCache = Expando<Uint8List>('cindelWebNativeFieldTypes');

/// Adds typed collection access to [CindelDatabase].
extension CindelTypedCollectionAccess on CindelDatabase {
  /// Returns typed access for the generated [schema].
  CindelTypedCollection<T> typedCollection<T>(
    CindelCollectionSchema<T> schema,
  ) {
    return CindelTypedCollection<T>(this, schema);
  }
}

/// Generated typed access to a Cindel collection on Web.
///
/// The Web facade uses generated SQLite-native rows. Schemas that cannot expose
/// native readers and writers are rejected instead of falling back to manual
/// document storage.
final class CindelTypedCollection<T> {
  /// Creates typed collection access over [database] using [schema].
  const CindelTypedCollection(this.database, this.schema);

  /// The database that owns this collection.
  final CindelDatabase database;

  /// Generated schema metadata for this collection.
  final CindelCollectionSchema<T> schema;

  /// Starts a typed query over every object in this collection.
  CindelQuery<T> all() {
    return CindelQuery.all(database: database, schema: schema);
  }

  /// Stores [object].
  Future<void> put(T object) {
    return putAll([object]);
  }

  /// Stores every object atomically.
  Future<void> putAll(Iterable<T> objects) async {
    final objectList = objects is List<T>
        ? objects
        : objects.toList(growable: false);
    if (objectList.isEmpty) {
      return;
    }
    final getId = schema.getId;
    if (getId == null) {
      _throwMissingTypedStorage();
    }

    final setId = schema.setId;
    final ids = <int>[];
    final seenIds = <int>{};
    for (final object in objectList) {
      var id = getId(object);
      if (id == autoIncrement) {
        if (setId == null) {
          throw CindelSchemaError(
            'Generated schema `${schema.dartName}` cannot assign autoIncrement ids.',
          );
        }
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
    }

    final nativeWriter = schema.writeNativeDocument;
    final fieldTypes = _nativeFieldTypes();
    if (nativeWriter != null && fieldTypes != null) {
      return database.putAllNativeBinaryDocuments(
        schema.name,
        ids,
        objectList,
        fieldTypes,
        nativeWriter,
      );
    }

    _throwMissingTypedStorage();
  }

  /// Stores many objects atomically.
  Future<void> putMany(Iterable<T> objects) {
    return putAll(objects);
  }

  /// Stores [object] by a unique replace index.
  ///
  /// Natural-key replacement is not specialized in the Web preview yet. The
  /// method is present so generated APIs compile against the same surface while
  /// Web routes the write through the regular typed path.
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
  ///
  /// See [putByUniqueIndex] for the current Web preview behavior.
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
    return (await getAll([id])).single;
  }

  /// Returns typed objects stored under [ids], preserving input order.
  Future<List<T?>> getAll(Iterable<int> ids) async {
    final idList = ids.toList(growable: false);
    final nativeReader = schema.readNativeDocument;
    final nativeFieldTypes = _nativeFieldTypes();
    if (nativeReader == null || nativeFieldTypes == null) {
      _throwMissingTypedStorage();
    }
    return database.getAllNativeBinaryDocuments(
      schema.name,
      idList,
      nativeFieldTypes,
      nativeReader,
    );
  }

  /// Deletes the object stored under [id], if it exists.
  Future<void> delete(int id) {
    return database.deleteAllNativeDocuments(schema.name, [id]);
  }

  /// Deletes every object stored under [ids] atomically.
  Future<void> deleteAll(Iterable<int> ids) {
    return database.deleteAllNativeDocuments(schema.name, ids);
  }

  /// Watches the typed object stored under [id].
  Stream<T?> watchObject(
    int id, {
    Duration pollInterval = defaultCindelWatchPollInterval,
    bool fireImmediately = true,
  }) {
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

  /// Watches one object and emits without returning the object value.
  Stream<void> watchObjectLazy(
    int id, {
    Duration pollInterval = defaultCindelWatchPollInterval,
    bool fireImmediately = false,
  }) {
    return watchObject(
      id,
      pollInterval: pollInterval,
      fireImmediately: fireImmediately,
    ).map((_) {});
  }

  /// Watches the entire typed collection.
  Stream<List<T>> watchCollection({
    Duration pollInterval = defaultCindelWatchPollInterval,
    bool fireImmediately = true,
  }) {
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

  /// Watches the entire typed collection and emits without returning objects.
  Stream<void> watchCollectionLazy({
    Duration pollInterval = defaultCindelWatchPollInterval,
    bool fireImmediately = false,
  }) {
    return database.watchCollectionLazy(
      collection: schema.name,
      pollInterval: pollInterval,
      fireImmediately: fireImmediately,
    );
  }

  Uint8List? _nativeFieldTypes() {
    // The Worker expects native field tags in persisted schema-field order
    // excluding the id field. Cache by schema object to avoid rebuilding this
    // layout for every batch.
    final cached = _nativeFieldTypesCache[schema];
    if (cached != null) {
      return cached;
    }
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
    _nativeFieldTypesCache[schema] = bytes;
    return bytes;
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
        ? await database.queryCompositeEqualIds(
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
      final setId = schema.setId;
      if (setId == null) {
        throw StateError(
          'Generated schema `${schema.dartName}` cannot assign unique index ids.',
        );
      }
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
      final objects = await CindelQuery.equal(
        database: database,
        schema: schema,
        field: fieldName,
        value: value,
      ).findAll();
      return [for (final object in objects) _idFromObject(object)];
    }
    return database.queryEqualIds(schema.name, fieldName, value);
  }

  int _idFromDocument(CindelDocument document) {
    final value = document[schema.idField];
    if (value is int) {
      return value;
    }
    throw CindelSchemaError(
      'Generated schema `${schema.dartName}` returned a non-int id field '
      '`${schema.idField}`.',
    );
  }

  int _idFromObject(T object) {
    final getId = schema.getId;
    if (getId != null) {
      return getId(object);
    }
    return _idFromDocument(schema.toDocument(object));
  }

  Never _throwMissingTypedStorage() {
    throw CindelSchemaError(
      'Generated schema `${schema.dartName}` does not expose SQLite-native '
      'read/write support required by Cindel Web.',
    );
  }
}
