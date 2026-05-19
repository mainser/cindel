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

    // Scenario: A document is written, read, and deleted from SQLite storage.
    // Covers:
    // - [CindelDatabase.put] serializing Dart maps into native bytes.
    // - [CindelDatabase.get] reading native bytes back into Dart maps.
    // - [CindelDatabase.delete] removing documents by collection and id.
    // Expected: The document round-trips once and is missing after deletion.
    test('persists and deletes a document through the public API.', () async {
      // Arrange.
      final directory = await _createDatabaseDirectory();
      addTearDown(() => directory.delete(recursive: true));
      final database = await Cindel.open(directory: directory.path);
      addTearDown(database.close);
      final user = <String, Object?>{'name': 'Noel', 'age': 34, 'active': true};

      // Act.
      await database.put('users', 1, user);
      final storedUser = await database.get('users', 1);

      // Assert.
      expect(storedUser, user);

      // Act.
      await database.delete('users', 1);
      final deletedUser = await database.get('users', 1);

      // Assert.
      expect(deletedUser, isNull);
    });

    // Scenario: A database directory is closed and opened again.
    // Covers:
    // - SQLite-backed storage writing bytes to disk.
    // - [Cindel.open] reusing an existing database file.
    // Expected: Documents remain readable after reopening the same directory.
    test('keeps documents after reopening the same directory.', () async {
      // Arrange.
      final directory = await _createDatabaseDirectory();
      addTearDown(() => directory.delete(recursive: true));
      final firstDatabase = await Cindel.open(directory: directory.path);

      // Act.
      await firstDatabase.put('settings', 7, {'theme': 'dark'});
      await firstDatabase.close();
      final secondDatabase = await Cindel.open(directory: directory.path);
      addTearDown(secondDatabase.close);
      final storedSettings = await secondDatabase.get('settings', 7);

      // Assert.
      expect(storedSettings, {'theme': 'dark'});
    });

    // Scenario: Write operations are requested after closing a database.
    // Covers:
    // - [CindelDatabase.put] checking handle state before FFI.
    // - [CindelDatabase.delete] checking handle state before FFI.
    // Expected: Closed databases reject write and delete operations.
    test('rejects writes and deletes after close.', () async {
      // Arrange.
      final directory = await _createDatabaseDirectory();
      addTearDown(() => directory.delete(recursive: true));
      final database = await Cindel.open(directory: directory.path);
      await database.close();

      // Act.
      final putAfterClose = database.put('users', 1, {'name': 'Noel'});
      final deleteAfterClose = database.delete('users', 1);

      // Assert.
      await expectLater(putAfterClose, throwsA(isA<StateError>()));
      await expectLater(deleteAfterClose, throwsA(isA<StateError>()));
    });
  });
}

/// Creates an isolated directory for tests that open a [Cindel] database.
Future<Directory> _createDatabaseDirectory() {
  return Directory.systemTemp.createTemp('cindel_');
}
