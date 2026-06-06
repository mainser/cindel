part of '../query.dart';

// Projection queries derived from a `CindelQuery`.
//
// Single-field projections can use native projection and aggregate APIs when the
// backing query has a native plan. Multi-field projections currently hydrate the
// matching documents and then select the requested fields.

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

    final nativeObjects = await _query._matchingNativeObjects();
    if (nativeObjects != null) {
      final decode = _decode;
      return [
        for (final object in nativeObjects)
          if (decode == null)
            _query._documentFromObject(object)[_field] as R
          else
            decode(_query._documentFromObject(object)[_field]),
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
      throw CindelNativeError('Native Cindel returned a non-numeric count.');
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
      throw CindelNativeError('Native Cindel returned a non-numeric sum.');
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
      throw CindelNativeError('Native Cindel returned a non-numeric average.');
    }
    return _average(await findAll());
  }

  // Attempts a native aggregate. Returning null means the caller should use the
  // Dart fallback over projected values.
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
        throw CindelQueryError(
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
        throw CindelQueryError('Property sum requires numeric values.');
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
        throw CindelQueryError('Property average requires numeric values.');
      }
      sum += value;
      count += 1;
    }
    return count == 0 ? null : sum / count;
  }
}

// Internal order used by the Dart min/max fallback.
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
    final nativeObjects = await _query._matchingNativeObjects();
    if (nativeObjects != null) {
      return [
        for (final object in nativeObjects)
          _projectDocument(_query._documentFromObject(object), _fields),
      ];
    }

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

CindelDocument _projectDocument(
  CindelDocument document,
  Iterable<String> fields,
) {
  return {for (final field in fields) field: document[field]};
}
