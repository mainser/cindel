part of '../query.dart';

// Converts Dart filter predicates into the compact wire filter format accepted
// by native storage.
//
// Returning null is intentional: it means the predicate cannot be represented
// losslessly by native storage and must continue through the Dart evaluator.

// Encodes a predicate into bytes for native APIs, or returns null when the
// predicate is not native-safe.
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

// Converts supported predicate nodes into their wire model. Nested-path filters
// and unsupported value shapes stay Dart-only.
WireFilter? _nativeFilterWire(CindelFilterPredicate predicate) {
  if (predicate is _FieldFilterPredicate) {
    if (!predicate.isTopLevel) {
      return null;
    }
    final expected = switch (predicate.operation) {
      _FilterOperation.isEmpty || _FilterOperation.isNotEmpty => 0,
      _ => predicate.expected,
    };
    if (!_isNativeFilterValue(expected)) {
      return null;
    }
    final value = _nativeFilterValue(expected);
    final operation = _nativeFilterOperation(predicate.operation, value);
    if (operation == null) {
      return null;
    }
    return WireFilter.field(
      field: predicate.field,
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
    if (encoded == null) {
      return null;
    }
    return WireFilter.not(encoded);
  }

  return null;
}

// Maps Dart filter operations to native operations.
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
    _FilterOperation.isEmpty => WireFilterOperation.lengthEqual,
    _FilterOperation.isNotEmpty => WireFilterOperation.lengthGreaterThan,
    _FilterOperation.lengthEqualTo => WireFilterOperation.lengthEqual,
    _FilterOperation.lengthGreaterThan => WireFilterOperation.lengthGreaterThan,
    _FilterOperation.lengthGreaterThanOrEqualTo =>
      WireFilterOperation.lengthGreaterThanOrEqual,
    _FilterOperation.lengthLessThan => WireFilterOperation.lengthLessThan,
    _FilterOperation.lengthLessThanOrEqualTo =>
      WireFilterOperation.lengthLessThanOrEqual,
  };
}

// Converts a Dart filter value into a wire value after `_isNativeFilterValue`
// has proven that it is safe to send across the native boundary.
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

// Encodes object filter values with stable field ordering.
List<WireObjectEntry> _nativeFilterObjectEntries(Map<Object?, Object?> value) {
  final entries = <WireObjectEntry>[
    for (final MapEntry(:key, :value) in value.entries)
      WireObjectEntry(key as String, _nativeFilterValue(value)),
  ];
  entries.sort((left, right) => left.name.compareTo(right.name));
  return entries;
}

// Native filters accept only value shapes that are stable across Dart, wire, and
// the Rust storage implementation.
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
