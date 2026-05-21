import 'database.dart';
import 'schema.dart';

typedef _CindelDocumentReader = Future<List<CindelDocument>> Function();

/// A typed query over a generated Cindel collection.
///
/// Query objects are usually created by generated `where()` helpers, for
/// example `database.todos.where().titleEqualTo('Ship').findAll()`.
final class CindelQuery<T> {
  const CindelQuery._({
    required _CindelDocumentReader readDocuments,
    required CindelFromDocument<T> fromDocument,
  }) : _readDocuments = readDocuments,
       _fromDocument = fromDocument;

  /// Creates a typed equality query for an indexed field.
  factory CindelQuery.equal({
    required CindelDatabase database,
    required CindelCollectionSchema<T> schema,
    required String field,
    required Object value,
  }) {
    return CindelQuery._(
      readDocuments: () => database.queryEqual(schema.name, field, value),
      fromDocument: schema.fromDocument,
    );
  }

  /// Creates a typed inclusive range query for an indexed field.
  factory CindelQuery.range({
    required CindelDatabase database,
    required CindelCollectionSchema<T> schema,
    required String field,
    Object? lower,
    Object? upper,
  }) {
    return CindelQuery._(
      readDocuments: () =>
          database.queryRange(schema.name, field, lower: lower, upper: upper),
      fromDocument: schema.fromDocument,
    );
  }

  /// Creates a typed prefix query for an indexed string field.
  factory CindelQuery.stringStartsWith({
    required CindelDatabase database,
    required CindelCollectionSchema<T> schema,
    required String field,
    required String prefix,
  }) {
    return CindelQuery._(
      readDocuments: () async {
        final documents = await database.queryRange(
          schema.name,
          field,
          lower: prefix,
          upper: prefix.isEmpty ? null : _inclusivePrefixUpperBound(prefix),
        );
        return documents
            .where((document) {
              final value = document[field];
              return value is String && value.startsWith(prefix);
            })
            .toList(growable: false);
      },
      fromDocument: schema.fromDocument,
    );
  }

  final _CindelDocumentReader _readDocuments;
  final CindelFromDocument<T> _fromDocument;

  /// Returns every object matching this query.
  Future<List<T>> findAll() async {
    final documents = await _readDocuments();
    return documents.map(_fromDocument).toList(growable: false);
  }

  /// Returns the first object matching this query, or `null`.
  Future<T?> findFirst() async {
    final objects = await findAll();
    if (objects.isEmpty) {
      return null;
    }
    return objects.first;
  }

  /// Returns the number of objects matching this query.
  Future<int> count() async {
    final documents = await _readDocuments();
    return documents.length;
  }
}

String _inclusivePrefixUpperBound(String prefix) {
  if (prefix.isEmpty) {
    return prefix;
  }
  final lastCodeUnit = prefix.codeUnitAt(prefix.length - 1);
  final nextCodeUnit = lastCodeUnit + 1;
  return '${prefix.substring(0, prefix.length - 1)}'
      '${String.fromCharCode(nextCodeUnit)}';
}
