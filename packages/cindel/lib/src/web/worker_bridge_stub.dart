/// Response returned by a Cindel Web worker request.
///
/// This stub exists so the internal Web database facade can be analyzed outside
/// Web targets. Constructing the bridge itself is unsupported.
final class CindelWebWorkerResponse {
  /// Creates a worker response with the raw transported [payload].
  const CindelWebWorkerResponse({required this.payload});

  /// Raw payload returned by the worker for the completed request.
  final Object? payload;
}

/// Structured failure returned by the Cindel Web worker bridge.
final class CindelWebWorkerException implements Exception {
  /// Creates an exception with a stable machine-readable [code] and [message].
  const CindelWebWorkerException(this.code, this.message);

  /// Machine-readable error code sent by the worker or bridge.
  final String code;

  /// Human-readable error message sent by the worker or bridge.
  final String message;

  @override
  String toString() => 'CindelWebWorkerException($code, $message)';
}

/// Non-Web placeholder for [CindelWebWorkerBridge].
final class CindelWebWorkerBridge {
  /// Throws because the bridge requires Dart Web worker APIs.
  CindelWebWorkerBridge(String workerUrl, {bool module = true}) {
    throw UnsupportedError(
      'CindelWebWorkerBridge is only available on Dart Web.',
    );
  }

  /// Always zero on non-Web targets because no worker can be opened.
  int get pendingCount => 0;

  /// Throws because the bridge requires Dart Web worker APIs.
  Future<void> init() {
    throw UnsupportedError('CindelWebWorkerBridge is only available on Web.');
  }

  /// Throws because the bridge requires Dart Web worker APIs.
  Future<CindelWebWorkerResponse> send({
    required String operation,
    Object? payload,
    List<Object>? transfer,
  }) {
    throw UnsupportedError('CindelWebWorkerBridge is only available on Web.');
  }

  /// Throws because the bridge requires Dart Web worker APIs.
  Future<void> close() {
    throw UnsupportedError('CindelWebWorkerBridge is only available on Web.');
  }
}

/// Returns [objects] unchanged on non-Web targets.
List<Object> cindelWebTransferList(List<Object> objects) => objects;
