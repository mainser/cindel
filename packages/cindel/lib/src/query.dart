import 'package:cindel_annotations/cindel_annotations.dart';

import 'database.dart';
import 'schema.dart';
import 'text.dart';

typedef _CindelDocumentReader = Future<List<CindelDocument>> Function();

/// Sort direction for Cindel query results.
enum CindelSortOrder {
  /// Ascending order.
  ascending,

  /// Descending order.
  descending,
}

/// Predicate used by Cindel query filters.
abstract interface class CindelFilterPredicate {
  /// Returns whether [document] matches this predicate.
  bool matches(CindelDocument document);
}

/// Factory helpers for query filter predicates.
final class CindelFilter {
  const CindelFilter._();

  /// Creates a predicate builder for [field].
  static CindelFilterField field(String field) {
    if (field.trim().isEmpty) {
      throw ArgumentError.value(field, 'field', 'Must not be empty.');
    }
    return CindelFilterField._(field);
  }

  /// Matches when all [predicates] match.
  static CindelFilterPredicate all(Iterable<CindelFilterPredicate> predicates) {
    return _CompositeFilterPredicate(
      predicates.toList(growable: false),
      _CompositeFilterMode.all,
    );
  }

  /// Matches when any predicate in [predicates] matches.
  static CindelFilterPredicate any(Iterable<CindelFilterPredicate> predicates) {
    return _CompositeFilterPredicate(
      predicates.toList(growable: false),
      _CompositeFilterMode.any,
    );
  }

  /// Matches when [predicate] does not match.
  static CindelFilterPredicate not(CindelFilterPredicate predicate) {
    return _NotFilterPredicate(predicate);
  }
}

/// Builds predicates for one Cindel document field.
final class CindelFilterField {
  const CindelFilterField._(this._field);

  final String _field;

  /// Matches documents where this field equals [value].
  CindelFilterPredicate equalTo(Object? value) {
    return _FieldFilterPredicate(
      field: _field,
      expected: value,
      operation: _FilterOperation.equalTo,
    );
  }

  /// Matches numeric fields greater than [value].
  CindelFilterPredicate greaterThan(num value) {
    return _FieldFilterPredicate(
      field: _field,
      expected: value,
      operation: _FilterOperation.greaterThan,
    );
  }

  /// Matches numeric fields greater than or equal to [value].
  CindelFilterPredicate greaterThanOrEqualTo(num value) {
    return _FieldFilterPredicate(
      field: _field,
      expected: value,
      operation: _FilterOperation.greaterThanOrEqualTo,
    );
  }

  /// Matches numeric fields less than [value].
  CindelFilterPredicate lessThan(num value) {
    return _FieldFilterPredicate(
      field: _field,
      expected: value,
      operation: _FilterOperation.lessThan,
    );
  }

  /// Matches numeric fields less than or equal to [value].
  CindelFilterPredicate lessThanOrEqualTo(num value) {
    return _FieldFilterPredicate(
      field: _field,
      expected: value,
      operation: _FilterOperation.lessThanOrEqualTo,
    );
  }

  /// Matches numeric fields inside an inclusive range.
  CindelFilterPredicate between(num? lower, num? upper) {
    if (lower == null && upper == null) {
      throw ArgumentError.value(null, 'lower/upper', 'Must provide a bound.');
    }
    return CindelFilter.all([
      if (lower != null) greaterThanOrEqualTo(lower),
      if (upper != null) lessThanOrEqualTo(upper),
    ]);
  }

  /// Matches string fields containing [value].
  CindelFilterPredicate contains(String value) {
    return _FieldFilterPredicate(
      field: _field,
      expected: value,
      operation: _FilterOperation.contains,
    );
  }

  /// Matches string fields starting with [value].
  CindelFilterPredicate startsWith(String value) {
    return _FieldFilterPredicate(
      field: _field,
      expected: value,
      operation: _FilterOperation.startsWith,
    );
  }

  /// Matches string fields ending with [value].
  CindelFilterPredicate endsWith(String value) {
    return _FieldFilterPredicate(
      field: _field,
      expected: value,
      operation: _FilterOperation.endsWith,
    );
  }
}

/// A typed query over a generated Cindel collection.
///
/// Query objects are usually created by generated `where()` helpers, for
/// example `database.todos.where().titleEqualTo('Ship').findAll()`.
final class CindelQuery<T> {
  const CindelQuery._({
    required CindelDatabase database,
    required CindelCollectionSchema<T> schema,
    required _CindelDocumentReader readDocuments,
    CindelFilterPredicate? filter,
    List<_CindelSortKey> sortKeys = const [],
    List<String> distinctFields = const [],
    int offset = 0,
    int? limit,
  }) : _database = database,
       _schema = schema,
       _readDocuments = readDocuments,
       _filter = filter,
       _sortKeys = sortKeys,
       _distinctFields = distinctFields,
       _offset = offset,
       _limit = limit;

  /// Creates a typed query that starts from every document in the collection.
  factory CindelQuery.all({
    required CindelDatabase database,
    required CindelCollectionSchema<T> schema,
  }) {
    return CindelQuery._(
      database: database,
      schema: schema,
      readDocuments: () => database.queryAll(schema.name),
    );
  }

  /// Creates a typed equality query for an indexed field.
  factory CindelQuery.equal({
    required CindelDatabase database,
    required CindelCollectionSchema<T> schema,
    required String field,
    required Object value,
  }) {
    return CindelQuery._(
      database: database,
      schema: schema,
      readDocuments: () => database.queryEqual(schema.name, field, value),
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
      database: database,
      schema: schema,
      readDocuments: () =>
          database.queryRange(schema.name, field, lower: lower, upper: upper),
    );
  }

  /// Creates a typed prefix query for an indexed string field.
  factory CindelQuery.stringStartsWith({
    required CindelDatabase database,
    required CindelCollectionSchema<T> schema,
    required String field,
    required String prefix,
  }) {
    final schemaField = _schemaField(schema, field);
    if (schemaField.indexType == CindelIndexType.hash) {
      throw StateError('Hash index `$field` only supports equality queries.');
    }
    final indexedPrefix = schemaField.indexCaseSensitive
        ? prefix
        : prefix.toLowerCase();
    return CindelQuery._(
      database: database,
      schema: schema,
      readDocuments: () async {
        final documents = await database.queryRange(
          schema.name,
          field,
          lower: indexedPrefix,
          upper: indexedPrefix.isEmpty
              ? null
              : _inclusivePrefixUpperBound(indexedPrefix),
        );
        return documents
            .where((document) {
              final value = document[field];
              if (value is! String) {
                return false;
              }
              if (schemaField.indexCaseSensitive) {
                return value.startsWith(prefix);
              }
              return value.toLowerCase().startsWith(indexedPrefix);
            })
            .toList(growable: false);
      },
    );
  }

  /// Creates a typed query for an exact word token in a word index.
  factory CindelQuery.wordsContain({
    required CindelDatabase database,
    required CindelCollectionSchema<T> schema,
    required String field,
    required String word,
  }) {
    final schemaField = _schemaField(schema, field);
    _checkWordsIndex(schemaField);
    final tokens = cindelSplitWords(
      word,
      caseSensitive: schemaField.indexCaseSensitive,
    );
    if (tokens.isEmpty) {
      return CindelQuery._(
        database: database,
        schema: schema,
        readDocuments: () async => <CindelDocument>[],
      );
    }
    return CindelQuery.equal(
      database: database,
      schema: schema,
      field: field,
      value: tokens.first,
    );
  }

  /// Creates a typed query for a word-token prefix in a word index.
  factory CindelQuery.wordsStartWith({
    required CindelDatabase database,
    required CindelCollectionSchema<T> schema,
    required String field,
    required String prefix,
  }) {
    final schemaField = _schemaField(schema, field);
    _checkWordsIndex(schemaField);
    final tokens = cindelSplitWords(
      prefix,
      caseSensitive: schemaField.indexCaseSensitive,
    );
    if (tokens.isEmpty) {
      return CindelQuery._(
        database: database,
        schema: schema,
        readDocuments: () async => <CindelDocument>[],
      );
    }
    final tokenPrefix = tokens.first;
    return CindelQuery.range(
      database: database,
      schema: schema,
      field: field,
      lower: tokenPrefix,
      upper: _inclusivePrefixUpperBound(tokenPrefix),
    );
  }

  final CindelDatabase _database;
  final CindelCollectionSchema<T> _schema;
  final _CindelDocumentReader _readDocuments;
  final CindelFilterPredicate? _filter;
  final List<_CindelSortKey> _sortKeys;
  final List<String> _distinctFields;
  final int _offset;
  final int? _limit;

  /// Returns a new query that filters the current query result by [predicate].
  CindelQuery<T> whereMatches(CindelFilterPredicate predicate) {
    final existing = _filter;
    return _copyWith(
      filter: existing == null
          ? predicate
          : CindelFilter.all([existing, predicate]),
    );
  }

  /// Sorts this query by [field].
  CindelQuery<T> sortBy(
    String field, {
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    _checkFieldName(field);
    return _copyWith(sortKeys: [_CindelSortKey(field, order)]);
  }

  /// Adds a secondary sort by [field].
  CindelQuery<T> thenBy(
    String field, {
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    _checkFieldName(field);
    return _copyWith(sortKeys: [..._sortKeys, _CindelSortKey(field, order)]);
  }

  /// Keeps only the first result for each distinct [field] value.
  CindelQuery<T> distinctBy(String field) {
    _checkFieldName(field);
    return distinctByFields([field]);
  }

  /// Keeps only the first result for each distinct tuple of [fields].
  CindelQuery<T> distinctByFields(Iterable<String> fields) {
    final fieldList = fields.toList(growable: false);
    if (fieldList.isEmpty) {
      throw ArgumentError.value(fields, 'fields', 'Must not be empty.');
    }
    for (final field in fieldList) {
      _checkFieldName(field);
    }
    return _copyWith(distinctFields: fieldList);
  }

  /// Skips [count] results after filtering, sorting, and distinct.
  CindelQuery<T> offset(int count) {
    if (count < 0) {
      throw ArgumentError.value(count, 'count', 'Must not be negative.');
    }
    return _copyWith(offset: count);
  }

  /// Limits this query to [count] results after offset.
  CindelQuery<T> limit(int count) {
    if (count < 0) {
      throw ArgumentError.value(count, 'count', 'Must not be negative.');
    }
    return _copyWith(limit: count);
  }

  /// Projects this query to one field.
  CindelPropertyQuery<T, R> property<R>(String field) {
    _checkFieldName(field);
    return CindelPropertyQuery<T, R>._(query: this, field: field);
  }

  /// Projects this query to multiple fields.
  CindelPropertiesQuery<T> properties(Iterable<String> fields) {
    final fieldList = fields.toList(growable: false);
    if (fieldList.isEmpty) {
      throw ArgumentError.value(fields, 'fields', 'Must not be empty.');
    }
    for (final field in fieldList) {
      _checkFieldName(field);
    }
    return CindelPropertiesQuery<T>._(query: this, fields: fieldList);
  }

  /// Returns every object matching this query.
  Future<List<T>> findAll() async {
    final documents = await _matchingDocuments();
    return documents.map(_schema.fromDocument).toList(growable: false);
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
    final documents = await _matchingDocuments();
    return documents.length;
  }

  /// Deletes the first object matching this query, if one exists.
  Future<bool> deleteFirst() async {
    final documents = await _matchingDocuments();
    if (documents.isEmpty) {
      return false;
    }
    await _database.deleteAll(_schema.name, [_idFromDocument(documents.first)]);
    return true;
  }

  /// Deletes every object matching this query atomically.
  Future<int> deleteAll() async {
    final documents = await _matchingDocuments();
    if (documents.isEmpty) {
      return 0;
    }
    final ids = documents.map(_idFromDocument).toList(growable: false);
    await _database.deleteAll(_schema.name, ids);
    return ids.length;
  }

  int _idFromDocument(CindelDocument document) {
    final value = document[_schema.idField];
    if (value is int) {
      return value;
    }
    throw StateError(
      'Generated schema `${_schema.dartName}` returned a non-int id field '
      '`${_schema.idField}`.',
    );
  }

  Future<List<CindelDocument>> _matchingDocuments() async {
    final documents = await _readDocuments();
    var matchingDocuments = documents;
    final filter = _filter;
    if (filter != null) {
      matchingDocuments = matchingDocuments.where(filter.matches).toList();
    }
    if (_sortKeys.isNotEmpty) {
      matchingDocuments = _sortDocuments(matchingDocuments, _sortKeys);
    }
    if (_distinctFields.isNotEmpty) {
      matchingDocuments = _distinctDocuments(
        matchingDocuments,
        _distinctFields,
      );
    }
    if (_offset > 0 || _limit != null) {
      matchingDocuments = _windowDocuments(matchingDocuments, _offset, _limit);
    }
    return matchingDocuments;
  }

  CindelQuery<T> _copyWith({
    CindelFilterPredicate? filter,
    List<_CindelSortKey>? sortKeys,
    List<String>? distinctFields,
    int? offset,
    int? limit,
  }) {
    return CindelQuery._(
      database: _database,
      schema: _schema,
      readDocuments: _readDocuments,
      filter: filter ?? _filter,
      sortKeys: sortKeys ?? _sortKeys,
      distinctFields: distinctFields ?? _distinctFields,
      offset: offset ?? _offset,
      limit: limit ?? _limit,
    );
  }
}

CindelFieldSchema _schemaField<T>(
  CindelCollectionSchema<T> schema,
  String field,
) {
  for (final schemaField in schema.fields) {
    if (schemaField.name == field) {
      return schemaField;
    }
  }
  throw StateError('Field `$field` is not part of `${schema.dartName}`.');
}

void _checkWordsIndex(CindelFieldSchema field) {
  if (field.indexType != CindelIndexType.words) {
    throw StateError('Field `${field.name}` is not a word index.');
  }
}

/// A projected query over a single field.
final class CindelPropertyQuery<T, R> {
  const CindelPropertyQuery._({
    required CindelQuery<T> query,
    required String field,
  }) : _query = query,
       _field = field;

  final CindelQuery<T> _query;
  final String _field;

  /// Returns every projected value.
  Future<List<R>> findAll() async {
    final documents = await _query._matchingDocuments();
    return [for (final document in documents) document[_field] as R];
  }

  /// Returns the first projected value, or `null`.
  Future<R?> findFirst() async {
    final values = await findAll();
    if (values.isEmpty) {
      return null;
    }
    return values.first;
  }
}

/// A projected query over multiple fields.
final class CindelPropertiesQuery<T> {
  const CindelPropertiesQuery._({
    required CindelQuery<T> query,
    required List<String> fields,
  }) : _query = query,
       _fields = fields;

  final CindelQuery<T> _query;
  final List<String> _fields;

  /// Returns every projected document.
  Future<List<CindelDocument>> findAll() async {
    final documents = await _query._matchingDocuments();
    return [
      for (final document in documents)
        {for (final field in _fields) field: document[field]},
    ];
  }

  /// Returns the first projected document, or `null`.
  Future<CindelDocument?> findFirst() async {
    final documents = await findAll();
    if (documents.isEmpty) {
      return null;
    }
    return documents.first;
  }
}

void _checkFieldName(String field) {
  if (field.trim().isEmpty) {
    throw ArgumentError.value(field, 'field', 'Must not be empty.');
  }
}

final class _CindelSortKey {
  const _CindelSortKey(this.field, this.order);

  final String field;
  final CindelSortOrder order;
}

final class _PositionedDocument {
  const _PositionedDocument(this.document, this.position);

  final CindelDocument document;
  final int position;
}

List<CindelDocument> _sortDocuments(
  List<CindelDocument> documents,
  List<_CindelSortKey> sortKeys,
) {
  final positioned = [
    for (var index = 0; index < documents.length; index += 1)
      _PositionedDocument(documents[index], index),
  ];
  positioned.sort((left, right) {
    for (final sortKey in sortKeys) {
      final comparison = _compareValues(
        left.document[sortKey.field],
        right.document[sortKey.field],
      );
      if (comparison == 0) {
        continue;
      }
      return sortKey.order == CindelSortOrder.ascending
          ? comparison
          : -comparison;
    }
    return left.position.compareTo(right.position);
  });
  return [for (final item in positioned) item.document];
}

int _compareValues(Object? left, Object? right) {
  if (left == null && right == null) {
    return 0;
  }
  if (left == null) {
    return -1;
  }
  if (right == null) {
    return 1;
  }
  if (left is num && right is num) {
    return left.compareTo(right);
  }
  if (left is String && right is String) {
    return left.compareTo(right);
  }
  if (left is bool && right is bool) {
    return left == right ? 0 : (left ? 1 : -1);
  }
  return left.toString().compareTo(right.toString());
}

List<CindelDocument> _distinctDocuments(
  List<CindelDocument> documents,
  List<String> fields,
) {
  final seen = <String>{};
  final distinct = <CindelDocument>[];
  for (final document in documents) {
    final key = _distinctKey(document, fields);
    if (seen.add(key)) {
      distinct.add(document);
    }
  }
  return distinct;
}

String _distinctKey(CindelDocument document, List<String> fields) {
  return fields
      .map((field) => '${document[field].runtimeType}:${document[field]}')
      .join('\u0001');
}

List<CindelDocument> _windowDocuments(
  List<CindelDocument> documents,
  int offset,
  int? limit,
) {
  if (offset >= documents.length) {
    return <CindelDocument>[];
  }
  final end = limit == null
      ? documents.length
      : (offset + limit).clamp(0, documents.length);
  return documents.sublist(offset, end);
}

enum _FilterOperation {
  equalTo,
  greaterThan,
  greaterThanOrEqualTo,
  lessThan,
  lessThanOrEqualTo,
  contains,
  startsWith,
  endsWith,
}

final class _FieldFilterPredicate implements CindelFilterPredicate {
  const _FieldFilterPredicate({
    required this.field,
    required this.expected,
    required this.operation,
  });

  final String field;
  final Object? expected;
  final _FilterOperation operation;

  @override
  bool matches(CindelDocument document) {
    if (!document.containsKey(field)) {
      return false;
    }
    final actual = document[field];
    return switch (operation) {
      _FilterOperation.equalTo => actual == expected,
      _FilterOperation.greaterThan => _compareNumbers(actual, expected) > 0,
      _FilterOperation.greaterThanOrEqualTo =>
        _compareNumbers(actual, expected) >= 0,
      _FilterOperation.lessThan => _compareNumbers(actual, expected) < 0,
      _FilterOperation.lessThanOrEqualTo =>
        _compareNumbers(actual, expected) <= 0,
      _FilterOperation.contains => _string(actual).contains(_string(expected)),
      _FilterOperation.startsWith => _string(
        actual,
      ).startsWith(_string(expected)),
      _FilterOperation.endsWith => _string(actual).endsWith(_string(expected)),
    };
  }

  int _compareNumbers(Object? actual, Object? expected) {
    if (actual is! num || expected is! num) {
      return -1;
    }
    return actual.compareTo(expected);
  }

  String _string(Object? value) {
    return value is String ? value : '';
  }
}

enum _CompositeFilterMode { all, any }

final class _CompositeFilterPredicate implements CindelFilterPredicate {
  const _CompositeFilterPredicate(this.predicates, this.mode);

  final List<CindelFilterPredicate> predicates;
  final _CompositeFilterMode mode;

  @override
  bool matches(CindelDocument document) {
    return switch (mode) {
      _CompositeFilterMode.all => predicates.every(
        (predicate) => predicate.matches(document),
      ),
      _CompositeFilterMode.any => predicates.any(
        (predicate) => predicate.matches(document),
      ),
    };
  }
}

final class _NotFilterPredicate implements CindelFilterPredicate {
  const _NotFilterPredicate(this.predicate);

  final CindelFilterPredicate predicate;

  @override
  bool matches(CindelDocument document) {
    return !predicate.matches(document);
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
