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
        ..dbId = 1
        ..name = 'Ana'
        ..email = 'ana@example.com'
        ..active = true;

      // Act.
      await database.users.put(user);
      final storedBinaryBytes = testStorageBackend == CindelStorageBackend.mdbx
          ? await database.getBinaryDocument('users', 1)
          : null;
      final savedUser = await database.users.get(1);
      user.name = 'Ana Maria';
      await database.users.put(user);
      final updatedUser = await database.users.get(1);
      await database.users.delete(1);
      final deletedUser = await database.users.get(1);

      // Assert.
      expect(savedUser, isNotNull);
      if (testStorageBackend == CindelStorageBackend.mdbx) {
        expect(storedBinaryBytes, isNotNull);
        expect(storedBinaryBytes!.take(3), [61, 0, 0]);
      }
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
      final savedFirstUser = await database.users.get(firstUser.dbId);
      final savedSecondUser = await database.users.get(secondUser.dbId);

      // Assert.
      expect(firstUser.dbId, 1);
      expect(secondUser.dbId, 2);
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
      final storedUsers = await database.users.getAll([
        ben.dbId,
        ana.dbId,
        404,
      ]);
      await database.users.deleteAll([ana.dbId, ben.dbId]);
      final deletedUsers = await database.users.getAll([ana.dbId, ben.dbId]);

      // Assert.
      expect([ana.dbId, ben.dbId], [1, 2]);
      expect(storedUsers.map((user) => user?.name), ['Ben', 'Ana', null]);
      expect(deletedUsers, [null, null]);
    });

    // Scenario: Bulk typed writes receive a lazy iterable rather than a List.
    // Covers:
    // - [CindelTypedCollection.putMany] aliasing [putAll].
    // - [CindelTypedCollection.putAll] materializing non-List iterables.
    // Expected: Lazy iterables are stored exactly like List batches.
    test('stores typed objects from lazy iterables.', () async {
      // Arrange.
      final database = await openTestDatabaseInMemory(schemas: [UserSchema]);
      addTearDown(database.close);

      Iterable<User> users() sync* {
        yield User()
          ..name = 'Ana'
          ..email = 'ana@example.com';
        yield User()
          ..name = 'Ben'
          ..email = 'ben@example.com';
      }

      // Act.
      await database.users.putMany(users());
      final stored = await database.users.all().sortByEmail().findAll();

      // Assert.
      expect(stored.map((user) => user.email), [
        'ana@example.com',
        'ben@example.com',
      ]);
      expect(stored.map((user) => user.dbId), [1, 2]);
    });

    // Scenario: A generated replace index helper upserts by natural key.
    // Covers:
    // - Generated [putByUsername] method for a unique replace index.
    // - Reusing the existing document id before persistence.
    // - Persisted field name lookup through the generated index metadata.
    // Expected: The replacement object receives the existing id and overwrites
    //   that document without a query in user code.
    test('reuses ids when putting by a unique replace index.', () async {
      // Arrange.
      final database = await openTestDatabaseInMemory(schemas: [AccountSchema]);
      addTearDown(database.close);
      final existing = Account()
        ..username = 'ana'
        ..displayLabel = 'Old';
      final replacement = Account()
        ..username = 'ana'
        ..displayLabel = 'New';

      // Act.
      await database.accounts.put(existing);
      await database.accounts.putByUsername(replacement);
      final stored = await database.accounts.get(existing.dbId);
      final matches = await database.accounts
          .where()
          .usernameEqualTo('ana')
          .findAll();

      // Assert.
      expect(existing.dbId, 1);
      expect(replacement.dbId, 1);
      expect(stored!.displayLabel, 'New');
      expect(matches.map((account) => account.displayLabel), ['New']);
    });

    // Scenario: Generated replace index helpers can upsert batches.
    // Covers:
    // - Generated [putAllByUsername] method.
    // - Per-object id reuse across a batch.
    // - Multiple replace-index values in one write transaction.
    // Expected: Each replacement reuses its matching stored id.
    test(
      'reuses ids when putting batches by a unique replace index.',
      () async {
        // Arrange.
        final database = await openTestDatabaseInMemory(
          schemas: [AccountSchema],
        );
        addTearDown(database.close);
        final ana = Account()
          ..username = 'ana'
          ..displayLabel = 'Ana old';
        final ben = Account()
          ..username = 'ben'
          ..displayLabel = 'Ben old';
        final replacementAna = Account()
          ..username = 'ana'
          ..displayLabel = 'Ana new';
        final replacementBen = Account()
          ..username = 'ben'
          ..displayLabel = 'Ben new';

        // Act.
        await database.accounts.putAll([ana, ben]);
        await database.accounts.putAllByUsername([
          replacementAna,
          replacementBen,
        ]);
        final stored = await database.accounts.all().sortByUsername().findAll();

        // Assert.
        expect([ana.dbId, ben.dbId], [1, 2]);
        expect([replacementAna.dbId, replacementBen.dbId], [1, 2]);
        expect(stored.map((account) => account.displayLabel), [
          'Ana new',
          'Ben new',
        ]);
      },
    );

    // Scenario: Normal put respects replace-index semantics at the storage
    // boundary.
    // Covers:
    // - [@Index(unique: true, replace: true)] on generated schema metadata.
    // - Native conflict deletion when a different id owns the same index value.
    // Expected: The conflicting old document is removed and the new id remains.
    test('replaces conflicting documents for normal puts.', () async {
      // Arrange.
      final database = await openTestDatabaseInMemory(schemas: [AccountSchema]);
      addTearDown(database.close);
      final oldAccount = Account()
        ..dbId = 7
        ..username = 'ana'
        ..displayLabel = 'Old';
      final newAccount = Account()
        ..dbId = 8
        ..username = 'ana'
        ..displayLabel = 'New';

      // Act.
      await database.accounts.put(oldAccount);
      await database.accounts.put(newAccount);
      final oldStored = await database.accounts.get(7);
      final newStored = await database.accounts.get(8);
      final matches = await database.accounts
          .where()
          .usernameEqualTo('ana')
          .findAll();

      // Assert.
      expect(oldStored, isNull);
      expect(newStored!.displayLabel, 'New');
      expect(matches.map((account) => account.dbId), [8]);
    });

    // Scenario: Replace-index helpers are called inside an existing write
    // transaction.
    // Covers:
    // - [CindelTypedCollection.putByUniqueIndex] transaction reuse branch.
    // - [CindelTypedCollection.putAllByUniqueIndex] transaction reuse branch.
    // - Empty replace-index batches as no-ops.
    // Expected: Helpers reuse the active transaction instead of nesting another
    // write transaction.
    test('reuses active transactions for replace-index helpers.', () async {
      // Arrange.
      final database = await openTestDatabaseInMemory(schemas: [AccountSchema]);
      addTearDown(database.close);
      final existing = Account()
        ..username = 'ana'
        ..displayLabel = 'Old';
      final replacement = Account()
        ..username = 'ana'
        ..displayLabel = 'New';
      final ben = Account()
        ..username = 'ben'
        ..displayLabel = 'Ben';

      // Act.
      await database.accounts.put(existing);
      await database.writeTxn<void>(() async {
        await database.accounts.putAllByUsername(const []);
        await database.accounts.putByUsername(replacement);
        await database.accounts.putAllByUsername([ben]);
      });
      final stored = await database.accounts.all().sortByUsername().findAll();

      // Assert.
      expect(replacement.dbId, existing.dbId);
      expect(stored.map((account) => account.displayLabel), ['New', 'Ben']);
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
        ..dbId = 7
        ..name = 'Ana'
        ..email = 'ana@example.com';
      final secondUser = User()
        ..dbId = 7
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
        ..dbId = 1
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

    // Scenario: Lazy typed watchers are subscribed without initial emissions.
    // Covers:
    // - [CindelTypedCollection.watchObjectLazy].
    // - [CindelTypedCollection.watchCollectionLazy].
    // - `fireImmediately: false` stream skip branch.
    // Expected: Lazy streams emit only after a matching collection change.
    test('emits lazy watcher events after changes only.', () async {
      // Arrange.
      final database = await openTestDatabaseInMemory(schemas: [UserSchema]);
      addTearDown(database.close);
      final objectEvents = <void>[];
      final collectionEvents = <void>[];
      final objectSubscription = database.users
          .watchObjectLazy(
            1,
            pollInterval: const Duration(milliseconds: 5),
            fireImmediately: false,
          )
          .listen(objectEvents.add);
      final collectionSubscription = database.users
          .watchCollectionLazy(
            pollInterval: const Duration(milliseconds: 5),
            fireImmediately: false,
          )
          .listen(collectionEvents.add);
      addTearDown(objectSubscription.cancel);
      addTearDown(collectionSubscription.cancel);

      // Act.
      await Future<void>.delayed(const Duration(milliseconds: 30));
      final initialObjectEvents = objectEvents.length;
      final initialCollectionEvents = collectionEvents.length;
      await database.users.put(
        User()
          ..dbId = 1
          ..name = 'Ana'
          ..email = 'ana@example.com',
      );
      await _waitUntil(() => objectEvents.length > initialObjectEvents);
      await _waitUntil(() => collectionEvents.length > initialCollectionEvents);

      // Assert.
      expect(initialObjectEvents, 0);
      expect(initialCollectionEvents, 0);
      expect(objectEvents, hasLength(1));
      expect(collectionEvents, hasLength(1));
    });

    // Scenario: A database closes while typed watchers are still subscribed.
    // Covers:
    // - Database close forwarding to active watcher streams.
    // - Watcher timer cleanup without requiring caller-side cancellation first.
    // Expected: Active watcher streams complete when the database closes.
    test('closes active watcher streams when database closes.', () async {
      // Arrange.
      final database = await openTestDatabaseInMemory(schemas: [UserSchema]);
      addTearDown(database.close);
      final done = database.users
          .watchCollection(
            pollInterval: const Duration(milliseconds: 5),
            fireImmediately: false,
          )
          .drain<void>();
      await Future<void>.delayed(Duration.zero);

      // Act.
      await database.close();

      // Assert.
      await expectLater(done, completes);
    });

    // Scenario: Typed watcher snapshots are unchanged after rewriting the same
    // object value.
    // Covers:
    // - [CindelTypedCollection._distinctObjectSnapshots] duplicate suppression.
    // - [CindelTypedCollection._distinctCollectionSnapshots] duplicate
    //   suppression.
    // - Deep document equality used by watcher transforms.
    // Expected: Rewriting an identical object does not emit a second snapshot.
    test('suppresses duplicate typed watcher snapshots.', () async {
      // Arrange.
      final database = await openTestDatabaseInMemory(schemas: [UserSchema]);
      addTearDown(database.close);
      final objectEvents = <User?>[];
      final collectionEvents = <List<User>>[];
      final objectSubscription = database.users
          .watchObject(1, pollInterval: const Duration(milliseconds: 5))
          .listen(objectEvents.add);
      final collectionSubscription = database.users
          .watchCollection(pollInterval: const Duration(milliseconds: 5))
          .listen(collectionEvents.add);
      addTearDown(objectSubscription.cancel);
      addTearDown(collectionSubscription.cancel);
      final user = User()
        ..dbId = 1
        ..name = 'Ana'
        ..email = 'ana@example.com'
        ..tags = ['vip']
        ..primaryRecipient = (Recipient()
          ..name = 'Ana'
          ..address = 'ana@example.com');

      // Act.
      await _waitUntil(() => objectEvents.length == 1);
      await _waitUntil(() => collectionEvents.length == 1);
      await database.users.put(user);
      await _waitUntil(() => objectEvents.length == 2);
      await _waitUntil(() => collectionEvents.length == 2);
      await database.users.put(user);
      await Future<void>.delayed(const Duration(milliseconds: 40));

      // Assert.
      expect(objectEvents, hasLength(2));
      expect(collectionEvents, hasLength(2));
      expect(objectEvents.last!.name, 'Ana');
      expect(collectionEvents.last.single.name, 'Ana');
    });

    // Scenario: A typed object serializer produces an invalid id field.
    // Covers:
    // - [CindelTypedCollection.put] id extraction from schema metadata.
    // - Defensive typed API validation before storage writes.
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

    // Scenario: A manually wired schema has typed id accessors but no generated
    // binary/native storage path.
    // Covers:
    // - [CindelTypedCollection.put] missing typed storage branch.
    // - [CindelTypedCollection.get] missing typed storage branch.
    // - [CindelTypedCollection.getAll] missing typed storage branch.
    // - [CindelTypedCollection.watchObject] and [watchCollection] missing typed
    //   storage branches.
    // Expected: Incomplete schemas fail explicitly instead of falling back to a
    // generic document path.
    test('rejects schemas without a typed storage path.', () async {
      // Arrange.
      final database = await openTestDatabaseInMemory();
      addTearDown(database.close);
      final schema = CindelCollectionSchema<_ManualStoredUser>(
        name: 'manualStoredUsers',
        dartName: 'ManualStoredUser',
        idField: 'id',
        fields: const [
          CindelFieldSchema(
            name: 'id',
            dartType: 'int',
            isId: true,
            isIndexed: false,
          ),
        ],
        toDocument: (user) => {'id': user.id},
        fromDocument: (document) => _ManualStoredUser(document['id']! as int),
        getId: (user) => user.id,
        setId: (user, id) => user.id = id,
      );
      final collection = database.typedCollection(schema);

      // Act / Assert.
      await expectLater(
        collection.put(_ManualStoredUser(1)),
        throwsA(isA<StateError>()),
      );
      await expectLater(collection.get(1), throwsA(isA<StateError>()));
      await expectLater(collection.getAll([1]), throwsA(isA<StateError>()));
      expect(
        () => collection.watchObject(1).listen(null),
        throwsA(isA<StateError>()),
      );
      expect(
        () => collection.watchCollection().listen(null),
        throwsA(isA<StateError>()),
      );
    });
  });
}

final class _BrokenUser {
  const _BrokenUser();
}

final class _ManualAutoUser {
  const _ManualAutoUser();
}

final class _ManualStoredUser {
  _ManualStoredUser(this.id);

  int id;
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
