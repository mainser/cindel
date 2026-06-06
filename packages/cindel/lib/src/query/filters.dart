part of '../query.dart';

// Filter predicate builders and the Dart-side predicate implementations.
//
// Public callers normally reach this file through `CindelFilter.field(...)` or
// generated query helpers. The private predicate classes are also used by the
// native filter encoder when a predicate can be represented by the wire format.

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
    return CindelFilterField._(<String>[field]);
  }

  /// Creates a predicate builder for a nested object [path].
  static CindelFilterField path(Iterable<String> path) {
    final parts = path.toList(growable: false);
    if (parts.isEmpty || parts.any((part) => part.trim().isEmpty)) {
      throw ArgumentError.value(path, 'path', 'Must not contain empty parts.');
    }
    return CindelFilterField._(parts);
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
    return _FieldFilterPredicate(
      path: _path,
      expected: value,
      operation: _FilterOperation.equalTo,
    );
  }

  /// Matches numeric fields greater than [value].
  CindelFilterPredicate greaterThan(num value) {
    return _FieldFilterPredicate(
      path: _path,
      expected: value,
      operation: _FilterOperation.greaterThan,
    );
  }

  /// Matches numeric fields greater than or equal to [value].
  CindelFilterPredicate greaterThanOrEqualTo(num value) {
    return _FieldFilterPredicate(
      path: _path,
      expected: value,
      operation: _FilterOperation.greaterThanOrEqualTo,
    );
  }

  /// Matches numeric fields less than [value].
  CindelFilterPredicate lessThan(num value) {
    return _FieldFilterPredicate(
      path: _path,
      expected: value,
      operation: _FilterOperation.lessThan,
    );
  }

  /// Matches numeric fields less than or equal to [value].
  CindelFilterPredicate lessThanOrEqualTo(num value) {
    return _FieldFilterPredicate(
      path: _path,
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

  /// Matches string fields containing [value] or list fields containing
  /// [value] as an element.
  CindelFilterPredicate contains(Object? value) {
    return _FieldFilterPredicate(
      path: _path,
      expected: value,
      operation: _FilterOperation.contains,
    );
  }

  /// Matches list fields with no elements.
  CindelFilterPredicate isEmpty() {
    return _FieldFilterPredicate(
      path: _path,
      expected: null,
      operation: _FilterOperation.isEmpty,
    );
  }

  /// Matches list fields with at least one element.
  CindelFilterPredicate isNotEmpty() {
    return _FieldFilterPredicate(
      path: _path,
      expected: null,
      operation: _FilterOperation.isNotEmpty,
    );
  }

  /// Matches list fields with exactly [length] elements.
  CindelFilterPredicate lengthEqualTo(int length) {
    return _FieldFilterPredicate(
      path: _path,
      expected: length,
      operation: _FilterOperation.lengthEqualTo,
    );
  }

  /// Matches list fields shorter than [length].
  CindelFilterPredicate lengthLessThan(int length, {bool include = false}) {
    return _FieldFilterPredicate(
      path: _path,
      expected: length,
      operation: include
          ? _FilterOperation.lengthLessThanOrEqualTo
          : _FilterOperation.lengthLessThan,
    );
  }

  /// Matches list fields longer than [length].
  CindelFilterPredicate lengthGreaterThan(int length, {bool include = false}) {
    return _FieldFilterPredicate(
      path: _path,
      expected: length,
      operation: include
          ? _FilterOperation.lengthGreaterThanOrEqualTo
          : _FilterOperation.lengthGreaterThan,
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
    return _FieldFilterPredicate(
      path: _path,
      expected: value,
      operation: _FilterOperation.startsWith,
    );
  }

  /// Matches string fields ending with [value].
  CindelFilterPredicate endsWith(String value) {
    return _FieldFilterPredicate(
      path: _path,
      expected: value,
      operation: _FilterOperation.endsWith,
    );
  }
}

// Operations supported by the Dart predicate evaluator. Native storage supports
// only the subset encoded in `native_filter_encoding.dart`.
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

// Field predicate over a top-level field or nested document path.
//
// Nested paths walk maps and list items recursively, which lets a filter target
// values inside embedded objects or lists of embedded objects.
final class _FieldFilterPredicate implements CindelFilterPredicate {
  const _FieldFilterPredicate({
    required List<String> path,
    required this.expected,
    required this.operation,
  }) : path = path;

  final List<String> path;
  final Object? expected;
  final _FilterOperation operation;

  bool get isTopLevel => path.length == 1;

  String get field => path.single;

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
      _FilterOperation.greaterThan => _compareNumbers(actual, expected) > 0,
      _FilterOperation.greaterThanOrEqualTo =>
        _compareNumbers(actual, expected) >= 0,
      _FilterOperation.lessThan => _compareNumbers(actual, expected) < 0,
      _FilterOperation.lessThanOrEqualTo =>
        _compareNumbers(actual, expected) <= 0,
      _FilterOperation.contains =>
        actual is Iterable
            ? actual.any((value) => _deepEquals(value, expected))
            : _string(actual).contains(_string(expected)),
      _FilterOperation.isEmpty => _listLength(actual) == 0,
      _FilterOperation.isNotEmpty => (_listLength(actual) ?? 0) > 0,
      _FilterOperation.lengthEqualTo => _matchesLength(
        actual,
        expected,
        (comparison) => comparison == 0,
      ),
      _FilterOperation.lengthGreaterThan => _matchesLength(
        actual,
        expected,
        (comparison) => comparison > 0,
      ),
      _FilterOperation.lengthGreaterThanOrEqualTo => _matchesLength(
        actual,
        expected,
        (comparison) => comparison >= 0,
      ),
      _FilterOperation.lengthLessThan => _matchesLength(
        actual,
        expected,
        (comparison) => comparison < 0,
      ),
      _FilterOperation.lengthLessThanOrEqualTo => _matchesLength(
        actual,
        expected,
        (comparison) => comparison <= 0,
      ),
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

  bool _matchesLength(
    Object? actual,
    Object? expected,
    bool Function(int comparison) test,
  ) {
    final comparison = _compareLength(actual, expected);
    return comparison != null && test(comparison);
  }

  int? _compareLength(Object? actual, Object? expected) {
    final length = _listLength(actual);
    if (length == null || expected is! num) {
      return null;
    }
    return length.compareTo(expected);
  }

  int? _listLength(Object? actual) {
    return actual is Iterable ? actual.length : null;
  }

  String _string(Object? value) {
    return value is String ? value : '';
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

// Deep equality for document values. This is intentionally structural for maps
// and iterables because manual documents and embedded objects may contain nested
// value trees.
bool _deepEquals(Object? left, Object? right) {
  if (identical(left, right) || left == right) {
    return true;
  }
  if (left is Map<Object?, Object?> && right is Map<Object?, Object?>) {
    if (left.length != right.length) {
      return false;
    }
    for (final entry in left.entries) {
      if (!right.containsKey(entry.key)) {
        return false;
      }
      if (!_deepEquals(entry.value, right[entry.key])) {
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

// Boolean composition mode for filter groups.
enum _CompositeFilterMode { all, any }

// Predicate group used by `CindelFilter.all` and `CindelFilter.any`.
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

// Negates another predicate.
final class _NotFilterPredicate implements CindelFilterPredicate {
  const _NotFilterPredicate(this.predicate);

  final CindelFilterPredicate predicate;

  @override
  bool matches(CindelDocument document) {
    return !predicate.matches(document);
  }
}
