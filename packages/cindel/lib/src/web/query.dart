import 'dart:async';
import 'dart:typed_data';

import 'package:cindel_annotations/cindel_annotations.dart';

import '../cindel_error.dart';
import '../schema.dart';
import 'database.dart';
import 'wire.dart';

typedef _CindelDocumentFilter = bool Function(CindelDocument document);

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
/// Web queries use the same generated public API as native queries. When the
/// query can be represented as a SQLite-native plan, execution is delegated to
/// the Worker/Wasm backend for ids, objects, counts, projection, aggregates,
/// updates, and deletes. Query shapes that cannot be encoded as a native plan
/// are evaluated over generated typed rows instead of falling back to untyped
/// document storage.
final class CindelQuery<T> {
  CindelQuery._({
    required CindelDatabase database,
    required CindelCollectionSchema<T> schema,
    _CindelDocumentFilter? sourceFilter,
    WireQuerySource nativeSource = const WireQuerySource.all(dedupe: false),
    CindelFilterPredicate? filter,
    List<_SortKey> sortKeys = const [],
    List<String> distinctFields = const [],
    int offset = 0,
    int? limit,
  }) : _database = database,
       _schema = schema,
       _sourceFilter = sourceFilter,
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
    return CindelQuery._(database: database, schema: schema);
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
      return CindelQuery.all(
        database: database,
        schema: schema,
      ).whereMatches(CindelFilter.field(field).equalTo(value));
    }
    if (_requiresDartIndexedEquality(schemaField, value)) {
      return CindelQuery._(
        database: database,
        schema: schema,
        sourceFilter: _caseInsensitiveStringEqualityFilter(
          schemaField,
          value as String,
        ),
      );
    }
    return CindelQuery._(
      database: database,
      schema: schema,
      nativeSource: WireQuerySource.indexEqual(
        indexName: field,
        value: webIndexValueForField(value, schemaField),
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
  final _CindelDocumentFilter? _sourceFilter;
  final WireQuerySource _nativeSource;
  final CindelFilterPredicate? _filter;
  final Uint8List? _nativeFilter;
  final List<_SortKey> _sortKeys;
  final List<String> _distinctFields;
  final int _offset;
  final int? _limit;

  /// Returns a new query that filters the current query result by [predicate].
  CindelQuery<T> whereMatches(CindelFilterPredicate predicate) {
    final indexedEqualityQuery = _indexedEqualityQuery(predicate);
    if (indexedEqualityQuery != null) {
      return indexedEqualityQuery;
    }
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
          option(_modifierBaseQuery(), item)._filter!,
      ]),
    );
  }

  /// Applies [option] for each item and ANDs generated filters together.
  CindelQuery<T> allOf<E>(
    Iterable<E> items,
    CindelQueryRepeatOption<T, E> option,
  ) {
    final filters = [
      for (final item in items) option(_modifierBaseQuery(), item)._filter!,
    ];
    return filters.isEmpty ? this : whereMatches(CindelFilter.all(filters));
  }

  CindelQuery<T> _modifierBaseQuery() {
    return CindelQuery.all(
      database: _database,
      schema: _schema,
    ).whereMatches(CindelFilter.all(const []));
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
    final values = await findAll();
    return values.isEmpty ? null : values.first;
  }

  /// Returns the number of objects matching this query.
  Future<int> count() async {
    final nativePlan = _nativePlan();
    if (nativePlan != null) {
      return _database.queryNativePlanCount(_schema.name, nativePlan);
    }
    return (await _matchingDocuments()).length;
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
    await _deleteIds([_idFromDocument(documents.first)]);
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
    final ids = documents.map(_idFromDocument).toList(growable: false);
    await _deleteIds(ids);
    return ids.length;
  }

  /// Updates the first object matching this query using native property writes.
  Future<bool> updateFirst(Map<String, Object?> changes) async {
    return (await updateAll(changes)) > 0;
  }

  /// Updates every object matching this query using native property writes.
  Future<int> updateAll(Map<String, Object?> changes) async {
    if (changes.isEmpty) {
      return 0;
    }
    final nativePlan = _nativePlan();
    if (nativePlan == null) {
      throw UnsupportedError(
        'Cindel Web query updates require a SQLite-native query plan.',
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

  Future<List<CindelDocument>> _matchingDocuments() async {
    final nativeDocuments = await _matchingNativeDocuments();
    if (nativeDocuments != null) {
      return nativeDocuments;
    }
    throw UnsupportedError(
      'Cindel Web typed queries require SQLite-native document support.',
    );
  }

  Future<void> _deleteIds(List<int> ids) {
    if (_usesNativeDocuments()) {
      return _database.deleteAll(_schema.name, ids);
    }
    throw UnsupportedError(
      'Cindel Web typed deletes require SQLite-native document support.',
    );
  }

  WireQueryPlan? _nativePlan({int? limitOverride}) {
    final nativeFilter = _nativeFilter;
    if (!_canUseNativePlanner || (_filter != null && nativeFilter == null)) {
      return null;
    }
    final effectiveLimit = switch ((_limit, limitOverride)) {
      (null, null) => null,
      (final current?, null) => current,
      (null, final override?) => override,
      (final current?, final override?) =>
        current < override ? current : override,
    };
    return WireQueryPlan(
      source: _nativeSource,
      filter: nativeFilter,
      sorts: [
        for (final sortKey in _sortKeys)
          WireQuerySort(
            field: sortKey.field,
            ascending: sortKey.order == CindelSortOrder.ascending,
          ),
      ],
      distinctFields: _distinctFields,
      offset: _offset,
      limit: effectiveLimit,
    );
  }

  bool get _canUseNativePlanner {
    if (_sourceFilter != null) {
      return false;
    }
    return _usesNativeDocuments() && _schema.readNativeDocument != null;
  }

  Future<List<T>?> _matchingNativeObjects() async {
    final nativePlan = _nativePlan();
    final readNativeDocument = _schema.readNativeDocument;
    final fieldTypes = _nativeFieldTypes();
    if (!_usesNativeDocuments() ||
        readNativeDocument == null ||
        fieldTypes == null) {
      return null;
    }
    if (nativePlan != null) {
      return _database.queryNativePlanObjects(
        _schema.name,
        nativePlan,
        fieldTypes,
        readNativeDocument,
      );
    }
    final documents = await _matchingNativeDocumentsWithDartPlan(
      fieldTypes,
      readNativeDocument,
    );
    return documents?.map(_schema.fromDocument).toList(growable: false);
  }

  Future<List<CindelDocument>?> _matchingNativeDocuments() {
    final readNativeDocument = _schema.readNativeDocument;
    final fieldTypes = _nativeFieldTypes();
    if (!_usesNativeDocuments() ||
        readNativeDocument == null ||
        fieldTypes == null) {
      return Future<List<CindelDocument>?>.value();
    }
    final nativePlan = _nativePlan();
    if (nativePlan != null) {
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
    return _matchingNativeDocumentsWithDartPlan(fieldTypes, readNativeDocument);
  }

  Future<List<CindelDocument>?> _matchingNativeDocumentsWithDartPlan(
    Uint8List fieldTypes,
    CindelReadNativeDocument<T> readNativeDocument,
  ) {
    return () async {
      final objects = await _database.queryNativePlanObjects(
        _schema.name,
        WireQueryPlan(
          source: const WireQuerySource.all(dedupe: false),
          filter: null,
          sorts: const [],
          distinctFields: const [],
          offset: 0,
          limit: null,
        ),
        fieldTypes,
        readNativeDocument,
      );
      var documents = <CindelDocument>[
        for (final object in objects)
          if (_matchesBeforeWindow(_documentFromObject(object)))
            _documentFromObject(object),
      ];
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
    }();
  }

  Future<List<int>> _matchingIds() async {
    if (_sortKeys.isEmpty &&
        _distinctFields.isEmpty &&
        _offset == 0 &&
        _limit == null &&
        _filter == null &&
        _sourceFilter == null) {
      return _database.documentIds(_schema.name);
    }

    final nativePlan = _nativePlan();
    if (nativePlan != null) {
      return _database.queryNativePlanIds(_schema.name, nativePlan);
    }

    final documents = await _matchingDocuments();
    return documents.map(_idFromDocument).toList(growable: false);
  }

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

  CindelDocument _documentFromObject(T object) {
    final document = _schema.toDocument(object);
    final getId = _schema.getId;
    if (getId == null || document.containsKey(_schema.idField)) {
      return document;
    }
    return <String, Object?>{...document, _schema.idField: getId(object)};
  }

  bool _usesNativeDocuments() {
    return _database.usesSqliteNativeDocuments &&
        _schema.writeNativeDocument != null &&
        _nativeFieldTypes() != null;
  }

  Uint8List? _nativeFieldTypes() {
    final fields = _schema.fields.toList(growable: false)
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
    return bytes;
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
      sourceFilter: _sourceFilter,
      nativeSource: _nativeSource,
      filter: filter ?? _filter,
      sortKeys: sortKeys ?? _sortKeys,
      distinctFields: distinctFields ?? _distinctFields,
      offset: offset ?? _offset,
      limit: limit ?? _limit,
    );
  }

  CindelQuery<T>? _indexedEqualityQuery(CindelFilterPredicate predicate) {
    if (_filter != null ||
        _sourceFilter != null ||
        _nativeSource is! WireQueryAllSource ||
        predicate is! _FieldFilterPredicate ||
        predicate.path.length != 1 ||
        predicate.operation != _FilterOperation.equalTo ||
        predicate.expected == null) {
      return null;
    }

    final field = _indexedEqualityField(predicate);
    if (field == null) {
      return null;
    }
    final value = predicate.expected!;
    if (_requiresDartIndexedEquality(field, value)) {
      return CindelQuery._(
        database: _database,
        schema: _schema,
        sourceFilter: _caseInsensitiveStringEqualityFilter(
          field,
          value as String,
        ),
        sortKeys: _sortKeys,
        distinctFields: _distinctFields,
        offset: _offset,
        limit: _limit,
      );
    }
    return CindelQuery._(
      database: _database,
      schema: _schema,
      nativeSource: WireQuerySource.indexEqual(
        indexName: field.name,
        value: webIndexValueForField(value, field),
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
      if (field.name != predicate.path.single || !field.isIndexed) {
        continue;
      }
      if (field.indexType == CindelIndexType.multiEntry ||
          field.indexType == CindelIndexType.words ||
          field.indexType == CindelIndexType.hash) {
        return null;
      }
      return field;
    }
    return null;
  }
}

bool _requiresDartIndexedEquality(CindelFieldSchema field, Object value) {
  return !field.indexCaseSensitive &&
      field.binaryType == 'string' &&
      value is String;
}

_CindelDocumentFilter _caseInsensitiveStringEqualityFilter(
  CindelFieldSchema field,
  String expected,
) {
  final normalizedExpected = expected.toLowerCase();
  return (document) {
    final actual = document[field.name];
    return actual is String && actual.toLowerCase() == normalizedExpected;
  };
}

Uint8List? _nativeFilterBytes(CindelFilterPredicate? predicate) {
  if (predicate == null) {
    return null;
  }
  final filter = _nativeFilterWire(predicate);
  return filter == null ? null : encodeFilter(filter);
}

WireFilter? _nativeFilterWire(CindelFilterPredicate predicate) {
  if (predicate is _FieldFilterPredicate) {
    if (predicate.path.length != 1 ||
        !_isNativeFilterValue(predicate.expected)) {
      return null;
    }
    final value = _nativeFilterValue(predicate.expected);
    final operation = _nativeFilterOperation(predicate.operation, value);
    if (operation == null) {
      return null;
    }
    return WireFilter.field(
      field: predicate.path.single,
      operation: operation,
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
    return encoded == null ? null : WireFilter.not(encoded);
  }

  return null;
}

WireFilterOperation? _nativeFilterOperation(
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
    _FilterOperation.isEmpty ||
    _FilterOperation.isNotEmpty ||
    _FilterOperation.lengthEqualTo ||
    _FilterOperation.lengthGreaterThan ||
    _FilterOperation.lengthGreaterThanOrEqualTo ||
    _FilterOperation.lengthLessThan ||
    _FilterOperation.lengthLessThanOrEqualTo => null,
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

CindelFieldSchema _schemaField<T>(
  CindelCollectionSchema<T> schema,
  String field,
) {
  for (final schemaField in schema.fields) {
    if (schemaField.name == field) {
      return schemaField;
    }
  }
  throw CindelSchemaError(
    'Field `$field` is not part of `${schema.dartName}`.',
  );
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
    if (nativePlan != null) {
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
    final native = await _tryNativeAggregate('count');
    if (native != null) {
      final value = native.value;
      if (value is int) {
        return value;
      }
      if (value is num) {
        return value.toInt();
      }
      throw CindelNativeError('Native Cindel returned a non-numeric count.');
    }
    return (await findAll()).where((value) => value != null).length;
  }

  /// Returns the smallest projected value.
  Future<R?> min() async {
    final native = await _tryNativeAggregate('min');
    if (native != null) {
      return _decodeAggregateValue(native.value);
    }
    return _minMax(await findAll(), true);
  }

  /// Returns the largest projected value.
  Future<R?> max() async {
    final native = await _tryNativeAggregate('max');
    if (native != null) {
      return _decodeAggregateValue(native.value);
    }
    return _minMax(await findAll(), false);
  }

  /// Returns the sum of numeric projected values.
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
      throw CindelNativeError('Native Cindel returned a non-numeric sum.');
    }
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
    final native = await _tryNativeAggregate('average');
    if (native != null) {
      final value = native.value;
      if (value == null) {
        return null;
      }
      if (value is num) {
        return value.toDouble();
      }
      throw CindelNativeError('Native Cindel returned a non-numeric average.');
    }
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

  Future<({Object? value})?> _tryNativeAggregate(String operation) async {
    final nativePlan = _query._nativePlan();
    if (nativePlan == null) {
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
    for (final actual in _valuesAtPath(document, 0)) {
      if (_matchesValue(actual)) {
        return true;
      }
    }
    return false;
  }

  bool _matchesValue(Object? actual) {
    return switch (operation) {
      _FilterOperation.equalTo => _deepEquals(actual, expected),
      _FilterOperation.greaterThan => _compare(actual, expected) > 0,
      _FilterOperation.greaterThanOrEqualTo => _compare(actual, expected) >= 0,
      _FilterOperation.lessThan => _compare(actual, expected) < 0,
      _FilterOperation.lessThanOrEqualTo => _compare(actual, expected) <= 0,
      _FilterOperation.contains =>
        actual is String
            ? actual.contains(expected.toString())
            : actual is Iterable &&
                  actual.any((value) => _deepEquals(value, expected)),
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

  Iterable<Object?> _valuesAtPath(Object? current, int pathIndex) sync* {
    if (pathIndex == path.length) {
      yield current;
      return;
    }
    if (current is Map<Object?, Object?>) {
      final part = path[pathIndex];
      if (!current.containsKey(part)) {
        return;
      }
      yield* _valuesAtPath(current[part], pathIndex + 1);
      return;
    }
    if (current is Iterable<Object?>) {
      for (final value in current) {
        yield* _valuesAtPath(value, pathIndex);
      }
    }
  }
}

bool _deepEquals(Object? left, Object? right) {
  if (identical(left, right) || left == right) {
    return true;
  }
  if (left is Map<Object?, Object?> && right is Map<Object?, Object?>) {
    if (left.length != right.length) {
      return false;
    }
    for (final entry in left.entries) {
      if (!right.containsKey(entry.key) ||
          !_deepEquals(entry.value, right[entry.key])) {
        return false;
      }
    }
    return true;
  }
  if (left is Iterable<Object?> && right is Iterable<Object?>) {
    final leftIterator = left.iterator;
    final rightIterator = right.iterator;
    while (true) {
      final leftHasNext = leftIterator.moveNext();
      final rightHasNext = rightIterator.moveNext();
      if (leftHasNext != rightHasNext) {
        return false;
      }
      if (!leftHasNext) {
        return true;
      }
      if (!_deepEquals(leftIterator.current, rightIterator.current)) {
        return false;
      }
    }
  }
  return false;
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
