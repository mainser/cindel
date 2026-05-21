import 'dart:async';
import 'dart:io';

import 'package:cindel/cindel.dart';
import 'package:test/test.dart';

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
      final database = await Cindel.open(
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
      final database = await Cindel.open(
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
      final database = await Cindel.open(directory: directory.path);
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
  });
}

final class _BrokenUser {
  const _BrokenUser();
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
