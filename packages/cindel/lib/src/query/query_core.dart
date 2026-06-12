part of '../query.dart';

// Core query object and execution pipeline.
//
// A `CindelQuery` carries the immutable query shape produced by generated
// `where()` helpers: source, filter, sort, distinct, offset, and limit. Execution
// chooses the fastest safe path available: native query plan, native filter,
// SQLite generated-document execution, or Dart-side typed filtering.

typedef _CindelDocumentReader = Future<List<CindelDocument>> Function();
typedef _CindelDocumentFilter = bool Function(CindelDocument document);
typedef _CindelIdReader = Future<List<int>> Function();

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

/// A typed query over a generated Cindel collection.
///
/// Query objects are immutable. Methods such as [whereMatches], [sortBy], and
/// [limit] return a new query with the requested modifier applied.
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
      readDocuments: () => _unavailableGeneratedDocumentReader(schema),
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
    if (schemaField.indexType == CindelIndexType.hash) {
      return CindelQuery._(
        database: database,
        schema: schema,
        readDocuments: () => _unavailableGeneratedDocumentReader(schema),
        nativeSource: const CindelNativeAllQuerySource(),
        filter: CindelFilter.field(field).equalTo(value),
      );
    }
    return CindelQuery._(
      database: database,
      schema: schema,
      readDocuments: () => _unavailableGeneratedDocumentReader(schema),
      readIds: () => database.queryEqualIds(schema.name, field, value),
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
      readDocuments: () => _unavailableGeneratedDocumentReader(schema),
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
      readDocuments: () => _unavailableGeneratedDocumentReader(schema),
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
      throw CindelQueryError(
        'Hash index `$field` only supports equality queries.',
      );
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
      readDocuments: () => _unavailableGeneratedDocumentReader(schema),
      sourceFilter: sourceFilter,
      readIds: () => database.queryRangeIds(
        schema.name,
        field,
        lower: indexedPrefix,
        upper: indexedPrefix.isEmpty
            ? null
            : _inclusivePrefixUpperBound(indexedPrefix),
      ),
      nativeSource: CindelNativeIndexRangeQuerySource(
        indexName: field,
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

  /// Applies [option] only when [enabled] is true.
  ///
  /// This is useful for dynamic queries where a filter should only be added
  /// when an input value is present.
  CindelQuery<T> optional(bool enabled, CindelQueryOption<T> option) {
    return enabled ? option(this) : this;
  }

  /// Applies [option] for each item and ORs the generated filters together.
  ///
  /// If [items] is empty, the query matches nothing. The [option] callback may
  /// only add filters; sort, distinct, window, projection, or source changes are
  /// rejected because those cannot be represented as one OR filter group.
  CindelQuery<T> anyOf<E>(
    Iterable<E> items,
    CindelQueryRepeatOption<T, E> option,
  ) {
    final itemList = items.toList(growable: false);
    if (itemList.isEmpty) {
      return whereMatches(CindelFilter.any(const []));
    }
    final predicates = [
      for (final item in itemList) _modifierPredicate(option, item),
    ];
    return whereMatches(CindelFilter.any(predicates));
  }

  /// Applies [option] for each item and ANDs the generated filters together.
  ///
  /// If [items] is empty, the query is returned unchanged. The [option]
  /// callback may only add filters; sort, distinct, window, projection, or
  /// source changes are rejected because those cannot be represented as one AND
  /// filter group.
  CindelQuery<T> allOf<E>(
    Iterable<E> items,
    CindelQueryRepeatOption<T, E> option,
  ) {
    final itemList = items.toList(growable: false);
    if (itemList.isEmpty) {
      return this;
    }
    final predicates = [
      for (final item in itemList) _modifierPredicate(option, item),
    ];
    return whereMatches(CindelFilter.all(predicates));
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

  // Native update path. Query updates intentionally require a native plan so
  // changes can be applied atomically without hydrating and rewriting objects.
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
    throw CindelSchemaError(
      'Generated schema `${_schema.dartName}` returned a non-int id field '
      '`${_schema.idField}`.',
    );
  }

  // Main document execution path. It tries native planning first, then applies
  // Dart-side sort, distinct, offset, and limit when storage cannot do it.
  Future<List<CindelDocument>> _matchingDocuments() async {
    final mdbxNativeDocuments =
        await _matchingMdbxNativeDocumentsWithDartPlan();
    if (mdbxNativeDocuments != null) {
      return mdbxNativeDocuments;
    }
    final sqliteNativeDocuments = await _matchingSqliteNativePlanDocuments();
    if (sqliteNativeDocuments != null) {
      return sqliteNativeDocuments;
    }
    final nativePlan = _nativePlan();
    if (nativePlan != null) {
      _throwMissingGeneratedNativeReader(_schema);
    }
    if (_database.backend == CindelStorageBackend.mdbx) {
      _throwMdbxNativePlanRequired('find documents');
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

  // Returns matching ids without hydrating documents when the query shape
  // allows it. Uses typed document matching for sorted, distinct, or windowed
  // queries that require full result processing.
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
    if (nativePlan != null) {
      return _database.queryNativePlanIds(_schema.name, nativePlan);
    }

    final documents = await _matchingDocuments();
    return documents.map(_idFromDocument).toList(growable: false);
  }

  // Hydrates typed objects directly from native binary documents when the
  // schema has a native reader and the current backend can safely use it.
  Future<List<T>?> _matchingNativeObjects() async {
    final nativePlan = _nativePlan();
    final fieldTypes = _nativeFieldTypes();
    final readNativeDocument = _schema.readNativeDocument;
    if (nativePlan == null ||
        readNativeDocument == null ||
        fieldTypes == null ||
        (_database.usesSqliteNativeDocuments && !_canUseSqliteNativePlanner)) {
      return null;
    }
    return _database.queryNativePlanObjects(
      _schema.name,
      nativePlan,
      fieldTypes,
      readNativeDocument,
    );
  }

  Future<List<CindelDocument>>? _matchingMdbxNativeDocumentsWithDartPlan() {
    final readNativeDocument = _schema.readNativeDocument;
    final fieldTypes = _nativeFieldTypes();
    if (_database.backend != CindelStorageBackend.mdbx ||
        _nativePlan() != null ||
        readNativeDocument == null ||
        fieldTypes == null) {
      return null;
    }

    return () async {
      final objects = await _database.queryNativePlanObjects(
        _schema.name,
        const CindelNativeQueryPlan(source: CindelNativeAllQuerySource()),
        fieldTypes,
        readNativeDocument,
      );
      var documents = <CindelDocument>[
        for (final object in objects)
          if (_matchesNativeDartPlan(_documentFromObject(object)))
            _documentFromObject(object),
      ];
      if (_sortKeys.isNotEmpty) {
        documents = _sortDocuments(documents, _sortKeys);
      } else {
        documents = _sortDocumentsByNativeSource(documents);
      }
      if (_distinctFields.isNotEmpty) {
        documents = _distinctDocuments(documents, _distinctFields);
      }
      if (_offset > 0 || _limit != null) {
        documents = _windowDocuments(documents, _offset, _limit);
      }
      return documents;
    }();
  }

  // SQLite generated native documents use the native planner when it can
  // represent the full query.
  Future<List<CindelDocument>>? _matchingSqliteNativePlanDocuments() {
    final dartDocuments = _matchingSqliteNativeDocumentsWithDartPlan();
    if (dartDocuments != null) {
      return dartDocuments;
    }
    final nativePlan = _nativePlan();
    final readNativeDocument = _schema.readNativeDocument;
    final fieldTypes = _nativeFieldTypes();
    if (!_database.usesSqliteNativeDocuments ||
        nativePlan == null ||
        !_canUseSqliteNativePlanner ||
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
      return [for (final object in objects) _documentFromObject(object)];
    }();
  }

  // Evaluates SQLite generated native documents in Dart when native SQL cannot
  // represent the full query. It still reads through generated native readers.
  Future<List<CindelDocument>>? _matchingSqliteNativeDocumentsWithDartPlan() {
    final readNativeDocument = _schema.readNativeDocument;
    final fieldTypes = _nativeFieldTypes();
    if (!_database.usesSqliteNativeDocuments ||
        _canUseSqliteNativePlanner ||
        readNativeDocument == null ||
        fieldTypes == null) {
      return null;
    }

    return () async {
      final objects = await _database.queryNativePlanObjects(
        _schema.name,
        const CindelNativeQueryPlan(source: CindelNativeAllQuerySource()),
        fieldTypes,
        readNativeDocument,
      );
      var documents = <CindelDocument>[
        for (final object in objects)
          if (_matchesSqliteNativeDartPlan(_documentFromObject(object)))
            _documentFromObject(object),
      ];
      if (_sortKeys.isNotEmpty) {
        documents = _sortDocuments(documents, _sortKeys);
      } else {
        documents = _sortDocumentsByNativeSource(documents);
      }
      if (_distinctFields.isNotEmpty) {
        documents = _distinctDocuments(documents, _distinctFields);
      }
      if (_offset > 0 || _limit != null) {
        documents = _windowDocuments(documents, _offset, _limit);
      }
      return documents;
    }();
  }

  bool get _canUseSqliteNativePlanner {
    if (!_database.usesSqliteNativeDocuments ||
        _sourceFilter != null ||
        (_filter != null &&
            (_nativeFilter == null || !_isSqliteNativeSqlFilter(_filter))) ||
        _distinctFields.isNotEmpty) {
      return false;
    }
    final source = _nativeSource;
    return switch (source) {
      null => false,
      CindelNativeAllQuerySource() => true,
      CindelNativeCompositeEqualQuerySource() => false,
      CindelNativeIndexEqualQuerySource(:final indexName) ||
      CindelNativeIndexRangeQuerySource(
        :final indexName,
      ) => switch (_fieldSchema(indexName)) {
        null => false,
        final field => switch (field.indexType) {
          CindelIndexType.hash ||
          CindelIndexType.words ||
          CindelIndexType.multiEntry => false,
          _ => field.binaryType != 'string' || field.indexCaseSensitive,
        },
      },
    };
  }

  bool _isSqliteNativeSqlFilter(CindelFilterPredicate predicate) {
    if (predicate is _FieldFilterPredicate) {
      if (!predicate.isTopLevel) {
        return false;
      }
      final field = _fieldSchema(predicate.field);
      if (field == null) {
        return false;
      }
      final binaryType = field.binaryType;
      final expected = predicate.expected;
      return switch (predicate.operation) {
        _FilterOperation.equalTo =>
          _isSqliteScalarFilterValue(expected) &&
              binaryType != 'list' &&
              binaryType != 'object',
        _FilterOperation.greaterThan ||
        _FilterOperation.greaterThanOrEqualTo ||
        _FilterOperation.lessThan ||
        _FilterOperation.lessThanOrEqualTo =>
          expected is num && (binaryType == 'int' || binaryType == 'double'),
        _FilterOperation.contains =>
          (binaryType == 'string' && expected is String) ||
              (binaryType == 'list' && _isSqliteScalarFilterValue(expected)),
        _FilterOperation.startsWith || _FilterOperation.endsWith =>
          binaryType == 'string' && expected is String,
        _FilterOperation.isEmpty ||
        _FilterOperation.isNotEmpty => binaryType == 'list',
        _FilterOperation.lengthEqualTo ||
        _FilterOperation.lengthGreaterThan ||
        _FilterOperation.lengthGreaterThanOrEqualTo ||
        _FilterOperation.lengthLessThan ||
        _FilterOperation.lengthLessThanOrEqualTo =>
          binaryType == 'list' && expected is int,
      };
    }
    if (predicate is _CompositeFilterPredicate) {
      return predicate.predicates.every(_isSqliteNativeSqlFilter);
    }
    if (predicate is _NotFilterPredicate) {
      return _isSqliteNativeSqlFilter(predicate.predicate);
    }
    return false;
  }

  bool _isSqliteScalarFilterValue(Object? value) {
    return value == null ||
        value is bool ||
        value is int ||
        (value is double && value.isFinite) ||
        value is String;
  }

  List<CindelDocument> _sortDocumentsByNativeSource(
    List<CindelDocument> documents,
  ) {
    final source = _nativeSource;
    if (source is! CindelNativeIndexRangeQuerySource) {
      return documents;
    }
    return _sortDocuments(documents, [
      _CindelSortKey(source.indexName, CindelSortOrder.ascending),
    ]);
  }

  CindelFieldSchema? _fieldSchema(String field) {
    for (final schemaField in _schema.fields) {
      if (schemaField.name == field) {
        return schemaField;
      }
    }
    return null;
  }

  bool _matchesSqliteNativeDartPlan(CindelDocument document) {
    return _matchesNativeDartPlan(document);
  }

  bool _matchesNativeDartPlan(CindelDocument document) {
    if (!_matchesSqliteNativeSource(document)) {
      return false;
    }
    final sourceFilter = _sourceFilter;
    if (sourceFilter != null && !sourceFilter(document)) {
      return false;
    }
    final filter = _filter;
    return filter == null || filter.matches(document);
  }

  bool _matchesSqliteNativeSource(CindelDocument document) {
    final source = _nativeSource;
    return switch (source) {
      null || CindelNativeAllQuerySource() => true,
      CindelNativeCompositeEqualQuerySource(:final indexName, :final values) =>
        _matchesCompositeSource(document, indexName, values),
      CindelNativeIndexEqualQuerySource(:final indexName, :final value) =>
        _matchesFieldEqualSource(document, indexName, value),
      CindelNativeIndexRangeQuerySource(
        :final indexName,
        :final lower,
        :final upper,
      ) =>
        _matchesFieldRangeSource(document, indexName, lower, upper),
    };
  }

  bool _matchesCompositeSource(
    CindelDocument document,
    String indexName,
    List<Object> values,
  ) {
    for (final index in _schema.compositeIndexes) {
      if (index.name != indexName || index.fields.length != values.length) {
        continue;
      }
      for (var i = 0; i < values.length; i += 1) {
        final field = _fieldSchema(index.fields[i]);
        if (!_valuesEqualForIndex(
          document[index.fields[i]],
          values[i],
          field,
        )) {
          return false;
        }
      }
      return true;
    }
    return false;
  }

  bool _matchesFieldEqualSource(
    CindelDocument document,
    String fieldName,
    Object value,
  ) {
    final field = _fieldSchema(fieldName);
    if (field == null) {
      return false;
    }
    final actual = document[fieldName];
    if (field.indexType == CindelIndexType.words) {
      if (actual is! String || value is! String) {
        return false;
      }
      return cindelSplitWords(
        actual,
        caseSensitive: field.indexCaseSensitive,
      ).contains(_normalizedIndexString(value, field));
    }
    if (field.indexType == CindelIndexType.multiEntry) {
      if (actual is! Iterable) {
        return false;
      }
      return actual.any((item) => _valuesEqualForIndex(item, value, field));
    }
    return _valuesEqualForIndex(actual, value, field);
  }

  bool _matchesFieldRangeSource(
    CindelDocument document,
    String fieldName,
    Object? lower,
    Object? upper,
  ) {
    final field = _fieldSchema(fieldName);
    if (field == null) {
      return false;
    }
    final actual = document[fieldName];
    if (field.indexType == CindelIndexType.words) {
      if (actual is! String) {
        return false;
      }
      return cindelSplitWords(
        actual,
        caseSensitive: field.indexCaseSensitive,
      ).any((token) => _valueInRange(token, lower, upper, field));
    }
    return _valueInRange(actual, lower, upper, field);
  }

  bool _valueInRange(
    Object? actual,
    Object? lower,
    Object? upper,
    CindelFieldSchema field,
  ) {
    if (actual == null) {
      return false;
    }
    if (lower != null && _compareIndexValues(actual, lower, field) < 0) {
      return false;
    }
    if (upper != null && _compareIndexValues(actual, upper, field) > 0) {
      return false;
    }
    return true;
  }

  bool _valuesEqualForIndex(
    Object? left,
    Object? right,
    CindelFieldSchema? field,
  ) {
    if (field == null) {
      return left == right;
    }
    if (left is String && right is String) {
      return _normalizedIndexString(left, field) ==
          _normalizedIndexString(right, field);
    }
    return left == right;
  }

  int _compareIndexValues(Object left, Object right, CindelFieldSchema field) {
    if (left is String && right is String) {
      return _normalizedIndexString(
        left,
        field,
      ).compareTo(_normalizedIndexString(right, field));
    }
    return _compareValues(left, right);
  }

  String _normalizedIndexString(String value, CindelFieldSchema field) {
    return field.indexCaseSensitive ? value : value.toLowerCase();
  }

  CindelDocument _documentFromObject(T object) {
    final document = _schema.toDocument(object);
    final getId = _schema.getId;
    if (getId == null || document.containsKey(_schema.idField)) {
      return document;
    }
    return <String, Object?>{...document, _schema.idField: getId(object)};
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
        'object' => 5,
        _ => null,
      };
      if (value == null) {
        return null;
      }
      bytes[i] = value;
    }
    return bytes;
  }

  // Builds a native query plan only when the full query shape can be represented
  // by storage. A null result means execution must stay in Dart.
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
      final documents = await _typedDocumentsByIds(matchingIds);
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

  Future<List<CindelDocument>> _typedDocumentsByIds(Iterable<int> ids) async {
    final readNativeDocument = _schema.readNativeDocument;
    final fieldTypes = _nativeFieldTypes();
    if (readNativeDocument == null || fieldTypes == null) {
      _throwMissingGeneratedNativeReader(_schema);
    }
    final objects = await _database.getAllNativeBinaryDocuments(
      _schema.name,
      ids,
      fieldTypes,
      readNativeDocument,
    );
    return [
      for (final object in objects)
        if (object != null) _documentFromObject(object),
    ];
  }

  bool get _canUseNativeFilter {
    return _database.backend == CindelStorageBackend.mdbx &&
        _schema.toBinaryDocument != null &&
        _schema.fromBinaryDocument != null;
  }

  bool get _canUseNativePlanner {
    if (_sourceFilter != null &&
        _database.backend != CindelStorageBackend.mdbx) {
      return false;
    }
    if (_database.backend == CindelStorageBackend.mdbx) {
      return _schema.toBinaryDocument != null &&
          _schema.fromBinaryDocument != null;
    }
    return _database.usesSqliteNativeDocuments &&
        _schema.writeNativeDocument != null &&
        _schema.readNativeDocument != null;
  }

  bool get _canUseNativeProjection =>
      _canUseNativePlanner && _database.backend == CindelStorageBackend.mdbx;

  Never _throwMdbxNativePlanRequired(String operation) {
    throw UnsupportedError(
      'MDBX `$operation` requires a generated typed native query plan. '
      'Untyped Dart materialization is disabled.',
    );
  }

  // Shared watcher body for `watch()`. Local change sets are skipped only when
  // they cannot affect the previous visible result.
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

  // Lightweight watcher body for `watchLazy()`. It tracks ids instead of
  // emitting hydrated objects.
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

  // Converts a plain equality filter into an indexed source when it is safe.
  // This bridges user-supplied `whereMatches` predicates and generated indexed
  // query factories.
  CindelQuery<T>? _indexedEqualityQuery(CindelFilterPredicate predicate) {
    if (_filter != null ||
        _sourceFilter != null ||
        _nativeSource is! CindelNativeAllQuerySource ||
        predicate is! _FieldFilterPredicate ||
        !predicate.isTopLevel ||
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
      readDocuments: () => _unavailableGeneratedDocumentReader(_schema),
      readIds: () => _database.queryEqualIds(_schema.name, field.name, value),
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
          field.indexType == CindelIndexType.words ||
          field.indexType == CindelIndexType.hash) {
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

  CindelFilterPredicate _modifierPredicate<E>(
    CindelQueryRepeatOption<T, E> option,
    E item,
  ) {
    final base = _copyWith(
      filter: CindelFilter.all(const []),
      clearFilter: true,
    );
    final modified = option(base, item);
    if (!_hasSameModifierShape(base, modified)) {
      throw ArgumentError.value(
        modified,
        'option',
        'anyOf/allOf options may only add filters.',
      );
    }
    return modified._filter ?? CindelFilter.all(const []);
  }

  bool _hasSameModifierShape(CindelQuery<T> base, CindelQuery<T> modified) {
    return identical(base._database, modified._database) &&
        identical(base._schema, modified._schema) &&
        identical(base._readDocuments, modified._readDocuments) &&
        identical(base._sourceFilter, modified._sourceFilter) &&
        identical(base._readIds, modified._readIds) &&
        base._nativeSource == modified._nativeSource &&
        _sortKeyListsEqual(base._sortKeys, modified._sortKeys) &&
        _stringListsEqual(base._distinctFields, modified._distinctFields) &&
        base._offset == modified._offset &&
        base._limit == modified._limit;
  }

  CindelQuery<T> _copyWith({
    CindelFilterPredicate? filter,
    List<_CindelSortKey>? sortKeys,
    List<String>? distinctFields,
    int? offset,
    int? limit,
    bool clearFilter = false,
  }) {
    return CindelQuery._(
      database: _database,
      schema: _schema,
      readDocuments: _readDocuments,
      sourceFilter: _sourceFilter,
      readIds: _readIds,
      nativeSource: _nativeSource,
      filter: clearFilter ? filter : filter ?? _filter,
      sortKeys: sortKeys ?? _sortKeys,
      distinctFields: distinctFields ?? _distinctFields,
      offset: offset ?? _offset,
      limit: limit ?? _limit,
    );
  }
}

Future<List<CindelDocument>> _unavailableGeneratedDocumentReader(
  CindelCollectionSchema<dynamic> schema,
) {
  throw UnsupportedError(
    'Generated query `${schema.dartName}` requires native typed document '
    'readers; untyped document materialization is not available.',
  );
}

Never _throwMissingGeneratedNativeReader(
  CindelCollectionSchema<dynamic> schema,
) {
  throw CindelSchemaError(
    'Generated schema `${schema.dartName}` does not expose native typed '
    'document readers required by this query.',
  );
}
