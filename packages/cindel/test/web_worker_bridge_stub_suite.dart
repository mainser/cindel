import 'package:cindel/src/web/worker_bridge.dart';
import 'package:test/test.dart';

void main() {
  group('Cindel Web worker bridge stub', () {
    // Scenario: Non-Web Dart reaches the internal worker bridge facade.
    // Covers:
    // - Conditional export stub for the internal worker bridge.
    // - Keeping VM/native test environments analyzer-safe without Web APIs.
    // Expected: Constructing the Web worker bridge outside Web throws a clear
    // UnsupportedError instead of touching browser-only APIs.
    test('throws when constructed on non-Web targets.', () {
      // Act / Assert.
      expect(
        () => CindelWebWorkerBridge('worker.js'),
        throwsA(isA<UnsupportedError>()),
      );
    });

    // Scenario: Stub response and exception value objects are used by code that
    // can be analyzed on native targets.
    // Covers:
    // - [CindelWebWorkerResponse] payload storage.
    // - [CindelWebWorkerException] code/message storage.
    // - [CindelWebWorkerException.toString].
    // Expected: Value objects keep the same observable contract outside Web.
    test('exposes response and exception value objects.', () {
      // Arrange.
      const response = CindelWebWorkerResponse(payload: {'ok': true});
      const exception = CindelWebWorkerException('boom', 'Worker failed');

      // Assert.
      expect(response.payload, {'ok': true});
      expect(exception.code, 'boom');
      expect(exception.message, 'Worker failed');
      expect(
        exception.toString(),
        'CindelWebWorkerException(boom, Worker failed)',
      );
    });

    // Scenario: Non-Web code asks for a transfer-list shape.
    // Covers:
    // - [cindelWebTransferList] native stub branch.
    // Expected: Native targets keep the same object list unchanged.
    test('returns transfer lists unchanged on non-Web targets.', () {
      // Arrange.
      final transfer = <Object>[Object(), 'bytes'];

      // Act.
      final result = cindelWebTransferList(transfer);

      // Assert.
      expect(identical(result, transfer), isTrue);
    });
  });
}
