import 'dart:async';
import 'dart:js_interop';

import 'package:cindel/src/web/worker_bridge.dart';
import 'package:test/test.dart';

const _deadline = Duration(seconds: 10);

void main() {
  group('Web Worker closure', () {
    // Scenario: a healthy Worker receives two requests before shutdown.
    // Covers:
    // - Draining accepted requests in their original admission order.
    // - Concurrent and later close calls sharing one successful Future.
    // - New requests rejected and transport resources released.
    // Expected: both replies keep their real result and closure succeeds once.
    test('drains admitted requests and shares successful closure.', () async {
      // Arrange.
      final bridge = await _openBridge('normal');
      final firstRequest = _Observed(bridge.send(operation: 'first'));
      final secondRequest = _Observed(bridge.send(operation: 'second'));

      // Act. Attach every observer before yielding to the browser event loop.
      final firstFuture = bridge.close();
      final first = _Observed(firstFuture);
      final secondFuture = bridge.close();
      final second = _Observed(secondFuture);
      final rejected = _Observed(bridge.send(operation: 'after-close'));
      await Future.wait<void>([
        firstRequest.done,
        secondRequest.done,
        first.done,
        second.done,
        rejected.done,
      ]).timeout(_deadline);
      final lateFuture = bridge.close();
      final late = _Observed(lateFuture);
      await late.done.timeout(_deadline);

      // Assert. The fixture numbers requests as the Worker actually receives
      // them, independently of Dart's call-site order and queue implementation.
      expect(firstRequest.error, isNull);
      expect(secondRequest.error, isNull);
      expect(_replyText(firstRequest.value!), '0:first');
      expect(_replyText(secondRequest.value!), '1:second');
      expect(identical(firstFuture, secondFuture), isTrue);
      expect(identical(firstFuture, lateFuture), isTrue);
      expect([first.error, second.error, late.error], everyElement(isNull));
      expect(rejected.error, isA<CindelWebWorkerException>());
      expect((rejected.error! as CindelWebWorkerException).code, 'closed');
      expect(bridge.pendingCount, 0);
    });

    final failureModes = <String, String>{
      'close-error-ack': 'preserves cleanup failure after acknowledgement.',
      'close-error-no-ack': 'preserves cleanup failure after timeout.',
      'silent-request': 'settles active and queued requests after timeout.',
      'close-no-ack': 'reports timeout when closure is not acknowledged.',
    };
    for (final entry in failureModes.entries) {
      // Scenario: a real Worker reports failure, omits its close acknowledgement,
      // or leaves an admitted request awaiting a reply.
      // Covers:
      // - A bounded cleanup result shared by concurrent and later callers.
      // - The first cleanup error preserved when acknowledgement is missing.
      // - Active and queued requests settled before teardown finishes.
      // - New calls rejected and the pending request map emptied.
      // Expected: one clear failure reaches all close callers; admitted healthy
      // requests retain successful replies and stalled requests report timeout.
      test(entry.value, () async {
        // Arrange.
        final mode = entry.key;
        final bridge = await _openBridge(mode);
        final requests = [
          _Observed(bridge.send(operation: 'first')),
          _Observed(bridge.send(operation: 'second')),
        ];
        if (mode == 'silent-request') {
          // Flush admission so one request is posted and the other remains
          // queued behind it when the bounded shutdown begins.
          await Future<void>.microtask(() {});
          expect(bridge.pendingCount, 1);
        }

        // Act.
        final firstFuture = bridge.close();
        final first = _Observed(firstFuture);
        final secondFuture = bridge.close();
        final second = _Observed(secondFuture);
        final rejected = _Observed(bridge.send(operation: 'after-close'));
        await Future.wait<void>([
          first.done,
          second.done,
          rejected.done,
          for (final request in requests) request.done,
        ]).timeout(_deadline);
        final lateFuture = bridge.close();
        final late = _Observed(lateFuture);
        await late.done.timeout(_deadline);

        // Assert. Timeout must retain an already reported cleanup failure.
        expect(identical(firstFuture, secondFuture), isTrue);
        expect(identical(firstFuture, lateFuture), isTrue);
        expect(first.error, isA<CindelWebWorkerException>());
        expect(identical(first.error, second.error), isTrue);
        expect(identical(first.error, late.error), isTrue);
        final expectedCode = mode.startsWith('close-error')
            ? 'close_failed'
            : 'close_timeout';
        expect((first.error! as CindelWebWorkerException).code, expectedCode);
        if (mode.startsWith('close-error')) {
          expect(
            (first.error! as CindelWebWorkerException).message,
            'Controlled worker cleanup failure.',
          );
        }
        expect(rejected.error, isA<CindelWebWorkerException>());
        expect((rejected.error! as CindelWebWorkerException).code, 'closed');
        expect(requests.every((request) => request.finished), isTrue);
        expect(bridge.pendingCount, 0);
        if (mode == 'silent-request') {
          expect(
            requests.every((request) => identical(request.error, first.error)),
            isTrue,
          );
        } else {
          expect(
            requests.map((request) => request.error),
            everyElement(isNull),
          );
          expect(_replyText(requests[0].value!), '0:first');
          expect(_replyText(requests[1].value!), '1:second');
        }
      });
    }
  }, timeout: const Timeout(Duration(seconds: 30)));
}

/// Starts a real Worker with controlled protocol responses for transport tests.
Future<CindelWebWorkerBridge> _openBridge(String mode) async {
  final bridge = CindelWebWorkerBridge(
    'fixtures/close_transport_worker.js?mode=${Uri.encodeQueryComponent(mode)}',
  );
  addTearDown(() async {
    // Failed closure is expected in the fault cases. Observe the cached Future
    // again so an earlier assertion cannot leave cleanup errors unhandled.
    final cleanup = _Observed(bridge.close());
    await cleanup.done.timeout(_deadline);
    if (mode == 'normal') expect(cleanup.error, isNull);
  });
  await bridge.init().timeout(_deadline);
  return bridge;
}

String _replyText(CindelWebWorkerResponse response) =>
    (response.payload! as JSString).toDart;

/// Attaches an error handler immediately while retaining the actual outcome.
final class _Observed<T> {
  _Observed(Future<T> future) {
    done = future.then<void>(
      (result) {
        value = result;
        finished = true;
      },
      onError: (Object caughtError, StackTrace _) {
        error = caughtError;
        finished = true;
      },
    );
  }

  late final Future<void> done;
  bool finished = false;
  T? value;
  Object? error;
}
