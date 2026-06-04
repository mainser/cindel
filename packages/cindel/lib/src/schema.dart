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

  /// Writes an embedded object value to [fieldIndex].
  void writeObject(int fieldIndex, Map<String, Object?> value);

  /// Writes an embedded object list value to [fieldIndex].
  void writeObjectList(int fieldIndex, List<Map<String, Object?>?> value);

  /// Starts writing a list value to [fieldIndex].
  CindelNativeDocumentWriter beginList(int fieldIndex, int length);

  /// Finishes a list value started with [beginList].
  void endList(CindelNativeDocumentWriter listWriter);
}

/// Optional fast path for generated native serializers writing string lists.
abstract interface class CindelNativeStringListDocumentWriter
    implements CindelNativeDocumentWriter {
  /// Writes a non-null string list value to [fieldIndex].
  void writeStringList(int fieldIndex, List<String> value);
}

/// Optional fast path for generated native serializers writing embedded
/// objects without building intermediate Dart maps.
abstract interface class CindelNativeObjectDocumentWriter
    implements CindelNativeDocumentWriter {
  /// Starts writing an embedded object value to [fieldIndex].
  CindelNativeDocumentWriter beginObject(
    int fieldIndex,
    List<String> fieldNames,
  );

  /// Finishes an embedded object value started with [beginObject].
  void endObject(CindelNativeDocumentWriter objectWriter);
}

/// Optional fast path for generated native deserializers reading embedded
/// objects without decoding the whole payload into a Dart map.
abstract interface class CindelNativeObjectDocumentReader
    implements CindelNativeDocumentReader {
  /// Reads an embedded object value as a child reader.
  CindelNativeDocumentReader? readObjectReader(
    int documentIndex,
    int fieldIndex,
    List<String> fieldNames,
  );
}

/// Writes [value] through the fastest string-list path supported by [writer].
void cindelWriteNativeStringList(
  CindelNativeDocumentWriter writer,
  int fieldIndex,
  List<String> value,
) {
  if (writer is CindelNativeStringListDocumentWriter) {
    writer.writeStringList(fieldIndex, value);
    return;
  }
  final listWriter = writer.beginList(fieldIndex, value.length);
  for (var i = 0; i < value.length; i += 1) {
    listWriter.writeString(i, value[i]);
  }
  writer.endList(listWriter);
}

/// Writes an embedded object through the fastest object path supported by
/// [writer].
void cindelWriteNativeObject<T>(
  CindelNativeDocumentWriter writer,
  int fieldIndex,
  List<String> fieldNames,
  T value,
  void Function(CindelNativeDocumentWriter writer, T value) writeNative,
  Map<String, Object?> Function(T value) toDocument,
) {
  if (writer is CindelNativeObjectDocumentWriter) {
    final objectWriter = writer.beginObject(fieldIndex, fieldNames);
    writeNative(objectWriter, value);
    writer.endObject(objectWriter);
    return;
  }
  writer.writeObject(fieldIndex, toDocument(value));
}

/// Writes an embedded object list through the fastest object path supported by
/// [writer].
void cindelWriteNativeObjectList<T>(
  CindelNativeDocumentWriter writer,
  int fieldIndex,
  List<String> fieldNames,
  List<T?> value,
  void Function(CindelNativeDocumentWriter writer, T value) writeNative,
  Map<String, Object?> Function(T value) toDocument,
) {
  if (writer is CindelNativeObjectDocumentWriter) {
    final listWriter = writer.beginList(fieldIndex, value.length);
    final objectListWriter = listWriter is CindelNativeObjectDocumentWriter
        ? listWriter
        : null;
    try {
      for (var index = 0; index < value.length; index += 1) {
        final element = value[index];
        if (element == null) {
          listWriter.writeNull(index);
          continue;
        }
        if (objectListWriter == null) {
          listWriter.writeObject(index, toDocument(element));
        } else {
          final objectWriter = objectListWriter.beginObject(index, fieldNames);
          writeNative(objectWriter, element);
          objectListWriter.endObject(objectWriter);
        }
      }
    } finally {
      writer.endList(listWriter);
    }
    return;
  }
  writer.writeObjectList(
    fieldIndex,
    value
        .map((element) => element == null ? null : toDocument(element))
        .toList(growable: false),
  );
}

/// Reads an embedded object through the fastest object path supported by
/// [reader].
T? cindelReadNativeObject<T>(
  CindelNativeDocumentReader reader,
  int documentIndex,
  int fieldIndex,
  List<String> fieldNames,
  T Function(CindelNativeDocumentReader reader, int documentIndex) readNative,
  T Function(Map<String, Object?> document) fromDocument,
) {
  if (reader is CindelNativeObjectDocumentReader) {
    final objectReader = reader.readObjectReader(
      documentIndex,
      fieldIndex,
      fieldNames,
    );
    if (objectReader == null) {
      return null;
    }
    try {
      return readNative(objectReader, 0);
    } finally {
      objectReader.release();
    }
  }
  final document = reader.readObject(documentIndex, fieldIndex);
  return document == null ? null : fromDocument(document);
}

/// Reads an embedded object list through the fastest object path supported by
/// [reader].
List<T?>? cindelReadNativeObjectList<T>(
  CindelNativeDocumentReader reader,
  int documentIndex,
  int fieldIndex,
  List<String> fieldNames,
  T Function(CindelNativeDocumentReader reader, int documentIndex) readNative,
  T Function(Map<String, Object?> document) fromDocument,
) {
  if (reader is CindelNativeObjectDocumentReader) {
    final listReader = reader.readList(documentIndex, fieldIndex);
    if (listReader == null) {
      return null;
    }
    try {
      final objectListReader = listReader is CindelNativeObjectDocumentReader
          ? listReader
          : null;
      return [
        for (var index = 0; index < listReader.length; index += 1)
          (() {
            if (objectListReader == null) {
              final document = listReader.readObject(0, index);
              return document == null ? null : fromDocument(document);
            }
            final objectReader = objectListReader.readObjectReader(
              0,
              index,
              fieldNames,
            );
            if (objectReader == null) {
              return null;
            }
            try {
              return readNative(objectReader, 0);
            } finally {
              objectReader.release();
            }
          })(),
      ];
    } finally {
      listReader.release();
    }
  }
  final documents = reader.readObjectList(documentIndex, fieldIndex);
  return documents == null
      ? null
      : documents
            .map((document) => document == null ? null : fromDocument(document))
            .toList(growable: false);
}

/// Reader used by generated typed deserializers for native binary documents.
abstract interface class CindelNativeDocumentReader {
  /// Number of documents or list values exposed by this reader.
  int get length;

  /// Whether the document at [documentIndex] exists.
  bool isPresent(int documentIndex);

  /// Reads the native document id stored as the collection key.
  int readId(int documentIndex);

  /// Reads a nullable boolean value.
  bool? readBool(int documentIndex, int fieldIndex);

  /// Reads a nullable integer value.
  int? readInt(int documentIndex, int fieldIndex);

  /// Reads a nullable double value.
  double? readDouble(int documentIndex, int fieldIndex);

  /// Reads a nullable string value.
  String? readString(int documentIndex, int fieldIndex);

  /// Reads a nullable string list value.
  List<String>? readStringList(int documentIndex, int fieldIndex);

  /// Reads a nullable embedded object value.
  Map<String, Object?>? readObject(int documentIndex, int fieldIndex);

  /// Reads a nullable embedded object list value.
  List<Map<String, Object?>?>? readObjectList(
    int documentIndex,
    int fieldIndex,
  );

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
