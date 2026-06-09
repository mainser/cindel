import 'package:cindel/cindel_web.dart';
import 'package:test/test.dart';

void main() {
  test('web worker bridge has a non-web stub', () {
    expect(
      () => CindelWebWorkerBridge('worker.js'),
      throwsA(isA<UnsupportedError>()),
    );
  });
}
