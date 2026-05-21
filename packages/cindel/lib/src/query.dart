import 'database.dart';
import 'schema.dart';

typedef _CindelDocumentReader = Future<List<CindelDocument>> Function();

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
  }) : _database = database,
       _schema = schema,
       _readDocuments = readDocuments,
       _filter = filter;

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
    return CindelQuery._(
      database: database,
      schema: schema,
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
    );
  }

  final CindelDatabase _database;
  final CindelCollectionSchema<T> _schema;
  final _CindelDocumentReader _readDocuments;
  final CindelFilterPredicate? _filter;

  /// Returns a new query that filters the current query result by [predicate].
  CindelQuery<T> whereMatches(CindelFilterPredicate predicate) {
    final existing = _filter;
    return CindelQuery._(
      database: _database,
      schema: _schema,
      readDocuments: _readDocuments,
      filter: existing == null
          ? predicate
          : CindelFilter.all([existing, predicate]),
    );
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
    final filter = _filter;
    if (filter == null) {
      return documents;
    }
    return documents.where(filter.matches).toList(growable: false);
  }
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
