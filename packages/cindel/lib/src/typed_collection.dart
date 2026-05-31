import 'dart:typed_data';

import 'package:cindel_annotations/cindel_annotations.dart';

import 'database.dart';
import 'query.dart';
import 'schema.dart';

final _nativeFieldTypesCache = Expando<Uint8List>('cindelNativeFieldTypes');

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
    if (_usesSqliteNativeDocuments && schema.getId != null) {
      return _putAllBinaryObjects([object]);
    }
    var document = schema.getId == null ? schema.toDocument(object) : null;
    var id = _idFromObject(object, document);
    if (id == autoIncrement) {
      final setId = _idSetter();
      id = await database.allocateId(schema.name);
      setId(object, id);
      document = null;
    }
    document ??= schema.toDocument(object);
    if (_usesBinaryDocuments) {
      return database.putBinaryDocument(
        schema.name,
        id,
        schema.toBinaryDocument!(object),
        document: document,
      );
    }
    return database.put(schema.name, id, document);
  }

  /// Stores every object atomically.
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

    final binaryValues = _usesBinaryDocuments ? <int, Uint8List>{} : null;
    final values = binaryValues == null ? <int, CindelDocument>{} : null;
    final changedDocuments = binaryValues == null
        ? null
        : <int, CindelDocument>{};
    final seenIds = <int>{};
    CindelSetId<T>? setId;
    for (final object in objectList) {
      var document = schema.getId == null ? schema.toDocument(object) : null;
      var id = _idFromObject(object, document);
      if (id == autoIncrement) {
        setId ??= _idSetter();
        id = await database.allocateId(schema.name);
        setId(object, id);
        document = null;
      }
      document ??= schema.toDocument(object);
      if (!seenIds.add(id)) {
        throw ArgumentError.value(
          id,
          'objects',
          'Bulk writes cannot contain duplicate ids.',
        );
      }
      if (binaryValues == null) {
        values![id] = document;
      } else {
        binaryValues[id] = schema.toBinaryDocument!(object);
        changedDocuments![id] = document;
      }
    }

    if (binaryValues != null) {
      return database.putAllBinaryDocuments(
        schema.name,
        binaryValues,
        documents: changedDocuments,
      );
    }
    return database.putAll(schema.name, values!);
  }

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
      return database.putAllNativeBinaryDocuments(
        schema.name,
        ids,
        objects,
        nativeFieldTypes,
        nativeWriter,
        documents: () => {
          for (var i = 0; i < objects.length; i += 1)
            ids[i]: schema.toDocument(objects[i]),
        },
      );
    }
    return database.putAllBinaryDocuments(schema.name, binaryValues!);
  }

  /// Stores many objects atomically.
  ///
  /// Alias for [putAll], provided for APIs that prefer `many` naming.
  Future<void> putMany(Iterable<T> objects) {
    return putAll(objects);
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
    final document = await database.get(schema.name, id);
    return document == null ? null : _objectFromDocument(document, id);
  }

  /// Returns typed objects stored under [ids], preserving input order.
  Future<List<T?>> getAll(Iterable<int> ids) async {
    final idList = ids.toList(growable: false);
    if (_usesBinaryDocuments || _usesSqliteNativeDocuments) {
      final nativeReader = schema.readNativeDocument;
      final nativeFieldTypes = _nativeFieldTypes();
      try {
        if (nativeReader != null && nativeFieldTypes != null) {
          return await database.getAllNativeBinaryDocuments(
            schema.name,
            idList,
            nativeFieldTypes,
            nativeReader,
          );
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
      } on Object {
        database.markCollectionHasGenericDocuments(schema.name);
      }
    }
    final documents = await database.getAll(schema.name, idList);
    return [
      for (var i = 0; i < documents.length; i += 1)
        documents[i] == null
            ? null
            : _objectFromDocument(documents[i]!, idList[i]),
    ];
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
          (document) =>
              document == null ? null : _objectFromDocument(document, id),
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

  bool get _usesBinaryDocuments {
    return database.backend == CindelStorageBackend.mdbx &&
        !database.collectionHasGenericDocuments(schema.name) &&
        schema.toBinaryDocument != null &&
        schema.fromBinaryDocument != null;
  }

  bool get _usesSqliteNativeDocuments {
    return database.usesSqliteNativeDocuments &&
        !database.collectionHasGenericDocuments(schema.name) &&
        schema.writeNativeDocument != null &&
        schema.readNativeDocument != null;
  }

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

  T _objectFromBinaryDocument(Uint8List bytes, int id) {
    final object = schema.fromBinaryDocument!(bytes);
    schema.setId?.call(object, id);
    return object;
  }

  T _objectFromDocument(CindelDocument document, int id) {
    if (document[schema.idField] is int) {
      return schema.fromDocument(document);
    }
    return schema.fromDocument(<String, Object?>{
      ...document,
      schema.idField: id,
    });
  }

  int _idFromObject(T object, CindelDocument? document) {
    final getId = schema.getId;
    if (getId != null) {
      return getId(object);
    }
    return _idFromDocument(document ?? schema.toDocument(object));
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
