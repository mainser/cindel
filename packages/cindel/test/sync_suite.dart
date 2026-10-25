import 'dart:async';
import 'dart:io';

import 'package:cindel/cindel.dart';
import 'package:test/test.dart';

import 'backend_test_support.dart';
import 'schema_generation_fixture.dart';

void main() {
  group('sync', () {
    // Public adapter values are plain transport contracts. This protects the
    // documented defaults and the less common result shapes without reaching
    // into the internal scheduler.
    // Scenario: Public sync configuration and result objects are constructed
    // with default and explicit values.
    // Covers:
    // - Adapter identity, scheduler defaults and link/rejection/push result
    // fields.
    // Expected: Defaults and every supplied transport field are retained
    // unchanged.
    test('exposes adapter contract value objects', () {
      // Arrange.
      final adapter = _SyncTestAdapter();
      // Act.
      final config = CindelSyncConfig(adapter: adapter);
      // Assert.
      expect(config.adapter, same(adapter));
      expect(config.clientId, isNull);
      expect(config.onStatusChanged, isNull);
      expect(config.onError, isNull);
      expect(config.autoStart, isTrue);
      expect(config.interval, const Duration(seconds: 5));
      expect(config.batchSize, 100);

      const linkReplacement = CindelRemoteReplaceLinks(
        collection: 'users',
        id: 7,
        linkName: 'teams',
        targetCollection: 'teams',
        targetIds: [1, 2],
      );
      expect(linkReplacement.collection, 'users');
      expect(linkReplacement.id, 7);
      expect(linkReplacement.linkName, 'teams');
      expect(linkReplacement.targetCollection, 'teams');
      expect(linkReplacement.targetIds, [1, 2]);

      const rejection = CindelSyncRejectedMutation(
        mutationId: 'client-a:3',
        reason: 'permission_denied',
      );
      expect(rejection.mutationId, 'client-a:3');
      expect(rejection.reason, 'permission_denied');

      const result = CindelPushResult(
        acceptedMutationIds: {'client-a:1'},
        rejectedMutations: [rejection],
        correctedChanges: [linkReplacement],
        checkpoint: '42',
      );
      expect(result.acceptedMutationIds, {'client-a:1'});
      expect(result.rejectedMutations, [rejection]);
      expect(result.correctedChanges, [linkReplacement]);
      expect(result.checkpoint, '42');
    });

    // This test covers the full local-outbox lifecycle: optimistic local write,
    // offline retry, durable pending row across reopen, successful push after
    // reconnect, and a follow-up delete using a non-reused mutation id.
    // Scenario: An offline adapter receives a local typed write, then the
    // database reopens before reconnecting.
    // Covers:
    // - Durable pending writes, reconnect push and mutation sequence reuse
    // prevention.
    // Expected: The row persists offline, reconnect drains pending work and a
    // subsequent delete reaches the server.
    test(
      'pushes pending typed writes through the internal scheduler',
      () async {
        // Arrange.
        final directory = await Directory.systemTemp.createTemp('cindel_sync_');
        final adapter = _SyncTestAdapter()..online = false;
        final statuses = <CindelSyncStatus>[];
        CindelDatabase? database;
        // Act / Assert.
        try {
          database = await openTestDatabase(
            directory: directory.path,
            schemas: [UserSchema],
            sync: CindelSyncConfig(
              adapter: adapter,
              interval: const Duration(milliseconds: 10),
              onStatusChanged: statuses.add,
            ),
          );

          final users = database.users;
          await users.put(_user(1, 'local@example.com'));

          expect((await users.get(1))?.email, 'local@example.com');
          await _eventually(
            () => statuses.any((status) => status.pendingCount == 1),
          );
          expect(adapter.serverHas(1), isFalse);

          await database.close();
          database = await openTestDatabase(
            directory: directory.path,
            schemas: [UserSchema],
            sync: CindelSyncConfig(
              adapter: adapter,
              interval: const Duration(milliseconds: 10),
              onStatusChanged: statuses.add,
            ),
          );
          await _eventually(
            () => statuses.any((status) => status.pendingCount == 1),
          );

          adapter.online = true;
          await _eventually(() => adapter.serverHas(1));
          await _eventually(() => statuses.last.pendingCount == 0);

          // Regression coverage for sequence persistence: after reopening with
          // pending outbox rows, the next mutation id must advance instead of
          // reusing an already-accepted id from the earlier push.
          await database.users.delete(1);
          await _eventually(() => !adapter.serverHas(1));
        } finally {
          await database?.close();
          await directory.delete(recursive: true);
        }
      },
    );

    // Remote apply must look like a normal committed database change to
    // watchers, but it must not be recorded as a new outgoing local mutation.
    // Scenario: A fake adapter stages a remote upsert followed by a remote
    // delete.
    // Covers:
    // - Watcher visibility of remote changes without generating outgoing
    // mutations.
    // Expected: Watchers observe both changes, the upsert adds no push and
    // the final pending count is zero.
    test('applies remote changes without re-enqueueing them', () async {
      // Arrange.
      final directory = await Directory.systemTemp.createTemp('cindel_sync_');
      final adapter = _SyncTestAdapter();
      final statuses = <CindelSyncStatus>[];
      final errors = <Object>[];
      CindelDatabase? database;
      StreamSubscription<List<User>>? subscription;
      final snapshots = <List<String>>[];
      // Act / Assert.
      try {
        database = await openTestDatabase(
          directory: directory.path,
          schemas: [UserSchema],
          sync: CindelSyncConfig(
            adapter: adapter,
            interval: const Duration(milliseconds: 10),
            onStatusChanged: statuses.add,
            onError: (error, _) => errors.add(error),
          ),
        );
        subscription = database.users.watchCollection().listen((users) {
          snapshots.add([for (final user in users) user.email]..sort());
        });

        final pushedBefore = adapter.pushedMutationIds.length;
        adapter.stageRemoteUpsert(
          _userDocument(_user(42, 'remote@example.com')),
        );
        await _eventually(() {
          if (errors.isNotEmpty) {
            fail('Sync error: ${errors.first}');
          }
          return snapshots.any(
            (emails) => emails.contains('remote@example.com'),
          );
        });
        expect(adapter.pushedMutationIds.length, pushedBefore);

        snapshots.clear();
        adapter.stageRemoteDelete(42);
        await _eventually(() {
          if (errors.isNotEmpty) {
            fail('Sync error: ${errors.first}');
          }
          return snapshots.any(
            (emails) => !emails.contains('remote@example.com'),
          );
        });
        expect(await database.users.get(42), isNull);
        await _eventually(() => statuses.last.pendingCount == 0);
      } finally {
        await subscription?.cancel();
        await database?.close();
        await directory.delete(recursive: true);
      }
    });

    // Query update support is intentionally blocked for now because it lacks
    // per-document snapshots. The object remains readable after the failed
    // update, proving the operation is rejected before corrupting data.
    // Scenario: A sync-enabled collection receives a query update.
    // Covers:
    // - Rejection of unsupported query mutations before changing stored
    // fields.
    // Expected: The update throws UnsupportedError and the original name
    // remains readable.
    test('rejects query updates while sync is enabled', () async {
      // Arrange.
      final directory = await Directory.systemTemp.createTemp('cindel_sync_');
      final adapter = _SyncTestAdapter();
      CindelDatabase? database;
      // Act / Assert.
      try {
        database = await openTestDatabase(
          directory: directory.path,
          schemas: [UserSchema],
          sync: CindelSyncConfig(
            adapter: adapter,
            interval: const Duration(milliseconds: 10),
          ),
        );
        await database.users.put(_user(1, 'blocked@example.com'));

        await expectLater(
          database.users.all().updateAll({'name': 'blocked'}),
          throwsA(isA<UnsupportedError>()),
        );
        expect((await database.users.get(1))?.name, 'blocked');
      } finally {
        await database?.close();
        await directory.delete(recursive: true);
      }
    });
  });
}

// Minimal idempotent fake backend for exercising the adapter contract without
// network I/O. It stores accepted mutation ids just like a real backend should.
final class _SyncTestAdapter implements CindelSyncAdapter {
  final _server = <int, Map<String, Object?>>{};
  final _changes = <({int sequence, CindelRemoteChange change})>[];
  final pushedMutationIds = <String>[];
  final _accepted = <String>{};

  var online = true;
  var _nextRemoteSequence = 1;

  @override
  Future<CindelPullResult> pull(CindelPullRequest request) async {
    _checkOnline();
    // Checkpoints are monotonically increasing sequence numbers in this fake.
    // Real adapters can use opaque tokens as long as they are stable.
    final since = request.checkpoint == null
        ? 0
        : int.parse(request.checkpoint!);
    return CindelPullResult(
      checkpoint: '${_nextRemoteSequence - 1}',
      changes: [
        for (final entry in _changes)
          if (entry.sequence > since) entry.change,
      ],
    );
  }

  @override
  Future<CindelPushResult> push(CindelPushRequest request) async {
    _checkOnline();
    final accepted = <String>{};
    for (final mutation in request.mutations) {
      // Duplicate mutation ids are acknowledged but not applied again. This is
      // the central backend requirement that makes retry safe.
      if (!_accepted.add(mutation.mutationId)) {
        accepted.add(mutation.mutationId);
        continue;
      }
      pushedMutationIds.add(mutation.mutationId);
      switch (mutation.operation) {
        case CindelSyncOperation.upsert:
          _server[mutation.documentId!] = Map.of(mutation.document!);
        case CindelSyncOperation.delete:
          _server.remove(mutation.documentId);
        case CindelSyncOperation.replaceLinks:
          break;
      }
      accepted.add(mutation.mutationId);
    }
    return CindelPushResult(acceptedMutationIds: accepted);
  }

  void stageRemoteUpsert(Map<String, Object?> document) {
    // Simulates another client or server-side process creating remote truth
    // that this database should later pull.
    final id = document['dbId'] as int;
    _server[id] = Map.of(document);
    _changes.add((
      sequence: _nextRemoteSequence++,
      change: CindelRemoteUpsert(
        collection: UserSchema.name,
        id: id,
        document: document,
      ),
    ));
  }

  void stageRemoteDelete(int id) {
    // Remote deletes are represented as server-side truth, not as a local
    // outgoing mutation from this database.
    _server.remove(id);
    _changes.add((
      sequence: _nextRemoteSequence++,
      change: CindelRemoteDelete(collection: UserSchema.name, id: id),
    ));
  }

  bool serverHas(int id) => _server.containsKey(id);

  void _checkOnline() {
    if (!online) {
      throw StateError('offline');
    }
  }
}

User _user(int id, String email) {
  return User()
    ..dbId = id
    ..name = email.split('@').first
    ..email = email
    ..active = true;
}

Map<String, Object?> _userDocument(User user) {
  return {
    UserSchema.idField: UserSchema.getId!(user),
    ...UserSchema.toDocument(user),
  };
}

Future<void> _eventually(FutureOr<bool> Function() test) async {
  for (var attempt = 0; attempt < 80; attempt += 1) {
    if (await test()) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
  fail('Condition was not met in time.');
}
