import 'dart:async';
import 'dart:typed_data';

import 'package:cindel_annotations/cindel_annotations.dart';

import 'database.dart';
import 'native/wire.dart';
import 'schema.dart';
import 'text.dart';

typedef _CindelDocumentReader = Future<List<CindelDocument>> Function();
typedef _CindelDocumentFilter = bool Function(CindelDocument document);
typedef _CindelIdReader = Future<List<int>> Function();

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
  CindelQuery._({
    required CindelDatabase database,
    required CindelCollectionSchema<T> schema,
    required _CindelDocumentReader readDocuments,
    _CindelDocumentFilter? sourceFilter,
    _CindelIdReader? readIds,
    CindelNativeQuerySource? nativeSource,
    CindelFilterPredicate? filter,
    List<_CindelSortKey> sortKeys = const [],
    List<String> distinctFields = const [],
    int offset = 0,
    int? limit,
  }) : _database = database,
       _schema = schema,
       _readDocuments = readDocuments,
       _sourceFilter = sourceFilter,
       _readIds = readIds,
       _nativeSource = nativeSource,
       _filter = filter,
       _nativeFilter = _nativeFilterBytes(filter),
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
      readIds: () => database.documentIds(schema.name),
      nativeSource: const CindelNativeAllQuerySource(),
    );
  }

  /// Creates a typed equality query for an indexed field.
  factory CindelQuery.equal({
    required CindelDatabase database,
    required CindelCollectionSchema<T> schema,
    required String field,
    required Object value,
  }) {
    final schemaField = _schemaField(schema, field);
    return CindelQuery._(
      database: database,
      schema: schema,
      readDocuments: () => database.queryEqual(schema.name, field, value),
      readIds: schemaField.indexType == CindelIndexType.hash
          ? null
          : () => database.queryEqualIds(schema.name, field, value),
      nativeSource: CindelNativeIndexEqualQuerySource(
        indexName: field,
        value: value,
        dedupe: schemaField.indexType == CindelIndexType.words,
      ),
    );
  }

  /// Creates a typed equality query for a composite index.
  factory CindelQuery.compositeEqual({
    required CindelDatabase database,
    required CindelCollectionSchema<T> schema,
    required String index,
    required List<Object> values,
  }) {
    return CindelQuery._(
      database: database,
      schema: schema,
      readDocuments: () =>
          database.queryCompositeEqual(schema.name, index, values),
      readIds: () async =>
          database.queryCompositeEqualIds(schema.name, index, values),
      nativeSource: CindelNativeCompositeEqualQuerySource(
        indexName: index,
        values: values,
      ),
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
      readIds: () => database.queryRangeIds(
        schema.name,
        field,
        lower: lower,
        upper: upper,
      ),
      nativeSource: CindelNativeIndexRangeQuerySource(
        indexName: field,
        lower: lower,
        upper: upper,
        dedupe: _schemaField(schema, field).indexType == CindelIndexType.words,
      ),
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
    bool sourceFilter(CindelDocument document) {
      final value = document[field];
      if (value is! String) {
        return false;
      }
      if (schemaField.indexCaseSensitive) {
        return value.startsWith(prefix);
      }
      return value.toLowerCase().startsWith(indexedPrefix);
    }

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
        return documents.where(sourceFilter).toList(growable: false);
      },
      sourceFilter: sourceFilter,
      readIds: () => database.queryRangeIds(
        schema.name,
        field,
        lower: indexedPrefix,
        upper: indexedPrefix.isEmpty
            ? null
            : _inclusivePrefixUpperBound(indexedPrefix),
      ),
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
        readIds: () async => <int>[],
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
        readIds: () async => <int>[],
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
  final _CindelDocumentFilter? _sourceFilter;
  final _CindelIdReader? _readIds;
  final CindelNativeQuerySource? _nativeSource;
  final CindelFilterPredicate? _filter;
  final Uint8List? _nativeFilter;
  final List<_CindelSortKey> _sortKeys;
  final List<String> _distinctFields;
  final int _offset;
  final int? _limit;

  /// Returns a new query that filters the current query result by [predicate].
  CindelQuery<T> whereMatches(CindelFilterPredicate predicate) {
    final indexedQuery = _indexedEqualityQuery(predicate);
    if (indexedQuery != null) {
      return indexedQuery;
    }

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
  CindelPropertyQuery<T, R> property<R>(
    String field, {
    R Function(Object? value)? decode,
  }) {
    _checkFieldName(field);
    return CindelPropertyQuery<T, R>._(
      query: this,
      field: field,
      decode: decode,
    );
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
    final nativeObjects = await _matchingNativeObjects();
    if (nativeObjects != null) {
      return nativeObjects;
    }
    final documents = await _matchingDocuments();
    return documents.map(_schema.fromDocument).toList(growable: false);
  }

  /// Watches this query and emits typed results when the visible result changes.
  Stream<List<T>> watch({
    Duration pollInterval = defaultCindelWatchPollInterval,
    bool fireImmediately = true,
  }) {
    return _watchMatchingDocuments(
      pollInterval: pollInterval,
      fireImmediately: fireImmediately,
    ).map(
      (documents) =>
          documents.map(_schema.fromDocument).toList(growable: false),
    );
  }

  /// Watches this query and emits without returning the matching objects.
  Stream<void> watchLazy({
    Duration pollInterval = defaultCindelWatchPollInterval,
    bool fireImmediately = false,
  }) {
    return _watchMatchingIds(
      pollInterval: pollInterval,
      fireImmediately: fireImmediately,
    ).map((_) {});
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
    final nativePlan = _nativePlan();
    if (nativePlan != null) {
      return _database.queryNativePlanCount(_schema.name, nativePlan);
    }
    final documents = await _matchingDocuments();
    return documents.length;
  }

  /// Deletes the first object matching this query, if one exists.
  Future<bool> deleteFirst() async {
    final nativePlan = _nativePlan(limitOverride: 1);
    if (nativePlan != null) {
      final ids = await _database.deleteNativePlan(_schema.name, nativePlan);
      return ids.isNotEmpty;
    }
    final documents = await _matchingDocuments();
    if (documents.isEmpty) {
      return false;
    }
    await _database.deleteAll(_schema.name, [_idFromDocument(documents.first)]);
    return true;
  }

  /// Deletes every object matching this query atomically.
  Future<int> deleteAll() async {
    final nativePlan = _nativePlan();
    if (nativePlan != null) {
      final ids = await _database.deleteNativePlan(_schema.name, nativePlan);
      return ids.length;
    }
    final documents = await _matchingDocuments();
    if (documents.isEmpty) {
      return 0;
    }
    final ids = documents.map(_idFromDocument).toList(growable: false);
    await _database.deleteAll(_schema.name, ids);
    return ids.length;
  }

  /// Updates the first object matching this query using native property writes.
  Future<bool> updateFirst(Map<String, Object?> changes) async {
    final count = await _updateNative(changes, limitOverride: 1);
    return count > 0;
  }

  /// Updates every object matching this query using native property writes.
  Future<int> updateAll(Map<String, Object?> changes) async {
    return _updateNative(changes);
  }

  Future<int> _updateNative(
    Map<String, Object?> changes, {
    int? limitOverride,
  }) async {
    if (changes.isEmpty) {
      return 0;
    }
    final nativePlan = _nativePlan(limitOverride: limitOverride);
    if (nativePlan == null) {
      throw UnsupportedError(
        'Native query updates require the MDBX binary query planner.',
      );
    }
    final updates = <String, WireValue>{};
    for (final entry in changes.entries) {
      final field = _schemaField(_schema, entry.key);
      if (field.isId) {
        throw ArgumentError.value(entry.key, 'changes', 'Cannot update id.');
      }
      final value = entry.value;
      if (!_isNativeFilterValue(value)) {
        throw ArgumentError.value(
          value,
          entry.key,
          'Native query updates support null, bool, int, double, String, List, and Map values.',
        );
      }
      updates[field.name] = _nativeFilterValue(value);
    }
    return _database.updateNativePlan(_schema.name, nativePlan, updates);
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
    final nativePlan = _nativePlan();
    if (nativePlan != null) {
      return _database.queryNativePlanDocuments(_schema.name, nativePlan);
    }

    var matchingDocuments = await _readFilteredDocuments();
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

  Future<List<int>> _matchingIds() async {
    if (_sortKeys.isEmpty &&
        _distinctFields.isEmpty &&
        _offset == 0 &&
        _limit == null) {
      final nativeFilter = _nativeFilter;
      final readIds = _readIds;
      if (nativeFilter != null && readIds != null && _canUseNativeFilter) {
        final candidateIds = await readIds();
        return _database.queryNativeFilterIds(
          _schema.name,
          candidateIds,
          nativeFilter,
        );
      }

      final filter = _filter;
      if (filter == null && _sourceFilter == null && readIds != null) {
        return readIds();
      }
    }

    final nativePlan = _nativePlan();
    if (nativePlan != null && _nativeFilter == null) {
      return _database.queryNativePlanIds(_schema.name, nativePlan);
    }

    final documents = await _matchingDocuments();
    return documents.map(_idFromDocument).toList(growable: false);
  }

  Future<List<T>>? _matchingNativeObjects() {
    final nativePlan = _nativePlan();
    final fieldTypes = _nativeFieldTypes();
    final readNativeDocument = _schema.readNativeDocument;
    if (nativePlan == null ||
        readNativeDocument == null ||
        fieldTypes == null) {
      return null;
    }
    return () async {
      final objects = await _database.queryNativePlanObjects(
        _schema.name,
        nativePlan,
        fieldTypes,
        readNativeDocument,
      );
      return objects;
    }();
  }

  Uint8List? _nativeFieldTypes() {
    final fields = _schema.fields.toList(growable: false)
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
        _ => null,
      };
      if (value == null) {
        return null;
      }
      bytes[i] = value;
    }
    return bytes;
  }

  CindelNativeQueryPlan? _nativePlan({int? limitOverride}) {
    final nativeSource = _nativeSource;
    final nativeFilter = _nativeFilter;
    if (!_canUseNativePlanner ||
        nativeSource == null ||
        (_filter != null && nativeFilter == null)) {
      return null;
    }
    final effectiveLimit = switch ((_limit, limitOverride)) {
      (null, null) => null,
      (final current?, null) => current,
      (null, final override?) => override,
      (final current?, final override?) =>
        current < override ? current : override,
    };
    return CindelNativeQueryPlan(
      source: nativeSource,
      filter: nativeFilter,
      sorts: [
        for (final sortKey in _sortKeys)
          CindelNativeQuerySort(
            field: sortKey.field,
            descending: sortKey.order == CindelSortOrder.descending,
          ),
      ],
      distinctFields: _distinctFields,
      offset: _offset,
      limit: effectiveLimit,
    );
  }

  Future<List<CindelDocument>> _readFilteredDocuments() async {
    final nativeFilter = _nativeFilter;
    final readIds = _readIds;
    if (nativeFilter != null && readIds != null && _canUseNativeFilter) {
      final candidateIds = await readIds();
      final matchingIds = await _database.queryNativeFilterIds(
        _schema.name,
        candidateIds,
        nativeFilter,
      );
      final documents = await _database.documentsByIds(
        _schema.name,
        matchingIds,
      );
      final sourceFilter = _sourceFilter;
      if (sourceFilter == null) {
        return documents;
      }
      return documents.where(sourceFilter).toList();
    }

    final documents = await _readDocuments();
    final filter = _filter;
    if (filter == null) {
      return documents;
    }
    return documents.where(filter.matches).toList();
  }

  bool get _canUseNativeFilter {
    return _database.backend == CindelStorageBackend.mdbx &&
        _schema.toBinaryDocument != null &&
        _schema.fromBinaryDocument != null;
  }

  bool get _canUseNativePlanner {
    return _canUseNativeFilter && _sourceFilter == null;
  }

  bool get _canUseNativeProjection => _canUseNativePlanner;

  Stream<List<CindelDocument>> _watchMatchingDocuments({
    required Duration pollInterval,
    required bool fireImmediately,
  }) {
    late final StreamController<List<CindelDocument>> controller;
    StreamSubscription<CindelChangeSet>? subscription;
    var hasSnapshot = false;
    Set<int> previousIds = const {};
    var isReading = false;
    var needsRead = false;

    bool canSkipLocalChange(CindelChangeSet change) {
      if (change.isExternal) {
        return false;
      }
      final changedIds = change.documentIds;
      if (changedIds == null) {
        return false;
      }
      if (changedIds.any(previousIds.contains)) {
        return false;
      }
      if (change.hasUnknownDocuments) {
        return false;
      }
      for (final document in change.documents.values) {
        if (_matchesBeforeWindow(document)) {
          return false;
        }
      }
      return true;
    }

    Future<void> readAndMaybeEmit(CindelChangeSet change) async {
      if (hasSnapshot && canSkipLocalChange(change)) {
        return;
      }
      if (isReading) {
        needsRead = true;
        return;
      }
      isReading = true;
      try {
        do {
          needsRead = false;
          final documents = await _matchingDocuments();
          if (controller.isClosed) {
            return;
          }
          final documentIds = documents.map(_idFromDocument).toSet();
          if (!hasSnapshot) {
            hasSnapshot = true;
            previousIds = documentIds;
            if (fireImmediately) {
              controller.add(documents);
            }
            continue;
          }

          previousIds = documentIds;
          controller.add(documents);
        } while (needsRead && !controller.isClosed);
      } catch (error, stackTrace) {
        if (!controller.isClosed) {
          controller.addError(error, stackTrace);
        }
      } finally {
        isReading = false;
      }
    }

    controller = StreamController<List<CindelDocument>>(
      onListen: () {
        subscription = _database
            .watchCollectionChanges(
              _schema.name,
              pollInterval: pollInterval,
              fireImmediately: true,
            )
            .listen(
              (change) => unawaited(readAndMaybeEmit(change)),
              onError: controller.addError,
              onDone: controller.close,
            );
      },
      onCancel: () async {
        await subscription?.cancel();
      },
    );

    return controller.stream;
  }

  Stream<List<int>> _watchMatchingIds({
    required Duration pollInterval,
    required bool fireImmediately,
  }) {
    late final StreamController<List<int>> controller;
    StreamSubscription<CindelChangeSet>? subscription;
    var hasSnapshot = false;
    Set<int> previousIdSet = const {};
    var isReading = false;
    var needsRead = false;

    bool canSkipLocalChange(CindelChangeSet change) {
      if (change.isExternal) {
        return false;
      }
      final changedIds = change.documentIds;
      if (changedIds == null) {
        return false;
      }
      if (changedIds.any(previousIdSet.contains)) {
        return false;
      }
      if (change.hasUnknownDocuments) {
        return false;
      }
      for (final document in change.documents.values) {
        if (_matchesBeforeWindow(document)) {
          return false;
        }
      }
      return true;
    }

    Future<void> readAndMaybeEmit(CindelChangeSet change) async {
      if (hasSnapshot && canSkipLocalChange(change)) {
        return;
      }
      if (isReading) {
        needsRead = true;
        return;
      }
      isReading = true;
      try {
        do {
          needsRead = false;
          final ids = await _matchingIds();
          if (controller.isClosed) {
            return;
          }
          final idSet = ids.toSet();
          if (!hasSnapshot) {
            hasSnapshot = true;
            previousIdSet = idSet;
            if (fireImmediately) {
              controller.add(ids);
            }
            continue;
          }

          previousIdSet = idSet;
          controller.add(ids);
        } while (needsRead && !controller.isClosed);
      } catch (error, stackTrace) {
        if (!controller.isClosed) {
          controller.addError(error, stackTrace);
        }
      } finally {
        isReading = false;
      }
    }

    controller = StreamController<List<int>>(
      onListen: () {
        subscription = _database
            .watchCollectionChanges(
              _schema.name,
              pollInterval: pollInterval,
              fireImmediately: true,
            )
            .listen(
              (change) => unawaited(readAndMaybeEmit(change)),
              onError: controller.addError,
              onDone: controller.close,
            );
      },
      onCancel: () async {
        await subscription?.cancel();
      },
    );

    return controller.stream;
  }

  bool _matchesBeforeWindow(CindelDocument document) {
    final sourceFilter = _sourceFilter;
    if (sourceFilter != null && !sourceFilter(document)) {
      return false;
    }
    final filter = _filter;
    if (filter != null && !filter.matches(document)) {
      return false;
    }
    return true;
  }

  CindelQuery<T>? _indexedEqualityQuery(CindelFilterPredicate predicate) {
    if (_filter != null ||
        _sourceFilter != null ||
        _nativeSource is! CindelNativeAllQuerySource ||
        predicate is! _FieldFilterPredicate ||
        predicate.operation != _FilterOperation.equalTo ||
        predicate.expected == null) {
      return null;
    }

    final field = _indexedEqualityField(predicate);
    if (field == null) {
      return null;
    }
    final value = predicate.expected!;
    return CindelQuery._(
      database: _database,
      schema: _schema,
      readDocuments: () =>
          _database.queryEqual(_schema.name, field.name, value),
      readIds: field.indexType == CindelIndexType.hash
          ? null
          : () => _database.queryEqualIds(_schema.name, field.name, value),
      nativeSource: CindelNativeIndexEqualQuerySource(
        indexName: field.name,
        value: value,
        dedupe: false,
      ),
      sortKeys: _sortKeys,
      distinctFields: _distinctFields,
      offset: _offset,
      limit: _limit,
    );
  }

  CindelFieldSchema? _indexedEqualityField(_FieldFilterPredicate predicate) {
    for (final field in _schema.fields) {
      if (field.name != predicate.field || !field.isIndexed) {
        continue;
      }
      if (field.indexType == CindelIndexType.multiEntry ||
          field.indexType == CindelIndexType.words) {
        return null;
      }
      if (!field.indexCaseSensitive &&
          field.binaryType == 'string' &&
          predicate.expected is String) {
        return null;
      }
      return field;
    }
    return null;
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
      sourceFilter: _sourceFilter,
      readIds: _readIds,
      nativeSource: _nativeSource,
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

Uint8List? _nativeFilterBytes(CindelFilterPredicate? predicate) {
  if (predicate == null) {
    return null;
  }
  final filter = _nativeFilterWire(predicate);
  if (filter == null) {
    return null;
  }
  return encodeFilter(filter);
}

WireFilter? _nativeFilterWire(CindelFilterPredicate predicate) {
  if (predicate is _FieldFilterPredicate) {
    if (!_isNativeFilterValue(predicate.expected)) {
      return null;
    }
    final value = _nativeFilterValue(predicate.expected);
    return WireFilter.field(
      field: predicate.field,
      operation: _nativeFilterOperation(predicate.operation, value),
      value: value,
    );
  }

  if (predicate is _CompositeFilterPredicate) {
    final predicates = <WireFilter>[];
    for (final child in predicate.predicates) {
      final encoded = _nativeFilterWire(child);
      if (encoded == null) {
        return null;
      }
      predicates.add(encoded);
    }
    return switch (predicate.mode) {
      _CompositeFilterMode.all => WireFilter.all(predicates),
      _CompositeFilterMode.any => WireFilter.any(predicates),
    };
  }

  if (predicate is _NotFilterPredicate) {
    final encoded = _nativeFilterWire(predicate.predicate);
    if (encoded == null) {
      return null;
    }
    return WireFilter.not(encoded);
  }

  return null;
}

WireFilterOperation _nativeFilterOperation(
  _FilterOperation operation,
  WireValue value,
) {
  if (operation == _FilterOperation.equalTo && value is WireNullValue) {
    return WireFilterOperation.isNull;
  }
  return switch (operation) {
    _FilterOperation.equalTo => WireFilterOperation.equal,
    _FilterOperation.greaterThan => WireFilterOperation.greaterThan,
    _FilterOperation.greaterThanOrEqualTo =>
      WireFilterOperation.greaterThanOrEqual,
    _FilterOperation.lessThan => WireFilterOperation.lessThan,
    _FilterOperation.lessThanOrEqualTo => WireFilterOperation.lessThanOrEqual,
    _FilterOperation.contains => WireFilterOperation.contains,
    _FilterOperation.startsWith => WireFilterOperation.startsWith,
    _FilterOperation.endsWith => WireFilterOperation.endsWith,
  };
}

WireValue _nativeFilterValue(Object? value) {
  return switch (value) {
    null => const WireValue.nullValue(),
    bool() => WireValue.bool(value),
    int() => WireValue.int(value),
    double() => WireValue.double(value),
    String() => WireValue.string(value),
    List() => WireValue.list([
      for (final item in value) _nativeFilterValue(item),
    ]),
    Map() => WireValue.object(_nativeFilterObjectEntries(value)),
    _ => throw ArgumentError.value(value, 'value', 'Unsupported filter value.'),
  };
}

List<WireObjectEntry> _nativeFilterObjectEntries(Map<Object?, Object?> value) {
  final entries = <WireObjectEntry>[
    for (final MapEntry(:key, :value) in value.entries)
      WireObjectEntry(key as String, _nativeFilterValue(value)),
  ];
  entries.sort((left, right) => left.name.compareTo(right.name));
  return entries;
}

bool _isNativeFilterValue(Object? value) {
  return switch (value) {
    null || String() || bool() || int() => true,
    double() => value.isFinite,
    List() => value.every(_isNativeFilterValue),
    Map() =>
      value.keys.every((key) => key is String) &&
          value.values.every(_isNativeFilterValue),
    _ => false,
  };
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
    final nativePlan = _query._nativePlan();
    if (nativePlan != null && _query._canUseNativeProjection) {
      final values = await _query._database.queryNativePlanProjection(
        _query._schema.name,
        nativePlan,
        _field,
      );
      final decode = _decode;
      return [
        for (final value in values)
          if (decode == null) value as R else decode(value),
      ];
    }

    final documents = await _query._matchingDocuments();
    final decode = _decode;
    return [
      for (final document in documents)
        if (decode == null) document[_field] as R else decode(document[_field]),
    ];
  }

  /// Returns the first projected value, or `null`.
  Future<R?> findFirst() async {
    final values = await findAll();
    if (values.isEmpty) {
      return null;
    }
    return values.first;
  }

  /// Returns the number of non-null projected values.
  Future<int> count() async {
    final native = await _tryNativeAggregate('count');
    if (native != null) {
      final value = native.value;
      if (value is int) {
        return value;
      }
      if (value is num) {
        return value.toInt();
      }
      throw StateError('Native Cindel returned a non-numeric count.');
    }

    var count = 0;
    for (final value in await findAll()) {
      if (value != null) {
        count += 1;
      }
    }
    return count;
  }

  /// Returns the smallest projected value, ignoring null values.
  Future<R?> min() async {
    final native = await _tryNativeAggregate('min');
    if (native != null) {
      return _decodeAggregateValue(native.value);
    }
    return _minMax(await findAll(), _AggregateOrder.min);
  }

  /// Returns the largest projected value, ignoring null values.
  Future<R?> max() async {
    final native = await _tryNativeAggregate('max');
    if (native != null) {
      return _decodeAggregateValue(native.value);
    }
    return _minMax(await findAll(), _AggregateOrder.max);
  }

  /// Returns the sum of numeric projected values, ignoring null values.
  Future<num?> sum() async {
    final native = await _tryNativeAggregate('sum');
    if (native != null) {
      final value = native.value;
      if (value == null) {
        return null;
      }
      if (value is num) {
        return value;
      }
      throw StateError('Native Cindel returned a non-numeric sum.');
    }
    return _sum(await findAll());
  }

  /// Returns the average of numeric projected values, ignoring null values.
  Future<double?> average() async {
    final native = await _tryNativeAggregate('average');
    if (native != null) {
      final value = native.value;
      if (value == null) {
        return null;
      }
      if (value is num) {
        return value.toDouble();
      }
      throw StateError('Native Cindel returned a non-numeric average.');
    }
    return _average(await findAll());
  }

  Future<({Object? value})?> _tryNativeAggregate(String operation) async {
    final nativePlan = _query._nativePlan();
    if (nativePlan == null || !_query._canUseNativeProjection) {
      return null;
    }
    final value = await _query._database.queryNativePlanAggregate(
      _query._schema.name,
      nativePlan,
      _field,
      operation,
    );
    return (value: value);
  }

  R? _decodeAggregateValue(Object? value) {
    if (value == null) {
      return null;
    }
    final decode = _decode;
    return decode == null ? value as R : decode(value);
  }

  R? _minMax(List<R> values, _AggregateOrder order) {
    Object? best;
    for (final value in values) {
      if (value == null) {
        continue;
      }
      if (value is! Comparable<dynamic>) {
        throw StateError(
          'Property aggregate `${order.name}` requires comparable values.',
        );
      }
      final currentBest = best;
      if (currentBest == null) {
        best = value;
        continue;
      }
      final comparison = value.compareTo(currentBest);
      final shouldReplace = switch (order) {
        _AggregateOrder.min => comparison < 0,
        _AggregateOrder.max => comparison > 0,
      };
      if (shouldReplace) {
        best = value;
      }
    }
    return best as R?;
  }

  num? _sum(List<R> values) {
    var sum = 0.0;
    var count = 0;
    for (final value in values) {
      if (value == null) {
        continue;
      }
      if (value is! num) {
        throw StateError('Property sum requires numeric values.');
      }
      sum += value;
      count += 1;
    }
    return count == 0 ? null : sum;
  }

  double? _average(List<R> values) {
    var sum = 0.0;
    var count = 0;
    for (final value in values) {
      if (value == null) {
        continue;
      }
      if (value is! num) {
        throw StateError('Property average requires numeric values.');
      }
      sum += value;
      count += 1;
    }
    return count == 0 ? null : sum / count;
  }
}

enum _AggregateOrder { min, max }

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
