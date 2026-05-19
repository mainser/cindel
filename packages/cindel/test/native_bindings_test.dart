import 'dart:io';

import 'package:cindel/cindel.dart';
import 'package:cindel/src/native/bindings.dart';
import 'package:test/test.dart';

void main() {
  group('Cindel native bindings', () {
    // Scenario: The Rust dynamic library is available through native assets.
    // Covers:
    // - The [CindelNativeBindings.abiVersion] FFI call path.
    // - Symbol resolution for `cindel_abi_version`.
    // Expected: Dart receives the current Rust ABI version.
    test('returns the current Rust ABI version.', () {
      // Arrange.
      const bindings = CindelNativeBindings();

      // Act.
      final abiVersion = bindings.abiVersion;

      // Assert.
      expect(abiVersion, 1);
    });

    // Scenario: A database is opened and then closed through the public API.
    // Covers:
    // - [Cindel.open] creating a non-null native engine handle.
    // - [CindelDatabase.close] releasing the native engine handle.
    // - Closed databases rejecting later read operations.
    // Expected: The directory is preserved and later reads throw [StateError].
    test('opens and closes the Rust engine through the public API.', () async {
      // Arrange.
      final directory = await _createDatabaseDirectory();
      addTearDown(() => directory.delete(recursive: true));

      // Act.
      final database = await Cindel.open(directory: directory.path);

      // Assert.
      expect(database.directory, directory.path);

      // Act.
      await database.close();

      // Assert.
      await expectLater(database.get('users', 1), throwsA(isA<StateError>()));
    });
  });
}

/// Creates an isolated directory for tests that open a [Cindel] database.
Future<Directory> _createDatabaseDirectory() {
  return Directory.systemTemp.createTemp('cindel_');
}
