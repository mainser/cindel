import 'dart:async';

import 'package:cindel/cindel.dart';
import 'package:cindel/src/web/worker_bridge.dart';
import 'package:test/test.dart';

import 'close_test_support_web.dart';
import 'type_compatibility_fixture.dart';

void main() {
  group('Web public watcher contracts', () {
    for (final route in ['changes', 'object', 'collection', 'query']) {
      // The runner injects one revision failure for this database name only.
      // Subsequent requests execute against the packaged Worker and SQLite.
      // Scenario: Each public watcher route encounters a controlled revision
      // failure before recovery and an update.
      // Covers:
      // - Error context preservation, resumed notifications and stream
      // termination on close.
      // Expected: One contextual error is reported, values seven/nine are
      // observed and no new events arrive after close.
      test('$route preserves errors, recovers, updates and closes', () async {
        // Arrange.
        final directory =
            'cindel-watch-error-${await createCloseTestDirectory()}';
        addTearDown(() => deleteCloseTestDirectory(directory));
        final db = await Cindel.open(
          directory: directory,
          backend: CindelStorageBackend.sqlite,
          schemas: [Modelc06Schema],
        );
        addTearDown(db.close);
        final collection = db.typedCollection(Modelc06Schema);
        await collection.put(
          Modelc06()
            ..dbId = 1
            ..value = 7,
        );
        const interval = Duration(milliseconds: 10);
        var writingUpdate = false;
        final Stream<int?> stream = switch (route) {
          'changes' =>
            db
                .watchCollectionChanges(
                  Modelc06Schema.name,
                  pollInterval: interval,
                )
                .map((change) {
                  expect(change.mayAffectDocument(1), isTrue);
                  return writingUpdate ? 9 : 7;
                }),
          'object' =>
            collection
                .watchObject(1, pollInterval: interval)
                .map((object) => object?.value),
          'collection' =>
            collection
                .watchCollection(pollInterval: interval)
                .map((objects) => objects.single.value),
          'query' =>
            collection
                .all()
                .watch(pollInterval: interval)
                .map((objects) => objects.single.value),
          _ => throw StateError(route),
        };
        final errors = <Object>[];
        final events = <int?>[];
        final failed = Completer<Object>();
        final recovered = Completer<void>();
        final updated = Completer<void>();
        final closed = Completer<void>();
        // Act.
        final subscription = stream.listen(
          (value) {
            events.add(value);
            if (value == 7 && !recovered.isCompleted) recovered.complete();
            if (value == 9 && !updated.isCompleted) updated.complete();
          },
          onError: (Object error, StackTrace stack) {
            errors.add(error);
            if (!failed.isCompleted) failed.complete(error);
          },
          onDone: closed.complete,
        );
        addTearDown(subscription.cancel);
        const timeout = Duration(seconds: 5);
        final error = await failed.future.timeout(timeout);
        // Assert.
        expect(error, isA<CindelError>());
        final cindelError = error as CindelError;
        expect(cindelError.operation, 'collectionRevision');
        expect(cindelError.backend, 'sqlite');
        expect(cindelError.code, 'operation_failed');
        expect(cindelError.cause, isA<CindelWebWorkerException>());
        expect(
          (cindelError.cause! as CindelWebWorkerException).message,
          'controlled watcher revision failure',
        );
        await recovered.future.timeout(timeout);
        writingUpdate = true;
        await collection.put(
          Modelc06()
            ..dbId = 1
            ..value = 9,
        );
        await updated.future.timeout(timeout);
        await db.close();
        await closed.future.timeout(timeout);
        final countAtClose = events.length;
        await Future<void>.delayed(interval * 3);
        expect(events.length, countAtClose);
        if (route == 'changes' || route == 'query') {
          // These streams notify changes; unlike typed snapshots, they do not
          // promise to suppress equivalent results from concurrent notifications.
          expect(events.first, 7);
          expect(events.skip(1), isNotEmpty);
          expect(events.skip(1), everyElement(9));
        } else {
          expect(events, [7, 9]);
        }
        expect(errors, [same(error)]);
      });
    }
    for (final route in [
      'object',
      'collection',
      'query',
      'objectLazy',
      'collectionLazy',
      'queryLazy',
    ]) {
      // Queue a real committed change while the listener is paused, then close
      // before resuming. This reproduces queued snapshot reads after retirement
      // without injected Worker failures or arbitrary timing delays.
      // Scenario: A watcher subscription is paused while an update is
      // buffered and the database closes.
      // Covers:
      // - Pending watcher work during close across object, collection, query
      // and lazy routes.
      // Expected: New reads are rejected, resuming allows close/stream
      // completion and no watcher error is emitted.
      test('$route closes with a buffered update and no error', () async {
        // Arrange.
        final directory = await createCloseTestDirectory();
        addTearDown(() => deleteCloseTestDirectory(directory));
        final db = await Cindel.open(
          directory: directory,
          backend: CindelStorageBackend.sqlite,
          schemas: [Modelc06Schema],
        );
        addTearDown(db.close);
        final collection = db.typedCollection(Modelc06Schema);
        await collection.put(
          Modelc06()
            ..dbId = 1
            ..value = 7,
        );
        const interval = Duration(milliseconds: 10);
        final Stream<Object?> stream = switch (route) {
          'object' => collection.watchObject(1, pollInterval: interval),
          'collection' => collection.watchCollection(pollInterval: interval),
          'query' => collection.all().watch(pollInterval: interval),
          'objectLazy' => collection.watchObjectLazy(
            1,
            pollInterval: interval,
            fireImmediately: true,
          ),
          'collectionLazy' => collection.watchCollectionLazy(
            pollInterval: interval,
            fireImmediately: true,
          ),
          'queryLazy' => collection.all().watchLazy(
            pollInterval: interval,
            fireImmediately: true,
          ),
          _ => throw StateError(route),
        };
        final errors = <Object>[];
        final initial = Completer<void>();
        final done = Completer<void>();
        // Act.
        final subscription = stream.listen(
          (_) {
            if (!initial.isCompleted) initial.complete();
          },
          onError: (Object error) => errors.add(error),
          onDone: done.complete,
        );
        addTearDown(subscription.cancel);
        const timeout = Duration(seconds: 5);
        await initial.future.timeout(timeout);
        subscription.pause();
        await collection.put(
          Modelc06()
            ..dbId = 1
            ..value = 9,
        );
        final closing = db.close();
        // Assert.
        try {
          // Yield one event-loop turn so close has retired the handle; the
          // public read verifies that state before the buffered stream resumes.
          await Future<void>.delayed(Duration.zero);
          await expectLater(
            collection.get(1),
            throwsA(isA<CindelDatabaseClosedError>()),
          );
        } finally {
          subscription.resume();
        }
        await closing.timeout(timeout);
        await done.future.timeout(timeout);
        expect(errors, isEmpty);
      });
    }
  });
}
