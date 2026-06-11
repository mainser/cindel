import 'dart:async';

import '../cindel_error.dart';
import '../schema.dart';
import 'database.dart';

/// Applies an optional query modifier.
typedef CindelQueryOption<T> = CindelQuery<T> Function(CindelQuery<T> query);

/// Applies a repeated query modifier for [E] items.
typedef CindelQueryRepeatOption<T, E> =
    CindelQuery<T> Function(CindelQuery<T> query, E item);

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
    return CindelFilterField._([field]);
  }

  /// Creates a predicate builder for a nested object [path].
  static CindelFilterField path(Iterable<String> path) {
    return CindelFilterField._(path.toList(growable: false));
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
  const CindelFilterField._(this._path);

  final List<String> _path;

  /// Matches documents where this field equals [value].
  CindelFilterPredicate equalTo(Object? value) {
    return _FieldFilterPredicate(_path, _FilterOperation.equalTo, value);
  }

  /// Matches numeric fields greater than [value].
  CindelFilterPredicate greaterThan(num value) {
    return _FieldFilterPredicate(_path, _FilterOperation.greaterThan, value);
  }

  /// Matches numeric fields greater than or equal to [value].
  CindelFilterPredicate greaterThanOrEqualTo(num value) {
    return _FieldFilterPredicate(
      _path,
      _FilterOperation.greaterThanOrEqualTo,
      value,
    );
  }

  /// Matches numeric fields less than [value].
  CindelFilterPredicate lessThan(num value) {
    return _FieldFilterPredicate(_path, _FilterOperation.lessThan, value);
  }

  /// Matches numeric fields less than or equal to [value].
  CindelFilterPredicate lessThanOrEqualTo(num value) {
    return _FieldFilterPredicate(
      _path,
      _FilterOperation.lessThanOrEqualTo,
      value,
    );
  }

  /// Matches numeric fields inside an inclusive range.
  CindelFilterPredicate between(num? lower, num? upper) {
    return CindelFilter.all([
      if (lower != null) greaterThanOrEqualTo(lower),
      if (upper != null) lessThanOrEqualTo(upper),
    ]);
  }

  /// Matches string fields containing [value] or list fields containing value.
  CindelFilterPredicate contains(Object? value) {
    return _FieldFilterPredicate(_path, _FilterOperation.contains, value);
  }

  /// Matches list fields with no elements.
  CindelFilterPredicate isEmpty() {
    return _FieldFilterPredicate(_path, _FilterOperation.isEmpty, null);
  }

  /// Matches list fields with at least one element.
  CindelFilterPredicate isNotEmpty() {
    return _FieldFilterPredicate(_path, _FilterOperation.isNotEmpty, null);
  }

  /// Matches list fields with exactly [length] elements.
  CindelFilterPredicate lengthEqualTo(int length) {
    return _FieldFilterPredicate(_path, _FilterOperation.lengthEqualTo, length);
  }

  /// Matches list fields shorter than [length].
  CindelFilterPredicate lengthLessThan(int length, {bool include = false}) {
    return _FieldFilterPredicate(
      _path,
      include
          ? _FilterOperation.lengthLessThanOrEqualTo
          : _FilterOperation.lengthLessThan,
      length,
    );
  }

  /// Matches list fields longer than [length].
  CindelFilterPredicate lengthGreaterThan(int length, {bool include = false}) {
    return _FieldFilterPredicate(
      _path,
      include
          ? _FilterOperation.lengthGreaterThanOrEqualTo
          : _FilterOperation.lengthGreaterThan,
      length,
    );
  }

  /// Matches list fields whose length is inside the requested range.
  CindelFilterPredicate lengthBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return CindelFilter.all([
      lengthGreaterThan(lower, include: includeLower),
      lengthLessThan(upper, include: includeUpper),
    ]);
  }

  /// Matches string fields starting with [value].
  CindelFilterPredicate startsWith(String value) {
    return _FieldFilterPredicate(_path, _FilterOperation.startsWith, value);
  }

  /// Matches string fields ending with [value].
  CindelFilterPredicate endsWith(String value) {
    return _FieldFilterPredicate(_path, _FilterOperation.endsWith, value);
  }
}

/// A typed query over a generated Cindel collection on Web.
///
/// This preview implementation preserves the generated Dart query surface and
/// evaluates filters, sorting, distinct, and projection in Dart over documents
/// read from the Web database. Native Worker query-plan acceleration remains
/// available through the lower-level database methods used by generated/native
/// paths that can provide a supported wire plan.
final class CindelQuery<T> {
  CindelQuery._({
    required CindelDatabase database,
    required CindelCollectionSchema<T> schema,
    CindelFilterPredicate? filter,
    List<_SortKey> sortKeys = const [],
    List<String> distinctFields = const [],
    int offset = 0,
    int? limit,
  }) : _database = database,
       _schema = schema,
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
    return CindelQuery._(database: database, schema: schema);
  }

  /// Creates a typed equality query for an indexed field.
  factory CindelQuery.equal({
    required CindelDatabase database,
    required CindelCollectionSchema<T> schema,
    required String field,
    required Object value,
  }) {
    return CindelQuery.all(
      database: database,
      schema: schema,
    ).whereMatches(CindelFilter.field(field).equalTo(value));
  }

  /// Creates a typed equality query for a composite index.
  factory CindelQuery.compositeEqual({
    required CindelDatabase database,
    required CindelCollectionSchema<T> schema,
    required String index,
    required List<Object> values,
  }) {
    final fields = schema.compositeIndexes
        .firstWhere((candidate) => candidate.name == index)
        .fields;
    return CindelQuery.all(database: database, schema: schema).whereMatches(
      CindelFilter.all([
        for (var i = 0; i < fields.length; i += 1)
          CindelFilter.field(fields[i]).equalTo(values[i]),
      ]),
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
    return CindelQuery.all(database: database, schema: schema).whereMatches(
      CindelFilter.all([
        if (lower is num) CindelFilter.field(field).greaterThanOrEqualTo(lower),
        if (upper is num) CindelFilter.field(field).lessThanOrEqualTo(upper),
      ]),
    );
  }

  /// Creates a typed prefix query for an indexed string field.
  factory CindelQuery.stringStartsWith({
    required CindelDatabase database,
    required CindelCollectionSchema<T> schema,
    required String field,
    required String prefix,
  }) {
    return CindelQuery.all(
      database: database,
      schema: schema,
    ).whereMatches(CindelFilter.field(field).startsWith(prefix));
  }

  /// Creates a typed query for an exact word token in a word index.
  factory CindelQuery.wordsContain({
    required CindelDatabase database,
    required CindelCollectionSchema<T> schema,
    required String field,
    required String word,
  }) {
    return CindelQuery.all(
      database: database,
      schema: schema,
    ).whereMatches(CindelFilter.field(field).contains(word));
  }

  /// Creates a typed query for a word-token prefix in a word index.
  factory CindelQuery.wordsStartWith({
    required CindelDatabase database,
    required CindelCollectionSchema<T> schema,
    required String field,
    required String prefix,
  }) {
    return CindelQuery.stringStartsWith(
      database: database,
      schema: schema,
      field: field,
      prefix: prefix,
    );
  }

  final CindelDatabase _database;
  final CindelCollectionSchema<T> _schema;
  final CindelFilterPredicate? _filter;
  final List<_SortKey> _sortKeys;
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

  /// Applies [option] only when [enabled] is true.
  CindelQuery<T> optional(bool enabled, CindelQueryOption<T> option) {
    return enabled ? option(this) : this;
  }

  /// Applies [option] for each item and ORs the generated filters together.
  CindelQuery<T> anyOf<E>(
    Iterable<E> items,
    CindelQueryRepeatOption<T, E> option,
  ) {
    final itemList = items.toList(growable: false);
    if (itemList.isEmpty) {
      return whereMatches(CindelFilter.any(const []));
    }
    return whereMatches(
      CindelFilter.any([
        for (final item in itemList)
          option(
            CindelQuery.all(database: _database, schema: _schema),
            item,
          )._filter!,
      ]),
    );
  }

  /// Applies [option] for each item and ANDs generated filters together.
  CindelQuery<T> allOf<E>(
    Iterable<E> items,
    CindelQueryRepeatOption<T, E> option,
  ) {
    final filters = [
      for (final item in items)
        option(
          CindelQuery.all(database: _database, schema: _schema),
          item,
        )._filter!,
    ];
    return filters.isEmpty ? this : whereMatches(CindelFilter.all(filters));
  }

  /// Sorts this query by [field].
  CindelQuery<T> sortBy(
    String field, {
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return _copyWith(sortKeys: [_SortKey(field, order)]);
  }

  /// Adds a secondary sort by [field].
  CindelQuery<T> thenBy(
    String field, {
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return _copyWith(sortKeys: [..._sortKeys, _SortKey(field, order)]);
  }

  /// Keeps only the first result for each distinct [field] value.
  CindelQuery<T> distinctBy(String field) {
    return distinctByFields([field]);
  }

  /// Keeps only the first result for each distinct tuple of [fields].
  CindelQuery<T> distinctByFields(Iterable<String> fields) {
    return _copyWith(distinctFields: fields.toList(growable: false));
  }

  /// Skips [count] results.
  CindelQuery<T> offset(int count) {
    return _copyWith(offset: count);
  }

  /// Limits this query to [count] results.
  CindelQuery<T> limit(int count) {
    return _copyWith(limit: count);
  }

  /// Projects this query to one field.
  CindelPropertyQuery<T, R> property<R>(
    String field, {
    R Function(Object? value)? decode,
  }) {
    return CindelPropertyQuery<T, R>._(
      query: this,
      field: field,
      decode: decode,
    );
  }

  /// Projects this query to multiple fields.
  CindelPropertiesQuery<T> properties(Iterable<String> fields) {
    return CindelPropertiesQuery<T>._(
      query: this,
      fields: fields.toList(growable: false),
    );
  }

  /// Returns every object matching this query.
  Future<List<T>> findAll() async {
    final documents = await _matchingDocuments();
    return documents.map(_schema.fromDocument).toList(growable: false);
  }

  /// Watches are not part of the current Web preview.
  Stream<List<T>> watch({
    Duration pollInterval = defaultCindelWatchPollInterval,
    bool fireImmediately = true,
  }) {
    throw UnsupportedError('Cindel Web watchers are not available yet.');
  }

  /// Watches are not part of the current Web preview.
  Stream<void> watchLazy({
    Duration pollInterval = defaultCindelWatchPollInterval,
    bool fireImmediately = false,
  }) {
    throw UnsupportedError('Cindel Web watchers are not available yet.');
  }

  /// Returns the first object matching this query, or `null`.
  Future<T?> findFirst() async {
    final values = await findAll();
    return values.isEmpty ? null : values.first;
  }

  /// Returns the number of objects matching this query.
  Future<int> count() async {
    return (await _matchingDocuments()).length;
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
    final ids = documents.map(_idFromDocument).toList(growable: false);
    await _database.deleteAll(_schema.name, ids);
    return ids.length;
  }

  /// Updates are not part of the initial Web facade.
  ///
  /// Native query-plan updates exist in the Worker, but this high-level Web
  /// query object does not yet translate arbitrary Dart-side predicates into
  /// mutation plans.
  Future<bool> updateFirst(Map<String, Object?> changes) async {
    return (await updateAll(changes)) > 0;
  }

  /// Updates are not part of the initial Web facade.
  Future<int> updateAll(Map<String, Object?> changes) {
    throw UnsupportedError('Cindel Web query updates are not available yet.');
  }

  Future<List<CindelDocument>> _matchingDocuments() async {
    var documents = await _database.queryAll(_schema.name);
    final filter = _filter;
    if (filter != null) {
      documents = documents.where(filter.matches).toList(growable: false);
    }
    if (_sortKeys.isNotEmpty) {
      documents = documents.toList(growable: false)
        ..sort((left, right) => _compareDocuments(left, right, _sortKeys));
    }
    if (_distinctFields.isNotEmpty) {
      final seen = <String>{};
      documents = [
        for (final document in documents)
          if (seen.add(_distinctKey(document, _distinctFields))) document,
      ];
    }
    if (_offset > 0 || _limit != null) {
      final start = _offset.clamp(0, documents.length);
      final limit = _limit;
      final end = limit == null
          ? documents.length
          : (start + limit).clamp(start, documents.length);
      documents = documents.sublist(start, end);
    }
    return documents;
  }

  int _idFromDocument(CindelDocument document) {
    final value = document[_schema.idField];
    if (value is int) {
      return value;
    }
    throw CindelSchemaError(
      'Generated schema `${_schema.dartName}` returned a non-int id field.',
    );
  }

  CindelQuery<T> _copyWith({
    CindelFilterPredicate? filter,
    List<_SortKey>? sortKeys,
    List<String>? distinctFields,
    int? offset,
    int? limit,
  }) {
    return CindelQuery._(
      database: _database,
      schema: _schema,
      filter: filter ?? _filter,
      sortKeys: sortKeys ?? _sortKeys,
      distinctFields: distinctFields ?? _distinctFields,
      offset: offset ?? _offset,
      limit: limit ?? _limit,
    );
  }
}

/// A projected query over a single field.
final class CindelPropertyQuery<T, R> {
  const CindelPropertyQuery._({
    required CindelQuery<T> query,
    required String field,
    required R Function(Object? value)? decode,
  }) : _query = query,
       _field = field,
       _decode = decode;

  final CindelQuery<T> _query;
  final String _field;
  final R Function(Object? value)? _decode;

  /// Returns every projected value.
  Future<List<R>> findAll() async {
    final decode = _decode;
    return [
      for (final document in await _query._matchingDocuments())
        if (decode == null) document[_field] as R else decode(document[_field]),
    ];
  }

  /// Returns the first projected value, or `null`.
  Future<R?> findFirst() async {
    final values = await findAll();
    return values.isEmpty ? null : values.first;
  }

  /// Returns the number of non-null projected values.
  Future<int> count() async {
    return (await findAll()).where((value) => value != null).length;
  }

  /// Returns the smallest projected value.
  Future<R?> min() async => _minMax(await findAll(), true);

  /// Returns the largest projected value.
  Future<R?> max() async => _minMax(await findAll(), false);

  /// Returns the sum of numeric projected values.
  Future<num?> sum() async {
    num total = 0;
    var count = 0;
    for (final value in await findAll()) {
      if (value == null) continue;
      if (value is! num) throw CindelQueryError('Property sum requires num.');
      total += value;
      count += 1;
    }
    return count == 0 ? null : total;
  }

  /// Returns the average of numeric projected values.
  Future<double?> average() async {
    final values = await findAll();
    num total = 0;
    var count = 0;
    for (final value in values) {
      if (value == null) continue;
      if (value is! num) {
        throw CindelQueryError('Property average requires num.');
      }
      total += value;
      count += 1;
    }
    return count == 0 ? null : total / count;
  }

  R? _minMax(List<R> values, bool min) {
    Comparable<Object?>? best;
    for (final value in values) {
      if (value == null) continue;
      if (value is! Comparable<Object?>) {
        throw CindelQueryError(
          'Property aggregate requires comparable values.',
        );
      }
      if (best == null ||
          (min ? value.compareTo(best) < 0 : value.compareTo(best) > 0)) {
        best = value;
      }
    }
    return best as R?;
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
    return [
      for (final document in await _query._matchingDocuments())
        {for (final field in _fields) field: document[field]},
    ];
  }

  /// Returns the first projected document, or `null`.
  Future<CindelDocument?> findFirst() async {
    final documents = await findAll();
    return documents.isEmpty ? null : documents.first;
  }
}

enum _FilterOperation {
  equalTo,
  greaterThan,
  greaterThanOrEqualTo,
  lessThan,
  lessThanOrEqualTo,
  contains,
  isEmpty,
  isNotEmpty,
  lengthEqualTo,
  lengthGreaterThan,
  lengthGreaterThanOrEqualTo,
  lengthLessThan,
  lengthLessThanOrEqualTo,
  startsWith,
  endsWith,
}

enum _CompositeFilterMode { all, any }

final class _FieldFilterPredicate implements CindelFilterPredicate {
  const _FieldFilterPredicate(this.path, this.operation, this.expected);

  final List<String> path;
  final _FilterOperation operation;
  final Object? expected;

  @override
  bool matches(CindelDocument document) {
    final actual = document[path.first];
    return switch (operation) {
      _FilterOperation.equalTo => actual == expected,
      _FilterOperation.greaterThan => _compare(actual, expected) > 0,
      _FilterOperation.greaterThanOrEqualTo => _compare(actual, expected) >= 0,
      _FilterOperation.lessThan => _compare(actual, expected) < 0,
      _FilterOperation.lessThanOrEqualTo => _compare(actual, expected) <= 0,
      _FilterOperation.contains =>
        actual is String
            ? actual.contains(expected.toString())
            : actual is Iterable && actual.contains(expected),
      _FilterOperation.isEmpty => actual is Iterable && actual.isEmpty,
      _FilterOperation.isNotEmpty => actual is Iterable && actual.isNotEmpty,
      _FilterOperation.lengthEqualTo => _length(actual) == expected,
      _FilterOperation.lengthGreaterThan => _length(actual) > (expected as int),
      _FilterOperation.lengthGreaterThanOrEqualTo =>
        _length(actual) >= (expected as int),
      _FilterOperation.lengthLessThan => _length(actual) < (expected as int),
      _FilterOperation.lengthLessThanOrEqualTo =>
        _length(actual) <= (expected as int),
      _FilterOperation.startsWith =>
        actual is String && actual.startsWith(expected.toString()),
      _FilterOperation.endsWith =>
        actual is String && actual.endsWith(expected.toString()),
    };
  }
}

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
  bool matches(CindelDocument document) => !predicate.matches(document);
}

final class _SortKey {
  const _SortKey(this.field, this.order);

  final String field;
  final CindelSortOrder order;
}

int _compare(Object? left, Object? right) {
  if (left is num && right is num) {
    return left.compareTo(right);
  }
  if (left is Comparable<Object?>) {
    return left.compareTo(right);
  }
  return 0;
}

int _length(Object? value) {
  if (value is Iterable) return value.length;
  if (value is String) return value.length;
  return 0;
}

int _compareDocuments(
  CindelDocument left,
  CindelDocument right,
  List<_SortKey> keys,
) {
  for (final key in keys) {
    final comparison = _compare(left[key.field], right[key.field]);
    if (comparison != 0) {
      return key.order == CindelSortOrder.ascending ? comparison : -comparison;
    }
  }
  return 0;
}

String _distinctKey(CindelDocument document, Iterable<String> fields) {
  return fields.map((field) => '${document[field]}').join('\u0000');
}
