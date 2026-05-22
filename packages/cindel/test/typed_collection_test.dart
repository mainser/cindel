import 'dart:async';
import 'dart:io';

import 'package:cindel/cindel.dart';
import 'package:test/test.dart';

import 'backend_test_support.dart';

import 'schema_generation_fixture.dart';

void main() {
  group('Cindel typed collections', () {
    // Scenario: A generated collection accessor is used for typed CRUD.
    // Covers:
    // - Generated [CindelDatabase.users] accessor.
    // - [CindelTypedCollection.put] mapping typed objects into documents.
    // - [CindelTypedCollection.get] mapping documents back into typed objects.
    // - [CindelTypedCollection.delete] removing the stored object.
    // Expected: The typed API can store, read, update, and delete a user.
    test('stores, reads, updates, and deletes typed objects.', () async {
      // Arrange.
      final directory = await _createDatabaseDirectory();
      addTearDown(() => directory.delete(recursive: true));
      final database = await openTestDatabase(
        directory: directory.path,
        schemas: [UserSchema],
      );
      addTearDown(database.close);
      final user = User()
        ..id = 1
        ..name = 'Ana'
        ..email = 'ana@example.com'
        ..active = true;

      // Act.
      await database.users.put(user);
      final savedUser = await database.users.get(1);
      user.name = 'Ana Maria';
      await database.users.put(user);
      final updatedUser = await database.users.get(1);
      await database.users.delete(1);
      final deletedUser = await database.users.get(1);

      // Assert.
      expect(savedUser, isNotNull);
      expect(savedUser!.name, 'Ana');
      expect(savedUser.email, 'ana@example.com');
      expect(savedUser.active, isTrue);
      expect(updatedUser, isNotNull);
      expect(updatedUser!.name, 'Ana Maria');
      expect(deletedUser, isNull);
    });

    // Scenario: A generated model keeps the autoIncrement sentinel id.
    // Covers:
    // - [CindelTypedCollection.put] detecting `autoIncrement`.
    // - Native id allocation through the typed API.
    // - Generated id setter mutating the model before persistence.
    // Expected: The object receives a real id and can be read by that id.
    test('assigns native auto-increment ids to typed objects.', () async {
      // Arrange.
      final database = await openTestDatabaseInMemory(schemas: [UserSchema]);
      addTearDown(database.close);
      final firstUser = User()
        ..name = 'Ana'
        ..email = 'ana@example.com'
        ..active = true;
      final secondUser = User()
        ..name = 'Ben'
        ..email = 'ben@example.com'
        ..active = false;

      // Act.
      await database.users.put(firstUser);
      await database.users.put(secondUser);
      final savedFirstUser = await database.users.get(firstUser.id);
      final savedSecondUser = await database.users.get(secondUser.id);

      // Assert.
      expect(firstUser.id, 1);
      expect(secondUser.id, 2);
      expect(savedFirstUser!.name, 'Ana');
      expect(savedSecondUser!.name, 'Ben');
    });

    // Scenario: Multiple generated objects are saved, read, and deleted.
    // Covers:
    // - [CindelTypedCollection.putMany] generated document mapping.
    // - Auto-increment assignment during typed bulk writes.
    // - [CindelTypedCollection.getAll] ordered nullable reads.
    // - [CindelTypedCollection.deleteAll] native batch delete path.
    // Expected: Bulk typed operations round-trip generated objects.
    test('stores, reads, and deletes typed objects in batches.', () async {
      // Arrange.
      final database = await openTestDatabaseInMemory(schemas: [UserSchema]);
      addTearDown(database.close);
      final ana = User()
        ..name = 'Ana'
        ..email = 'ana@example.com';
      final ben = User()
        ..name = 'Ben'
        ..email = 'ben@example.com';

      // Act.
      await database.users.putMany([ana, ben]);
      final storedUsers = await database.users.getAll([ben.id, ana.id, 404]);
      await database.users.deleteAll([ana.id, ben.id]);
      final deletedUsers = await database.users.getAll([ana.id, ben.id]);

      // Assert.
      expect([ana.id, ben.id], [1, 2]);
      expect(storedUsers.map((user) => user?.name), ['Ben', 'Ana', null]);
      expect(deletedUsers, [null, null]);
    });

    // Scenario: A typed bulk write receives duplicate explicit ids.
    // Covers:
    // - [CindelTypedCollection.putAll] preflight duplicate id validation.
    // - Avoiding partial native writes when generated objects are invalid.
    // Expected: Nothing is persisted from the invalid batch.
    test('rejects typed bulk writes with duplicate ids.', () async {
      // Arrange.
      final database = await openTestDatabaseInMemory(schemas: [UserSchema]);
      addTearDown(database.close);
      final firstUser = User()
        ..id = 7
        ..name = 'Ana'
        ..email = 'ana@example.com';
      final secondUser = User()
        ..id = 7
        ..name = 'Ben'
        ..email = 'ben@example.com';

      // Act.
      final result = database.users.putAll([firstUser, secondUser]);

      // Assert.
      await expectLater(result, throwsA(isA<ArgumentError>()));
      expect(await database.users.get(7), isNull);
    });

    // Scenario: Generated typed watchers observe collection and object changes.
    // Covers:
    // - [CindelTypedCollection.watchCollection] typed snapshots.
    // - [CindelTypedCollection.watchObject] typed snapshots.
    // - Local post-commit notifications through the typed collection API.
    // Expected: Watchers emit typed values after put and delete operations.
    test('emits typed object and collection watcher snapshots.', () async {
      // Arrange.
      final directory = await _createDatabaseDirectory();
      addTearDown(() => directory.delete(recursive: true));
      final database = await openTestDatabase(
        directory: directory.path,
        schemas: [UserSchema],
      );
      addTearDown(database.close);
      final collectionEvents = <List<User>>[];
      final objectEvents = <User?>[];
      final collectionSubscription = database.users
          .watchCollection(pollInterval: const Duration(milliseconds: 5))
          .listen(collectionEvents.add);
      final objectSubscription = database.users
          .watchObject(1, pollInterval: const Duration(milliseconds: 5))
          .listen(objectEvents.add);
      addTearDown(collectionSubscription.cancel);
      addTearDown(objectSubscription.cancel);
      final user = User()
        ..id = 1
        ..name = 'Ben'
        ..email = 'ben@example.com'
        ..active = false;

      // Act.
      await _waitUntil(() => collectionEvents.length == 1);
      await _waitUntil(() => objectEvents.length == 1);
      await database.users.put(user);
      await _waitUntil(
        () => collectionEvents.any((users) => users.length == 1),
      );
      await _waitUntil(() => objectEvents.any((event) => event != null));
      await database.users.delete(1);
      await _waitUntil(() => objectEvents.length >= 3);

      // Assert.
      final latestNonEmptyCollection = collectionEvents.lastWhere(
        (users) => users.isNotEmpty,
      );
      expect(collectionEvents.first, isEmpty);
      expect(latestNonEmptyCollection.single.name, 'Ben');
      expect(objectEvents.first, isNull);
      expect(objectEvents[1]!.name, 'Ben');
      expect(objectEvents.last, isNull);
    });

    // Scenario: A typed object serializer produces an invalid id field.
    // Covers:
    // - [CindelTypedCollection.put] id extraction from schema metadata.
    // - Defensive typed API validation before manual document writes.
    // Expected: Invalid generated id data fails with a [StateError].
    test('rejects typed objects with non-int id values.', () async {
      // Arrange.
      final directory = await _createDatabaseDirectory();
      addTearDown(() => directory.delete(recursive: true));
      final database = await openTestDatabase(directory: directory.path);
      addTearDown(database.close);
      final schema = CindelCollectionSchema<_BrokenUser>(
        name: 'brokenUsers',
        dartName: 'BrokenUser',
        idField: 'id',
        fields: const [
          CindelFieldSchema(
            name: 'id',
            dartType: 'String',
            isId: true,
            isIndexed: false,
          ),
        ],
        toDocument: (_) => {'id': 'oops'},
        fromDocument: (_) => const _BrokenUser(),
      );

      // Act.
      Future<void> putInvalidObject() {
        return database.typedCollection(schema).put(const _BrokenUser());
      }

      // Assert.
      expect(putInvalidObject, throwsA(isA<StateError>()));
    });

    // Scenario: A hand-written schema returns the autoIncrement sentinel but
    // has no generated id setter.
    // Covers:
    // - Defensive validation before native id allocation.
    // - Clear failure for incomplete schema metadata.
    // Expected: The typed write fails with [StateError].
    test('rejects auto-increment schemas without id setters.', () async {
      // Arrange.
      final database = await openTestDatabaseInMemory();
      addTearDown(database.close);
      final schema = CindelCollectionSchema<_ManualAutoUser>(
        name: 'manualAutoUsers',
        dartName: 'ManualAutoUser',
        idField: 'id',
        fields: const [
          CindelFieldSchema(
            name: 'id',
            dartType: 'int',
            isId: true,
            isIndexed: false,
          ),
        ],
        toDocument: (_) => {'id': autoIncrement},
        fromDocument: (_) => const _ManualAutoUser(),
      );

      // Act.
      Future<void> putInvalidObject() {
        return database.typedCollection(schema).put(const _ManualAutoUser());
      }

      // Assert.
      expect(putInvalidObject, throwsA(isA<StateError>()));
    });
  });
}

final class _BrokenUser {
  const _BrokenUser();
}

final class _ManualAutoUser {
  const _ManualAutoUser();
}

Future<void> _waitUntil(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 2),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('Timed out waiting for watcher event.');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

Future<Directory> _createDatabaseDirectory() {
  return Directory.systemTemp.createTemp('cindel_');
}
