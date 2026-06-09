import 'package:cindel/cindel_web.dart';
import 'package:test/test.dart';

void main() {
  // Scenario: Non-Web Dart imports the separate Web entrypoint.
  // Covers:
  // - Conditional export fallback for `package:cindel/cindel_web.dart`.
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
