/// Converts a typed object into a Cindel document.
typedef CindelToDocument<T> = Map<String, Object?> Function(T object);

/// Converts a Cindel document into a typed object.
typedef CindelFromDocument<T> = T Function(Map<String, Object?> document);

/// Assigns a generated id to a typed object before it is persisted.
typedef CindelSetId<T> = void Function(T object, int id);

/// Generated metadata for a Cindel collection.
final class CindelCollectionSchema<T> {
  /// Creates generated metadata for a Cindel collection.
  CindelCollectionSchema({
    required this.name,
    required this.dartName,
    required this.idField,
    required Iterable<CindelFieldSchema> fields,
    required this.toDocument,
    required this.fromDocument,
    this.setId,
  }) : fields = List.unmodifiable(fields);

  /// The storage collection name.
  final String name;

  /// The Dart class name represented by this schema.
  final String dartName;

  /// The field used as the document id.
  final String idField;

  /// Generated metadata for fields persisted by this schema.
  final List<CindelFieldSchema> fields;

  /// Serializes typed objects into Cindel documents.
  final CindelToDocument<T> toDocument;

  /// Deserializes Cindel documents into typed objects.
  final CindelFromDocument<T> fromDocument;

  /// Assigns native auto-increment ids to typed objects.
  final CindelSetId<T>? setId;
}

/// Generated metadata for a persisted field.
final class CindelFieldSchema {
  /// Creates generated metadata for a persisted field.
  const CindelFieldSchema({
    required this.name,
    required this.dartType,
    required this.isId,
    required this.isIndexed,
  });

  /// The stored field name.
  final String name;

  /// The Dart type as written by the analyzer.
  final String dartType;

  /// Whether this field stores the Cindel document id.
  final bool isId;

  /// Whether this field is marked with `@index`.
  final bool isIndexed;
}
