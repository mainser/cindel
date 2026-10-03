// VM-only tests use mirrors to exercise the private native ABI check.
// ignore_for_file: uri_does_not_exist, undefined_function, undefined_identifier

import 'dart:mirrors';

import 'package:cindel/src/cindel_error.dart';
import 'package:cindel/src/native/bindings.dart';
import 'package:test/test.dart';

void main() {
  group('Cindel native ABI compatibility', () {
    // Scenario: The native library reports the ABI expected by these bindings.
    // Covers:
    // - Exact ABI 34 acceptance by the shared compatibility check.
    // Expected: Validation returns normally without loading a native library.
    test('accepts the exact native ABI version.', () {
      // Arrange.
      const version = 34;

      // Act / Assert.
      expect(() => _checkAbi(version), returnsNormally);
    });

    for (final version in [0, 33, 35, 0xffffffff]) {
      // Scenario: The native library reports an ABI different from ABI 34.
      // Covers:
      // - Older and newer ABIs, including the uint32 boundary values.
      // - CindelNativeError with the expected ABI, actual ABI, and corrective
      //   guidance for selecting a matching native library.
      // Expected: Each incompatible ABI is rejected with the exact message.
      test('rejects native ABI $version with the required version.', () {
        // Arrange.
        final expectedMessage =
            'Incompatible Cindel native ABI: expected 34, '
            'found $version. Load a native library matching this Cindel package.';

        // Act / Assert.
        expect(
          () => _checkAbi(version),
          throwsA(
            isA<CindelNativeError>().having(
              (error) => error.message,
              'message',
              expectedMessage,
            ),
          ),
        );
      });
    }
  });
}

// Exercise the private compatibility check without constructing bindings or
// loading a DLL. Mirrors keep this VM-only test independent of native fixtures
// without adding a public testing entrypoint to the binding API.
void _checkAbi(int version) {
  expect(CindelNativeBindings, isNotNull);
  final library = currentMirrorSystem()
      .libraries[Uri.parse('package:cindel/src/native/bindings.dart')];
  if (library == null) {
    fail('Could not find package:cindel/src/native/bindings.dart.');
  }
  library.invoke(MirrorSystem.getSymbol('_checkNativeAbi', library), [version]);
}
