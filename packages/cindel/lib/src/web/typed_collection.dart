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
/// The Web facade prefers generated SQLite-native rows when the schema exposes
/// a supported native writer. Schemas outside that subset fall back to generic
/// document writes so `Cindel.open(...).typedCollection(schema)` remains usable
/// for manual and lab schemas.
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
  ///
  /// Auto-increment ids are allocated by the Worker/Wasm engine. Supported
  /// generated schemas use the native row batch path; unsupported layouts fall
  /// back to generic indexed documents.
  Future<void> putAll(Iterable<T> objects) async {
    final objectList = objects is List<T>
        ? objects
        : objects.toList(growable: false);
    if (objectList.isEmpty) {
      return;
    }
    final getId = schema.getId;
    if (getId == null) {
      final values = <int, CindelDocument>{};
      for (final object in objectList) {
        final document = schema.toDocument(object);
        values[_idFromDocument(document)] = document;
      }
      return database.putAll(schema.name, values);
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

    return database.putAll(schema.name, {
      for (var i = 0; i < objectList.length; i += 1)
        ids[i]: schema.toDocument(objectList[i]),
    });
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
    final documents = await database.getAll(schema.name, idList);
    return [
      for (var i = 0; i < idList.length; i += 1)
        documents[i] == null
            ? null
            : _objectFromDocument(documents[i]!, idList[i]),
    ];
  }

  /// Deletes the object stored under [id], if it exists.
  Future<void> delete(int id) {
    return deleteAll([id]);
  }

  /// Deletes every object stored under [ids] atomically.
  ///
  /// Generated native-row collections must use the native delete operation;
  /// generic fallback collections use the document-table delete path.
  Future<void> deleteAll(Iterable<int> ids) {
    return _usesNativeDocuments()
        ? database.deleteAllNativeDocuments(schema.name, ids)
        : database.deleteAll(schema.name, ids);
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
      collection: schema.name,
      pollInterval: pollInterval,
      fireImmediately: fireImmediately,
    );
  }

  List<T> _objectsFromDocuments(Iterable<CindelDocument> documents) {
    return documents.map(schema.fromDocument).toList(growable: false);
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

  bool _usesNativeDocuments() {
    return schema.writeNativeDocument != null && _nativeFieldTypes() != null;
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
      final documents = await database.queryEqual(
        schema.name,
        fieldName,
        value,
      );
      return [
        for (final document in documents)
          if (document[schema.idField] is int) document[schema.idField] as int,
      ];
    }
    return database.queryEqualIds(schema.name, fieldName, value);
  }

  T _objectFromDocument(CindelDocument document, int id) {
    final value = document[schema.idField];
    if (value is int) {
      return schema.fromDocument(document);
    }
    return schema.fromDocument(<String, Object?>{
      ...document,
      schema.idField: id,
    });
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
}
