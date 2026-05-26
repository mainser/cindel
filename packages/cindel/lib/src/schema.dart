import 'dart:typed_data';

import 'package:cindel_annotations/cindel_annotations.dart';

/// Raw bytes encoded with Cindel's generated binary document format.
typedef CindelBinaryDocumentBytes = Uint8List;

/// Converts a typed object into a Cindel document.
typedef CindelToDocument<T> = Map<String, Object?> Function(T object);

/// Converts a Cindel document into a typed object.
typedef CindelFromDocument<T> = T Function(Map<String, Object?> document);

/// Converts a typed object into Cindel's binary document format.
typedef CindelToBinaryDocument<T> =
    CindelBinaryDocumentBytes Function(T object);

/// Converts Cindel binary document bytes into a typed object.
typedef CindelFromBinaryDocument<T> =
    T Function(CindelBinaryDocumentBytes bytes);

/// Reads the generated id field from a typed object.
typedef CindelGetId<T> = int Function(T object);

/// Writes a typed object into a native binary document writer.
typedef CindelWriteNativeDocument<T> =
    void Function(CindelNativeDocumentWriter writer, T object);

/// Reads a typed object from a native binary document reader.
typedef CindelReadNativeDocument<T> =
    T Function(CindelNativeDocumentReader reader, int documentIndex);

/// Assigns a generated id to a typed object before it is persisted.
typedef CindelSetId<T> = void Function(T object, int id);

/// Writer used by generated typed serializers for native binary documents.
abstract interface class CindelNativeDocumentWriter {
  /// Writes a null value to [fieldIndex].
  void writeNull(int fieldIndex);

  /// Writes a boolean value to [fieldIndex].
  void writeBool(int fieldIndex, bool value);

  /// Writes an integer value to [fieldIndex].
  void writeInt(int fieldIndex, int value);

  /// Writes a double value to [fieldIndex].
  void writeDouble(int fieldIndex, double value);

  /// Writes a string value to [fieldIndex].
  void writeString(int fieldIndex, String value);

  /// Starts writing a list value to [fieldIndex].
  CindelNativeDocumentWriter beginList(int fieldIndex, int length);

  /// Finishes a list value started with [beginList].
  void endList(CindelNativeDocumentWriter listWriter);
}

/// Reader used by generated typed deserializers for native binary documents.
abstract interface class CindelNativeDocumentReader {
  /// Number of documents or list values exposed by this reader.
  int get length;

  /// Whether the document at [documentIndex] exists.
  bool isPresent(int documentIndex);

  /// Reads a nullable boolean value.
  bool? readBool(int documentIndex, int fieldIndex);

  /// Reads a nullable integer value.
  int? readInt(int documentIndex, int fieldIndex);

  /// Reads a nullable double value.
  double? readDouble(int documentIndex, int fieldIndex);

  /// Reads a nullable string value.
  String? readString(int documentIndex, int fieldIndex);

  /// Reads a nested list value as a child reader.
  CindelNativeDocumentReader? readList(int documentIndex, int fieldIndex);

  /// Releases native memory held by this reader.
  void release();
}

/// Generated metadata for a Cindel collection.
final class CindelCollectionSchema<T> {
  /// Creates generated metadata for a Cindel collection.
  CindelCollectionSchema({
    required this.name,
    required this.dartName,
    required this.idField,
    required Iterable<CindelFieldSchema> fields,
    Iterable<CindelCompositeIndexSchema> compositeIndexes = const [],
    required this.toDocument,
    required this.fromDocument,
    this.toBinaryDocument,
    this.fromBinaryDocument,
    this.getId,
    this.writeNativeDocument,
    this.readNativeDocument,
    this.setId,
  }) : fields = List.unmodifiable(fields),
       compositeIndexes = List.unmodifiable(compositeIndexes);

  /// The storage collection name.
  final String name;

  /// The Dart class name represented by this schema.
  final String dartName;

  /// The field used as the document id.
  final String idField;

  /// Generated metadata for fields persisted by this schema.
  final List<CindelFieldSchema> fields;

  /// Generated metadata for composite indexes persisted by this schema.
  final List<CindelCompositeIndexSchema> compositeIndexes;

  /// Serializes typed objects into Cindel documents.
  final CindelToDocument<T> toDocument;

  /// Deserializes Cindel documents into typed objects.
  final CindelFromDocument<T> fromDocument;

  /// Serializes typed objects into Cindel binary documents.
  final CindelToBinaryDocument<T>? toBinaryDocument;

  /// Deserializes Cindel binary documents into typed objects.
  final CindelFromBinaryDocument<T>? fromBinaryDocument;

  /// Reads the generated id from typed objects without creating documents.
  final CindelGetId<T>? getId;

  /// Writes typed objects into native binary document writers.
  final CindelWriteNativeDocument<T>? writeNativeDocument;

  /// Reads typed objects from native binary document readers.
  final CindelReadNativeDocument<T>? readNativeDocument;

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
    this.binaryType,
    this.isIndexUnique = false,
    this.indexCaseSensitive = true,
    this.indexType = CindelIndexType.value,
  });

  /// The stored field name.
  final String name;

  /// The Dart type as written by the analyzer.
  final String dartType;

  /// The schema-backed binary storage type used by generated serializers.
  final String? binaryType;

  /// Whether this field stores the Cindel document id.
  final bool isId;

  /// Whether this field is marked with `@index`.
  final bool isIndexed;

  /// Whether this indexed field requires unique values.
  final bool isIndexUnique;

  /// Whether string index lookups are case-sensitive.
  final bool indexCaseSensitive;

  /// Storage strategy used for this index.
  final CindelIndexType indexType;
}

/// Generated metadata for a collection-level composite index.
final class CindelCompositeIndexSchema {
  /// Creates generated metadata for a composite index.
  CindelCompositeIndexSchema({
    required this.name,
    required Iterable<String> fields,
    this.isUnique = false,
    this.caseSensitive = true,
  }) : fields = List.unmodifiable(fields);

  /// Stable native index name.
  final String name;

  /// Indexed field names in index order.
  final List<String> fields;

  /// Whether the full composite value must be unique.
  final bool isUnique;

  /// Whether string values keep case-sensitive lookup semantics.
  final bool caseSensitive;
}
