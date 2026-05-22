import 'package:cindel_annotations/cindel_annotations.dart';

import 'database.dart';
import 'query.dart';
import 'schema.dart';

/// Adds typed collection access to [CindelDatabase].
extension CindelTypedCollectionAccess on CindelDatabase {
  /// Returns typed generated access for [schema].
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

  /// Stores [object] using the id field declared by [schema].
  Future<void> put(T object) async {
    var document = schema.toDocument(object);
    var id = _idFromDocument(document);
    if (id == autoIncrement) {
      final setId = _idSetter();
      id = await database.allocateId(schema.name);
      setId(object, id);
      document = schema.toDocument(object);
    }
    return database.put(schema.name, id, document);
  }

  /// Stores every object atomically.
  Future<void> putAll(Iterable<T> objects) async {
    final objectList = objects.toList(growable: false);
    if (objectList.isEmpty) {
      return;
    }

    final values = <int, CindelDocument>{};
    final seenIds = <int>{};
    CindelSetId<T>? setId;
    for (final object in objectList) {
      var document = schema.toDocument(object);
      var id = _idFromDocument(document);
      if (id == autoIncrement) {
        setId ??= _idSetter();
        id = await database.allocateId(schema.name);
        setId(object, id);
        document = schema.toDocument(object);
      }
      if (!seenIds.add(id)) {
        throw ArgumentError.value(
          id,
          'objects',
          'Bulk writes cannot contain duplicate ids.',
        );
      }
      values[id] = document;
    }

    return database.putAll(schema.name, values);
  }

  /// Stores many objects atomically.
  ///
  /// Alias for [putAll], provided for APIs that prefer `many` naming.
  Future<void> putMany(Iterable<T> objects) {
    return putAll(objects);
  }

  /// Returns the typed object stored under [id], or `null`.
  Future<T?> get(int id) async {
    final document = await database.get(schema.name, id);
    return document == null ? null : schema.fromDocument(document);
  }

  /// Returns typed objects stored under [ids], preserving input order.
  Future<List<T?>> getAll(Iterable<int> ids) async {
    final documents = await database.getAll(schema.name, ids);
    return [
      for (final document in documents)
        document == null ? null : schema.fromDocument(document),
    ];
  }

  /// Deletes the object stored under [id], if it exists.
  Future<void> delete(int id) {
    return database.delete(schema.name, id);
  }

  /// Deletes every object stored under [ids] atomically.
  Future<void> deleteAll(Iterable<int> ids) {
    return database.deleteAll(schema.name, ids);
  }

  /// Watches the typed object stored under [id].
  Stream<T?> watchObject(
    int id, {
    Duration pollInterval = defaultCindelWatchPollInterval,
    bool fireImmediately = true,
  }) {
    return database
        .watchDocument(
          schema.name,
          id,
          pollInterval: pollInterval,
          fireImmediately: fireImmediately,
        )
        .map(
          (document) => document == null ? null : schema.fromDocument(document),
        );
  }

  /// Watches one object and emits without returning the object value.
  Stream<void> watchObjectLazy(
    int id, {
    Duration pollInterval = defaultCindelWatchPollInterval,
    bool fireImmediately = false,
  }) {
    return database.watchDocumentLazy(
      schema.name,
      id,
      pollInterval: pollInterval,
      fireImmediately: fireImmediately,
    );
  }

  /// Watches the entire typed collection.
  Stream<List<T>> watchCollection({
    Duration pollInterval = defaultCindelWatchPollInterval,
    bool fireImmediately = true,
  }) {
    return database
        .watchCollection(
          schema.name,
          pollInterval: pollInterval,
          fireImmediately: fireImmediately,
        )
        .map(_objectsFromDocuments);
  }

  /// Watches the entire typed collection and emits without returning objects.
  Stream<void> watchCollectionLazy({
    Duration pollInterval = defaultCindelWatchPollInterval,
    bool fireImmediately = false,
  }) {
    return database.watchCollectionLazy(
      schema.name,
      pollInterval: pollInterval,
      fireImmediately: fireImmediately,
    );
  }

  List<T> _objectsFromDocuments(Iterable<CindelDocument> documents) {
    return documents.map(schema.fromDocument).toList(growable: false);
  }

  int _idFromDocument(CindelDocument document) {
    final value = document[schema.idField];
    if (value is int) {
      return value;
    }
    throw StateError(
      'Generated schema `${schema.dartName}` returned a non-int id field '
      '`${schema.idField}`.',
    );
  }

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
