/// Base class for runtime failures reported by Cindel itself.
///
/// Cindel errors extend [StateError] for compatibility with earlier versions
/// that reported these failures as plain state errors.
sealed class CindelError extends StateError {
  CindelError(
    super.message, {
    this.operation,
    this.backend,
    this.code,
    this.cause,
  });

  /// Operation that failed, when reported by the engine boundary.
  final String? operation;

  /// Storage backend, when known at the boundary.
  final String? backend;

  /// Original transport or backend code, when available.
  final String? code;

  /// Original diagnostic; retained before rollback or close can replace it.
  final Object? cause;

  /// Short stable name used by [toString].
  String get name;

  @override
  String toString() {
    return '$name: $message';
  }
}

/// The native database engine could not be opened.
final class CindelOpenError extends CindelError {
  CindelOpenError({required String backend, Object? cause, String? code})
    : super(
        'Failed to open Cindel native engine with backend `$backend`.'
        '${cause == null ? "" : " $cause"}',
        operation: 'open',
        backend: backend,
        cause: cause,
        code: code,
      );

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
  CindelTransactionError(
    super.message, {
    super.operation,
    super.backend,
    super.code,
    super.cause,
  });

  @override
  String get name => 'CindelTransactionError';
}

/// A registered schema is missing or incompatible with the requested operation.
final class CindelSchemaError extends CindelError {
  CindelSchemaError(
    super.message, {
    super.operation,
    super.backend,
    super.code,
    super.cause,
  });

  @override
  String get name => 'CindelSchemaError';
}

/// A query cannot be planned or executed with the requested field/index shape.
final class CindelQueryError extends CindelError {
  CindelQueryError(
    super.message, {
    super.operation,
    super.backend,
    super.code,
    super.cause,
  });

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
  CindelNativeError(
    super.message, {
    super.operation,
    super.backend,
    super.code,
    super.cause,
  });

  @override
  String get name => 'CindelNativeError';
}

/// Converts an engine/transport failure without discarding its diagnostic.
/// Internal runtime helper; operation names are kept as supplied by the caller.
CindelError cindelOperationError(
  String operation,
  Object cause, {
  String? backend,
  String? code,
}) {
  final message = 'Cindel $operation failed: $cause';
  final normalized = operation.toLowerCase();
  if (normalized.contains('transaction')) {
    return CindelTransactionError(
      message,
      operation: operation,
      backend: backend,
      code: code,
      cause: cause,
    );
  }
  if (normalized.contains('schema')) {
    return CindelSchemaError(
      message,
      operation: operation,
      backend: backend,
      code: code,
      cause: cause,
    );
  }
  if (normalized.contains('query') ||
      normalized.contains('reader') ||
      normalized.startsWith('get') ||
      normalized.startsWith('read ')) {
    return CindelQueryError(
      message,
      operation: operation,
      backend: backend,
      code: code,
      cause: cause,
    );
  }
  return CindelNativeError(
    message,
    operation: operation,
    backend: backend,
    code: code,
    cause: cause,
  );
}
