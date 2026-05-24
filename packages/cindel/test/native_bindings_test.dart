import 'dart:io';

import 'package:cindel/cindel.dart';
import 'package:cindel/src/native/bindings.dart';
import 'package:test/test.dart';

import 'backend_test_support.dart';

void main() {
  group('Cindel native bindings', () {
    // Scenario: The Rust dynamic library is available through native assets.
    // Covers:
    // - The [CindelNativeBindings.abiVersion] FFI call path.
    // - Symbol resolution for `cindel_abi_version`.
    // Expected: Dart receives the current Rust ABI version.
    test('returns the current Rust ABI version.', () {
      // Arrange.
      final bindings = CindelNativeBindings();

      // Act.
      final abiVersion = bindings.abiVersion;

      // Assert.
      expect(abiVersion, 11);
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
      final database = await openTestDatabase(directory: directory.path);

      // Assert.
      expect(database.directory, directory.path);

      // Act.
      await database.close();

      // Assert.
      await expectLater(database.get('users', 1), throwsA(isA<StateError>()));
    });

    // Scenario: A caller opens a database without selecting a backend.
    // Covers:
    // - [Cindel.openInMemory] default backend selection.
    // - MDBX becoming the public API default.
    // Expected: New database handles use MDBX unless callers request another
    //   backend explicitly.
    test(
      'opens with MDBX as the default backend.',
      () async {
        // Arrange.
        final database = await Cindel.openInMemory();
        addTearDown(database.close);

        // Act.
        await database.put('users', 1, {'name': 'Ana'});
        final storedUser = await database.get('users', 1);

        // Assert.
        expect(defaultCindelStorageBackend, CindelStorageBackend.mdbx);
        expect(database.backend, CindelStorageBackend.mdbx);
        expect(storedUser, {'name': 'Ana'});
      },
      skip: !_runMdbxBackendTests
          ? 'Requires CINDEL_TEST_MDBX=1 and a native library built with mdbx.'
          : false,
    );

    // Scenario: A caller explicitly selects the secondary SQLite backend.
    // Covers:
    // - [Cindel.open] backend option.
    // - FFI open path for SQLite after MDBX became the default.
    // Expected: Explicit SQLite remains available for compatibility.
    test('opens with an explicit SQLite backend.', () async {
      // Arrange.
      final database = await openTestDatabaseInMemory(
        backend: CindelStorageBackend.sqlite,
      );
      addTearDown(database.close);

      // Act.
      await database.put('users', 1, {'name': 'Ana'});
      final storedUser = await database.get('users', 1);

      // Assert.
      expect(database.backend, CindelStorageBackend.sqlite);
      expect(storedUser, {'name': 'Ana'});
    });

    // Scenario: MDBX is selected explicitly for an in-memory test database.
    // Covers:
    // - [Cindel.openInMemory] backend option.
    // - `cindel_open_with_backend` FFI routing.
    // - Basic read/write behavior through MDBX.
    // Expected: MDBX works when the loaded native library was built with the
    //   native `mdbx` Cargo feature.
    test(
      'opens with an explicit MDBX backend.',
      () async {
        // Arrange.
        final database = await openTestDatabaseInMemory(
          backend: CindelStorageBackend.mdbx,
        );
        addTearDown(database.close);

        // Act.
        await database.put('users', 1, {'name': 'Ana'});
        final storedUser = await database.get('users', 1);

        // Assert.
        expect(database.backend, CindelStorageBackend.mdbx);
        expect(storedUser, {'name': 'Ana'});
      },
      skip: !_runMdbxBackendTests
          ? 'Requires CINDEL_TEST_MDBX=1 and a native library built with mdbx.'
          : false,
    );

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
      final database = await openTestDatabase(directory: directory.path);
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

    // Scenario: Multiple documents are written, read, and deleted in batches.
    // Covers:
    // - [CindelDatabase.putMany] alias over the native batch write path.
    // - [CindelDatabase.getAll] ordered reads with nullable misses.
    // - [CindelDatabase.deleteAll] native batch delete path.
    // Expected: Batch writes and deletes affect every requested document.
    test('persists, reads, and deletes documents in batches.', () async {
      // Arrange.
      final database = await openTestDatabaseInMemory();
      addTearDown(database.close);

      // Act.
      await database.putMany('users', {
        1: {'name': 'Ana'},
        2: {'name': 'Ben'},
      });
      final storedUsers = await database.getAll('users', [2, 1, 404]);
      await database.deleteAll('users', [1, 2]);
      final deletedUsers = await database.getAll('users', [1, 2]);

      // Assert.
      expect(storedUsers, [
        {'name': 'Ben'},
        {'name': 'Ana'},
        null,
      ]);
      expect(deletedUsers, [null, null]);
    });

    // Scenario: A batch write includes an invalid document after a valid one.
    // Covers:
    // - [CindelDatabase.putAll] validation before native writes.
    // - No partial writes when public validation fails.
    // Expected: The valid document is not persisted.
    test('does not partially write invalid document batches.', () async {
      // Arrange.
      final database = await openTestDatabaseInMemory();
      addTearDown(database.close);

      // Act.
      final result = database.putAll('users', {
        1: {'name': 'Ana'},
        2: {'createdAt': DateTime(2026)},
      });

      // Assert.
      await expectLater(result, throwsA(isA<ArgumentError>()));
      expect(await database.get('users', 1), isNull);
    });

    // Scenario: A document contains nested JSON-compatible values.
    // Covers:
    // - [CindelDatabase.put] accepting nested maps and lists.
    // - [CindelDatabase.get] decoding nested JSON values from native bytes.
    // Expected: The nested document round-trips without losing structure.
    test('persists nested JSON-compatible documents.', () async {
      // Arrange.
      final directory = await _createDatabaseDirectory();
      addTearDown(() => directory.delete(recursive: true));
      final database = await openTestDatabase(directory: directory.path);
      addTearDown(database.close);
      final document = <String, Object?>{
        'name': 'Noel',
        'tags': ['admin', 'local'],
        'profile': {'score': 42, 'active': true, 'metadata': null},
      };

      // Act.
      await database.put('users', 3, document);
      final storedDocument = await database.get('users', 3);

      // Assert.
      expect(storedDocument, document);
    });

    // Scenario: A document is requested but does not exist.
    // Covers:
    // - Native `not found` status conversion.
    // - [CindelDatabase.get] returning nullable documents.
    // Expected: Missing documents are represented as `null`.
    test('returns null when a document does not exist.', () async {
      // Arrange.
      final directory = await _createDatabaseDirectory();
      addTearDown(() => directory.delete(recursive: true));
      final database = await openTestDatabase(directory: directory.path);
      addTearDown(database.close);

      // Act.
      final missingDocument = await database.get('users', 404);

      // Assert.
      expect(missingDocument, isNull);
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
      final firstDatabase = await openTestDatabase(directory: directory.path);

      // Act.
      await firstDatabase.put('settings', 7, {'theme': 'dark'});
      await firstDatabase.close();
      final secondDatabase = await openTestDatabase(directory: directory.path);
      addTearDown(secondDatabase.close);
      final storedSettings = await secondDatabase.get('settings', 7);

      // Assert.
      expect(storedSettings, {'theme': 'dark'});
    });

    // Scenario: Native ids are allocated and the database is reopened.
    // Covers:
    // - [CindelDatabase.allocateId] FFI path.
    // - SQLite persisted per-collection id counters.
    // - MDBX primary-key-derived counters for collections without documents.
    // Expected: SQLite persists allocate-only counters; MDBX restarts empty
    //   collections from id 1 because PERF-11 keeps allocate-only state in
    //   memory and derives reopened counters from stored document ids.
    test('allocates persistent native ids by collection.', () async {
      // Arrange.
      final directory = await _createDatabaseDirectory();
      addTearDown(() => directory.delete(recursive: true));
      final firstDatabase = await openTestDatabase(directory: directory.path);

      // Act.
      final firstUserId = await firstDatabase.allocateId('users');
      final secondUserId = await firstDatabase.allocateId('users');
      final firstSettingsId = await firstDatabase.allocateId('settings');
      await firstDatabase.close();

      final secondDatabase = await openTestDatabase(directory: directory.path);
      addTearDown(secondDatabase.close);
      final reopenedUserId = await secondDatabase.allocateId('users');

      // Assert.
      expect(firstUserId, 1);
      expect(secondUserId, 2);
      expect(firstSettingsId, 1);
      expect(
        reopenedUserId,
        testStorageBackend == CindelStorageBackend.mdbx ? 1 : 3,
      );
    });

    // Scenario: A manual id is stored before native allocation.
    // Covers:
    // - [CindelDatabase.put] advancing native id counters.
    // - Collision avoidance for later auto-increment writes.
    // Expected: The allocated id is greater than the manual id.
    test('advances allocated ids after manual put.', () async {
      // Arrange.
      final database = await openTestDatabaseInMemory();
      addTearDown(database.close);

      // Act.
      await database.put('users', 10, {'name': 'Ana'});
      final allocatedId = await database.allocateId('users');

      // Assert.
      expect(allocatedId, 11);
    });

    // Scenario: A manual id is stored and the database is reopened.
    // Covers:
    // - MDBX deriving auto-increment counters from stored document primary keys.
    // - SQLite retaining the existing persisted counter behavior.
    // Expected: Reopened databases allocate one greater than the stored max id.
    test('advances allocated ids after reopening stored manual ids.', () async {
      // Arrange.
      final directory = await _createDatabaseDirectory();
      addTearDown(() => directory.delete(recursive: true));
      final firstDatabase = await openTestDatabase(directory: directory.path);

      // Act.
      await firstDatabase.put('users', 10, {'name': 'Ana'});
      await firstDatabase.close();
      final secondDatabase = await openTestDatabase(directory: directory.path);
      addTearDown(secondDatabase.close);
      final allocatedId = await secondDatabase.allocateId('users');

      // Assert.
      expect(allocatedId, 11);
    });

    // Scenario: A database is opened in memory for a short-lived test.
    // Covers:
    // - [Cindel.openInMemory] routing to SQLite in-memory storage.
    // - No persisted state between separate in-memory database handles.
    // Expected: The second in-memory database starts empty.
    test('opens isolated in-memory databases.', () async {
      // Arrange.
      final firstDatabase = await openTestDatabaseInMemory();

      // Act.
      await firstDatabase.put('settings', 7, {'theme': 'dark'});
      final storedSettings = await firstDatabase.get('settings', 7);
      await firstDatabase.close();

      final secondDatabase = await openTestDatabaseInMemory();
      addTearDown(secondDatabase.close);
      final missingSettings = await secondDatabase.get('settings', 7);

      // Assert.
      expect(firstDatabase.directory, ':memory:');
      expect(storedSettings, {'theme': 'dark'});
      expect(missingSettings, isNull);
    });

    // Scenario: The database is closed more than once.
    // Covers:
    // - [CindelDatabase.close] idempotent closed-state handling.
    // - Native close not being called again after the handle is cleared.
    // Expected: Closing twice completes without throwing.
    test('allows closing a database more than once.', () async {
      // Arrange.
      final directory = await _createDatabaseDirectory();
      addTearDown(() => directory.delete(recursive: true));
      final database = await openTestDatabase(directory: directory.path);

      // Act.
      await database.close();
      final secondClose = database.close();

      // Assert.
      await expectLater(secondClose, completes);
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
      final database = await openTestDatabase(directory: directory.path);
      await database.close();

      // Act.
      final putAfterClose = database.put('users', 1, {'name': 'Noel'});
      final deleteAfterClose = database.delete('users', 1);
      final allocateIdAfterClose = database.allocateId('users');

      // Assert.
      await expectLater(putAfterClose, throwsA(isA<StateError>()));
      await expectLater(deleteAfterClose, throwsA(isA<StateError>()));
      await expectLater(allocateIdAfterClose, throwsA(isA<StateError>()));
    });

    // Scenario: Invalid database, collection, and id inputs are provided.
    // Covers:
    // - [Cindel.open] directory validation before FFI.
    // - [CindelDatabase.put], [CindelDatabase.get], and [CindelDatabase.delete]
    //   validating public arguments before FFI.
    // Expected: Invalid public inputs fail with [ArgumentError].
    test('rejects invalid public API inputs before FFI.', () async {
      // Arrange.
      final directory = await _createDatabaseDirectory();
      addTearDown(() => directory.delete(recursive: true));
      final database = await openTestDatabase(directory: directory.path);
      addTearDown(database.close);

      // Act.
      final openWithEmptyDirectory = openTestDatabase(directory: ' ');
      final putWithEmptyCollection = database.put(' ', 1, {'name': 'Noel'});
      final allocateIdWithEmptyCollection = database.allocateId(' ');
      final getWithNegativeId = database.get('users', -1);
      final deleteWithTooLargeId = database.delete('users', 0x8000000000000000);

      // Assert.
      await expectLater(openWithEmptyDirectory, throwsA(isA<ArgumentError>()));
      await expectLater(putWithEmptyCollection, throwsA(isA<ArgumentError>()));
      await expectLater(
        allocateIdWithEmptyCollection,
        throwsA(isA<ArgumentError>()),
      );
      await expectLater(getWithNegativeId, throwsA(isA<ArgumentError>()));
      await expectLater(deleteWithTooLargeId, throwsA(isA<ArgumentError>()));
    });

    // Scenario: A document includes values outside Cindel's JSON contract.
    // Covers:
    // - [CindelDatabase.put] recursive JSON compatibility validation.
    // - Rejection of non-finite numbers and unsupported Dart objects.
    // Expected: Invalid documents fail with [ArgumentError] before FFI.
    test('rejects non JSON-compatible documents before FFI.', () async {
      // Arrange.
      final directory = await _createDatabaseDirectory();
      addTearDown(() => directory.delete(recursive: true));
      final database = await openTestDatabase(directory: directory.path);
      addTearDown(database.close);

      // Act.
      final putWithNonFiniteNumber = database.put('users', 1, {
        'score': double.nan,
      });
      final putWithUnsupportedObject = database.put('users', 2, {
        'createdAt': DateTime(2026),
      });

      // Assert.
      await expectLater(putWithNonFiniteNumber, throwsA(isA<ArgumentError>()));
      await expectLater(
        putWithUnsupportedObject,
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}

/// Creates an isolated directory for tests that open a [Cindel] database.
Future<Directory> _createDatabaseDirectory() {
  return Directory.systemTemp.createTemp('cindel_');
}

bool get _runMdbxBackendTests {
  return Platform.environment['CINDEL_TEST_MDBX'] == '1';
}
