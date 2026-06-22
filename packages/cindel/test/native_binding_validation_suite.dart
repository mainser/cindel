import 'dart:ffi';
import 'dart:typed_data';

import 'package:cindel/src/native/bindings.dart';
import 'package:test/test.dart';

void main() {
  group('Cindel native binding validations', () {
    // Scenario: Native document batch writes receive a mismatched id list.
    // Covers:
    // - `CindelNativeBindings.putManyNativeDocuments` id-count guard.
    // Expected: The binding rejects the call before allocating native writers.
    test('rejects native document batches with mismatched id counts.', () {
      // Arrange.
      final bindings = CindelNativeBindings();

      // Act / Assert.
      expect(
        () => bindings.putManyNativeDocuments<Object>(
          nullptr,
          'users',
          Uint8List(0),
          const [1],
          const <Object>[],
          (_, _) {},
          true,
          false,
        ),
        throwsA(
          isA<ArgumentError>()
              .having((error) => error.name, 'name', 'ids')
              .having(
                (error) => error.message,
                'message',
                'Must match the object count.',
              ),
        ),
      );
    });

    // Scenario: Migration metadata writes receive a negative version.
    // Covers:
    // - `CindelNativeBindings.setMigrationVersion` negative version guard.
    // Expected: The binding rejects the call before invoking native storage.
    test('rejects negative migration versions before FFI calls.', () {
      // Arrange.
      final bindings = CindelNativeBindings();

      // Act / Assert.
      expect(
        () => bindings.setMigrationVersion(nullptr, -1),
        throwsA(
          isA<ArgumentError>()
              .having((error) => error.name, 'name', 'version')
              .having(
                (error) => error.message,
                'message',
                'Must not be negative.',
              ),
        ),
      );
    });
  });
}
