import 'package:cindel/src/web/worker_bridge.dart';
import 'package:test/test.dart';

void main() {
  // Scenario: Non-Web Dart reaches the internal worker bridge facade.
  // Covers:
  // - Conditional export stub for the internal worker bridge.
  // - Keeping VM/native test environments analyzer-safe without Web APIs.
  // Expected: Constructing the Web worker bridge outside Web throws a clear
  // UnsupportedError instead of touching browser-only APIs.
  test('web worker bridge has a non-web stub', () {
    // Act / Assert.
    expect(
      () => CindelWebWorkerBridge('worker.js'),
      throwsA(isA<UnsupportedError>()),
    );
  });
}
