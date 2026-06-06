/// Base class for runtime failures reported by Cindel itself.
///
/// Cindel errors extend [StateError] for compatibility with earlier versions
/// that reported these failures as plain state errors.
sealed class CindelError extends StateError {
  CindelError(super.message);

  /// Short stable name used by [toString].
  String get name;

  @override
  String toString() {
    return '$name: $message';
  }
}

/// The native database engine could not be opened.
final class CindelOpenError extends CindelError {
  CindelOpenError({required String backend})
    : super('Failed to open Cindel native engine with backend `$backend`.');

  @override
  String get name => 'CindelOpenError';
}

/// An operation was attempted after the database handle was closed.
final class CindelDatabaseClosedError extends CindelError {
  CindelDatabaseClosedError() : super('CindelDatabase is closed.');

  @override
  String get name => 'CindelDatabaseClosedError';
}

/// A transaction operation violates Cindel's transaction rules.
final class CindelTransactionError extends CindelError {
  CindelTransactionError(super.message);

  @override
  String get name => 'CindelTransactionError';
}

/// A registered schema is missing or incompatible with the requested operation.
final class CindelSchemaError extends CindelError {
  CindelSchemaError(super.message);

  @override
  String get name => 'CindelSchemaError';
}

/// A query cannot be planned or executed with the requested field/index shape.
final class CindelQueryError extends CindelError {
  CindelQueryError(super.message);

  @override
  String get name => 'CindelQueryError';
}

/// A unique index would contain the same value for more than one document.
final class CindelUniqueIndexError extends CindelError {
  CindelUniqueIndexError(String indexName)
    : super('Unique index `$indexName` already contains this value.');

  @override
  String get name => 'CindelUniqueIndexError';
}

/// The native layer returned data Cindel cannot use safely.
final class CindelNativeError extends CindelError {
  CindelNativeError(super.message);

  @override
  String get name => 'CindelNativeError';
}
