part of '../database.dart';

// Native query plans are the compact Dart-side representation of work that can
// be pushed into the Rust engine. CindelQuery builds these objects, and
// CindelDatabase serializes them into the wire format before calling native FFI.

/// Base class for native query sources.
///
/// A source chooses the initial candidate id stream before filters, sorting,
/// distinct, offset, or limit are applied by the native query planner.
sealed class CindelNativeQuerySource {
  const CindelNativeQuerySource();
}

/// Reads every document id in a collection.
final class CindelNativeAllQuerySource extends CindelNativeQuerySource {
  const CindelNativeAllQuerySource();
}

/// Reads candidate ids from a single-field equality index lookup.
final class CindelNativeIndexEqualQuerySource extends CindelNativeQuerySource {
  const CindelNativeIndexEqualQuerySource({
    required this.indexName,
    required this.value,
    this.dedupe = false,
  });

  /// Name of the index to read.
  final String indexName;

  /// Exact index value to match before wire encoding.
  final Object value;

  /// Whether duplicate ids must be removed from multi-entry or word indexes.
  final bool dedupe;
}

/// Reads candidate ids from a composite equality index lookup.
final class CindelNativeCompositeEqualQuerySource
    extends CindelNativeQuerySource {
  const CindelNativeCompositeEqualQuerySource({
    required this.indexName,
    required this.values,
  });

  /// Name of the composite index to read.
  final String indexName;

  /// Values for the composite fields, in schema order.
  final List<Object> values;
}

/// Reads candidate ids from a single-field range index lookup.
final class CindelNativeIndexRangeQuerySource extends CindelNativeQuerySource {
  const CindelNativeIndexRangeQuerySource({
    required this.indexName,
    required this.lower,
    required this.upper,
    this.dedupe = false,
  });

  /// Name of the range-capable index to read.
  final String indexName;

  /// Inclusive lower bound, or `null` for an open lower bound.
  final Object? lower;

  /// Inclusive upper bound, or `null` for an open upper bound.
  final Object? upper;

  /// Whether duplicate ids must be removed from multi-entry or word indexes.
  final bool dedupe;
}

/// Sort applied by a native query plan after source and filter execution.
final class CindelNativeQuerySort {
  const CindelNativeQuerySort({required this.field, required this.descending});

  /// Field name to sort by.
  final String field;

  /// Whether values are sorted descending instead of ascending.
  final bool descending;
}

/// Native query plan executed by the Rust engine.
///
/// Plans are built from generated query helpers and keep Dart-side semantics
/// visible while allowing the native layer to stream ids, documents,
/// projections, aggregates, deletes, and updates.
final class CindelNativeQueryPlan {
  const CindelNativeQueryPlan({
    required this.source,
    this.filter,
    this.sorts = const [],
    this.distinctFields = const [],
    this.offset = 0,
    this.limit,
  });

  /// Initial candidate id source.
  final CindelNativeQuerySource source;

  /// Encoded native filter bytes, or `null` when no native filter is needed.
  final Uint8List? filter;

  /// Ordered sort clauses.
  final List<CindelNativeQuerySort> sorts;

  /// Fields used to drop duplicate projected document values.
  final List<String> distinctFields;

  /// Number of matching rows to skip.
  final int offset;

  /// Maximum number of rows to return, or `null` for no limit.
  final int? limit;
}
