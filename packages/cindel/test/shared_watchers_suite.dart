import 'dart:async';

import 'package:cindel/cindel.dart';
import 'package:test/test.dart';

import 'backend_test_support.dart';
import 'backup_contract_fixture.dart';
import 'close_test_support_io.dart'
    if (dart.library.js_interop) 'close_test_support_web.dart';

void main({bool includeExternalHandle = true}) {
  group('shared watchers integration', () {
    Future<CindelDatabase> open() async {
      final path = await createCloseTestDirectory();
      addTearDown(() => deleteCloseTestDirectory(path));
      final db = await openTestDatabase(
        directory: path,
        schemas: [backupNodeSchema],
      );
      addTearDown(db.close);
      return db;
    }

    // Scenario: Object, collection, query and lazy observers share a collection.
    // Covers: Typed filtering, initial events, commit/rollback and duplicate suppression.
    // Expected: All 100 observers keep their public behavior under shared polling.
    test(
      'preserves mixed typed subscriptions and committed changes.',
      () async {
        // Arrange.
        final db = await open();
        final nodes = db.typedCollection(backupNodeSchema);
        final subscriptions = <StreamSubscription<Object?>>[];
        addTearDown(() async {
          for (final subscription in subscriptions) {
            await subscription.cancel();
          }
        });
        var objects = 0;
        var collections = 0;
        final queryResults = List.generate(25, (_) => <List<BackupNode>>[]);
        var lazy = 0;
        // Act.
        for (var i = 0; i < 25; i++) {
          subscriptions.add(nodes.watchObject(1).listen((_) => objects++));
          subscriptions.add(
            nodes.watchCollection().listen((_) => collections++),
          );
          subscriptions.add(
            nodes
                .all()
                .whereMatches(CindelFilter.path(['payload']).equalTo('target'))
                .watch()
                .listen(queryResults[i].add),
          );
          subscriptions.add(nodes.watchObjectLazy(1).listen((_) => lazy++));
        }
        await _until(
          () =>
              objects == 25 &&
              collections == 25 &&
              queryResults.every((events) => events.isNotEmpty),
        );
        // Assert.
        expect(lazy, 0);
        await nodes.put(BackupNode(2, payload: 'unrelated'));
        await _until(() => collections == 50);
        expect(objects, 25);
        expect(queryResults.every((events) => events.last.isEmpty), isTrue);
        expect(lazy, 0);
        await db.writeTxn(() async {
          await nodes.put(BackupNode(1, payload: 'target'));
          await Future<void>.delayed(const Duration(milliseconds: 70));
          expect(objects, 25);
          expect(collections, 50);
        });
        await _until(
          () =>
              objects == 50 &&
              collections == 75 &&
              lazy == 25 &&
              queryResults.every(
                (events) =>
                    events.last.length == 1 && events.last.single.dbId == 1,
              ),
        );
        final failure = StateError('controlled rollback');
        await expectLater(
          db.writeTxn(() async {
            await nodes.put(BackupNode(1, payload: 'rollback'));
            throw failure;
          }),
          throwsA(same(failure)),
        );
        await nodes.put(BackupNode(1, payload: 'target'));
        await Future<void>.delayed(const Duration(milliseconds: 100));
        expect([objects, collections, lazy], [50, 75, 25]);
        // Query watchers intentionally may repeat an unchanged result. Preserve
        // that contract while ensuring no uncommitted value reaches any query.
        expect(
          queryResults.every(
            (events) => events.every(
              (nodes) => nodes.every((node) => node.payload == 'target'),
            ),
          ),
          isTrue,
        );
      },
    );

    // Scenario: The first observer subscribes while a write is pending.
    // Covers: Initial snapshot deferral and rollback isolation.
    // Expected: No uncommitted event escapes; initial emission happens afterward.
    test(
      'does not initialize watchers from an uncommitted transaction.',
      () async {
        // Arrange.
        final db = await open();
        final events = <List<BackupNode>>[];
        StreamSubscription<List<BackupNode>>? subscription;
        addTearDown(() => subscription?.cancel());
        final failure = StateError('controlled rollback');
        // Act / Assert.
        await expectLater(
          db.writeTxn(() async {
            await db.typedCollection(backupNodeSchema).put(BackupNode(1));
            subscription = db
                .typedCollection(backupNodeSchema)
                .watchCollection(pollInterval: const Duration(milliseconds: 5))
                .listen(events.add);
            await Future<void>.delayed(const Duration(milliseconds: 30));
            expect(events, isEmpty);
            throw failure;
          }),
          throwsA(same(failure)),
        );
        await _until(() => events.isNotEmpty);
        expect(events.single, isEmpty);
      },
    );

    if (includeExternalHandle) {
      // Scenario: Another native handle commits while 100 observers share polls.
      // Covers: External revisions, mixed intervals, cancellation and remaining listener.
      // Expected: Every observer sees external changes; canceled observers stay quiet.
      test(
        'detects external commits after other subscribers cancel.',
        () async {
          // Arrange.
          final db = await open();
          final writer = await openTestDatabase(
            directory: db.directory,
            schemas: [backupNodeSchema],
          );
          addTearDown(writer.close);
          final events = List.generate(100, (_) => <CindelChangeSet>[]);
          final subscriptions = [
            for (var i = 0; i < events.length; i++)
              db
                  .watchCollectionChanges(
                    'backup_nodes',
                    pollInterval: Duration(milliseconds: i < 50 ? 5 : 30),
                  )
                  .listen(events[i].add),
          ];
          addTearDown(() async {
            for (final subscription in subscriptions) {
              await subscription.cancel();
            }
          });
          await _until(() => events.every((values) => values.length == 1));
          // Act.
          await writer.typedCollection(backupNodeSchema).put(BackupNode(1));
          await _until(() => events.every((values) => values.length == 2));
          // Assert.
          expect(events.every((values) => values.last.isExternal), isTrue);
          for (final subscription in subscriptions.take(99)) {
            await subscription.cancel();
          }
          await writer.typedCollection(backupNodeSchema).put(BackupNode(2));
          await _until(() => events.last.length == 3);
          expect(events.take(99).every((values) => values.length == 2), isTrue);
        },
      );
    }
  });
}

Future<void> _until(bool Function() done) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!done()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('Watcher event missing.');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}
