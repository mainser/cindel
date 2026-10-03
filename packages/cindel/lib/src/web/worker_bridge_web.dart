import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

/// Response returned by a Cindel Web worker request.
///
/// The bridge intentionally treats payloads as transport data. Callers decide
/// whether the value is an `ArrayBuffer`, a structured clone object, or another
/// worker-supported value.
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

/// Minimal request/response bridge between Dart Web and a Cindel Worker.
///
/// This class only transports operation names and raw payloads. It does not
/// know about collections, schemas, queries, or database semantics.
final class CindelWebWorkerBridge {
  /// Creates a bridge for [workerUrl].
  ///
  /// By default the worker is created as a JavaScript module worker. Pass
  /// `module: false` only for classic workers.
  CindelWebWorkerBridge(String workerUrl, {bool module = true})
    : _worker = web.Worker(
        workerUrl.toJS,
        web.WorkerOptions(type: module ? 'module' : 'classic'),
      ) {
    _worker.onmessage = ((web.Event event) {
      final data = (event as web.MessageEvent).data;
      if (data == null) return;
      _handleMessage(_CindelWebWorkerMessage._(data as JSObject));
    }).toJS;
    _worker.onerror = ((web.Event _) {
      _handleTransportFailure(
        const CindelWebWorkerException('worker_error', 'Worker error event.'),
      );
    }).toJS;
    _worker.onmessageerror = ((web.Event _) {
      _handleTransportFailure(
        const CindelWebWorkerException(
          'message_error',
          'Worker message could not be deserialized.',
        ),
      );
    }).toJS;
  }

  final web.Worker _worker;
  final _pending = <int, Completer<CindelWebWorkerResponse>>{};
  Completer<void>? _readyCompleter;
  Completer<void>? _closedCompleter;
  Future<void>? _closeFuture;
  CindelWebWorkerException? _closeFailure;
  Future<void> _queue = Future<void>.value();
  int _nextRequestId = 1;
  bool _closed = false;
  bool _terminated = false;

  /// Number of requests currently waiting for a worker response.
  int get pendingCount => _pending.length;

  /// Sends the bridge init message and completes when the worker reports ready.
  Future<void> init() {
    if (_closed) {
      return Future<void>.error(
        const CindelWebWorkerException('closed', 'Worker bridge is closed.'),
      );
    }

    final ready = _readyCompleter ??= Completer<void>();
    _worker.postMessage(_CindelWebWorkerMessage(type: 'init'));
    return ready.future;
  }

  /// Sends one transport operation to the worker.
  ///
  /// Requests are serialized before they enter the worker so callers may issue
  /// concurrent Dart futures without allowing simultaneous engine entry. Pass
  /// transferable payload objects, such as an `ArrayBuffer`, through [transfer]
  /// when ownership can move to the worker without copying.
  Future<CindelWebWorkerResponse> send({
    required String operation,
    Object? payload,
    List<Object>? transfer,
  }) {
    if (_closed) {
      return Future<CindelWebWorkerResponse>.error(
        const CindelWebWorkerException('closed', 'Worker bridge is closed.'),
      );
    }

    final request = _queue.then(
      (_) =>
          _sendNow(operation: operation, payload: payload, transfer: transfer),
    );
    _queue = request.then<void>((_) {}, onError: (_) {});
    return request;
  }

  /// Closes the bridge after requests already admitted have completed.
  ///
  /// New requests are rejected immediately. Repeated calls share completion,
  /// including a worker cleanup failure, and terminate the worker only once.
  Future<void> close() => _closeFuture ??= _close().timeout(
    const Duration(seconds: 2),
    onTimeout: () {
      // Bound both the admitted-request drain and the closed acknowledgement.
      // Termination is observable as a failure, not an unconfirmed clean close.
      _closeFailure ??= const CindelWebWorkerException(
        'close_timeout',
        'Worker shutdown timed out; the worker was terminated.',
      );
      _failOpenRequests(_closeFailure!);
      _completeClosed();
      throw _closeFailure!;
    },
  );

  Future<void> _close() async {
    _closed = true;
    final closed = _closedCompleter = Completer<void>();
    // Queued requests belong to their original callers. Let their real storage
    // results settle before closing instead of turning successful writes into
    // transport errors or dropping accepted requests that have not been posted.
    await Future.wait<void>([
      _queue.then<void>((_) {
        if (!_terminated) {
          _worker.postMessage(_CindelWebWorkerMessage(type: 'close'));
        }
      }),
      // Observe the acknowledgement immediately, including failures while an
      // admitted request is still draining, so shutdown errors stay handled.
      closed.future,
    ], eagerError: true);
  }

  Future<CindelWebWorkerResponse> _sendNow({
    required String operation,
    required Object? payload,
    required List<Object>? transfer,
  }) {
    // send() already admitted this request. close() waits for the queue, so the
    // worker remains available even if new requests are now being rejected.
    if (_terminated) {
      return Future<CindelWebWorkerResponse>.error(
        _closeFailure ??
            const CindelWebWorkerException(
              'closed',
              'Worker bridge is closed.',
            ),
      );
    }
    final requestId = _nextRequestId++;
    final completer = Completer<CindelWebWorkerResponse>();
    _pending[requestId] = completer;
    final message = _CindelWebWorkerMessage(
      type: 'request',
      requestId: requestId,
      operation: operation,
      payload: payload as JSAny?,
    );
    final transferList = _toJsTransferList(transfer);
    if (transfer == null) {
      _worker.postMessage(message);
    } else {
      _worker.callMethod<JSAny?>('postMessage'.toJS, message, transferList!);
    }
    return completer.future;
  }

  void _handleMessage(_CindelWebWorkerMessage message) {
    switch (message.type) {
      case 'ready':
        _completeReady();
      case 'closed':
        _completeClosed();
      case 'response':
        _completeRequest(message);
      case 'error':
        _completeError(message);
    }
  }

  void _completeReady() {
    final ready = _readyCompleter;
    if (ready != null && !ready.isCompleted) {
      ready.complete();
    }
  }

  void _completeClosed() {
    final closed = _closedCompleter;
    if (closed != null && !closed.isCompleted) {
      if (!_terminated) {
        _terminated = true;
        _worker.terminate();
      }
      final failure = _closeFailure;
      if (failure == null) {
        closed.complete();
      } else {
        closed.completeError(failure);
      }
    }
  }

  void _completeRequest(_CindelWebWorkerMessage message) {
    final requestId = message.requestId;
    if (requestId == null) return;
    final completer = _pending.remove(requestId);
    if (completer == null || completer.isCompleted) return;
    completer.complete(CindelWebWorkerResponse(payload: message.payload));
  }

  void _completeError(_CindelWebWorkerMessage message) {
    final error = message.error;
    final exception = CindelWebWorkerException(
      error?.code ?? 'worker_error',
      error?.message ?? 'Worker request failed.',
    );
    final requestId = message.requestId;
    if (requestId == null || requestId == 0) {
      if (_closedCompleter != null && exception.code == 'close_failed') {
        // The worker still owes its closed acknowledgement. Retain the error
        // until that acknowledgement confirms cleanup and termination.
        _closeFailure ??= exception;
        return;
      }
      _completeReadyWithError(exception);
      _failOpenRequests(exception);
      return;
    }

    final completer = _pending.remove(requestId);
    if (completer != null && !completer.isCompleted) {
      completer.completeError(exception);
    }
  }

  void _completeReadyWithError(CindelWebWorkerException exception) {
    final ready = _readyCompleter;
    if (ready != null && !ready.isCompleted) {
      ready.completeError(exception);
    }
  }

  void _handleTransportFailure(CindelWebWorkerException exception) {
    _failOpenRequests(exception);
    if (_closedCompleter != null) {
      _closeFailure ??= exception;
      _completeClosed();
    }
  }

  void _failOpenRequests(CindelWebWorkerException exception) {
    _completeReadyWithError(exception);
    final pending = List<Completer<CindelWebWorkerResponse>>.from(
      _pending.values,
    );
    _pending.clear();
    for (final completer in pending) {
      if (!completer.isCompleted) {
        completer.completeError(exception);
      }
    }
  }
}

/// Returns [objects] in the shape expected by [CindelWebWorkerBridge.send].
///
/// This helper keeps application code independent from the conditional Web
/// implementation while still allowing transfer lists for `postMessage`.
List<Object> cindelWebTransferList(List<Object> objects) => objects;

JSArray<JSObject>? _toJsTransferList(List<Object>? transfer) {
  if (transfer == null) return null;
  return <JSObject>[for (final object in transfer) object as JSObject].toJS;
}

extension type _CindelWebWorkerMessage._(JSObject _) implements JSObject {
  external factory _CindelWebWorkerMessage({
    required String type,
    int? requestId,
    String? operation,
    JSAny? payload,
  });

  external String get type;
  external int? get requestId;
  external JSAny? get payload;
  external _CindelWebWorkerError? get error;
}

extension type _CindelWebWorkerError._(JSObject _) implements JSObject {
  external String? get code;
  external String? get message;
}
