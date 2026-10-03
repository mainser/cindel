import 'dart:async';

import 'package:cindel/cindel.dart';
import 'package:test/test.dart';

import 'close_test_support_web.dart';
import 'schema_generation_fixture.dart';

void main() {
  group('Web database close', () {
    for (final write in [false, true]) {
      // Scenario: close starts before a dispatched transaction BEGIN replies.
      // Covers:
      // - The asynchronous Worker admission boundary before user callbacks.
      // - Retiring the handle without starting a callback after closure.
      // Expected: close succeeds; the transaction reports closed, its callback
      // never starts, and no pending row persists through another Worker.
      test('cancels an admitted ${write ? 'write' : 'read'} BEGIN.', () async {
        // Arrange.
        final fixture = await _seeded();
        var callbackRan = false;
        Future<void> callback() async {
          callbackRan = true;
          await fixture.database.apiProducts.get(1);
          if (write)
            await fixture.database.apiProducts.put(_product(2, 'pending'));
        }

        // Act. Keep these calls in the same synchronous turn.
        final transaction = _Observed(
          write
              ? fixture.database.writeTxn(callback)
              : fixture.database.readTxn(callback),
        );
        final close = _Observed(fixture.database.close());
        await Future.wait([transaction.done, close.done]).timeout(_timeout);

        // Assert.
        expect(close.error, isNull);
        expect(transaction.error, isA<CindelDatabaseClosedError>());
        expect(callbackRan, isFalse);
        await _stored(fixture.directory, pendingId: 2);
      });
    }

    // Scenario: a paused watcher is canceled while concurrent closes wait.
    // Covers:
    // - Both close callers sharing the paused stream teardown.
    // - Cancellation releasing teardown without watcher failures.
    // Expected: both close Futures stay pending until cancellation and then
    // finish successfully with identical Future identity.
    test('releases paused watcher closure on cancellation.', () async {
      // Arrange.
      final fixture = await _seeded();
      final initial = Completer<void>();
      final errors = <Object>[];
      final subscription = fixture.database.apiProducts
          .watchCollection(pollInterval: const Duration(milliseconds: 5))
          .listen(
            (_) {
              if (!initial.isCompleted) initial.complete();
            },
            onError: (Object error, StackTrace _) {
              errors.add(error);
              if (!initial.isCompleted) initial.complete();
            },
          );
      addTearDown(subscription.cancel);
      await initial.future.timeout(_timeout);
      subscription.pause();

      // Act. Attach observers before yielding and always release before asserts.
      final firstFuture = fixture.database.close();
      final secondFuture = fixture.database.close();
      final first = _Observed(firstFuture);
      final second = _Observed(secondFuture);
      await Future<void>.delayed(Duration.zero);
      final bothPending = !first.finished && !second.finished;
      await subscription.cancel();
      await Future.wait([first.done, second.done]).timeout(_timeout);

      // Assert.
      expect(bothPending, isTrue);
      expect(secondFuture, same(firstFuture));
      expect(first.error, isNull);
      expect(second.error, isNull);
      expect(errors, isEmpty);
      await _stored(fixture.directory);
    });

    // Scenario: close arrives after the callback returns with commit dispatched.
    // Covers:
    // - In-flight commit preserving its storage and public transaction result.
    // - Watcher metadata cleanup not replacing a successful commit with error.
    // Expected: both operations succeed and the committed row persists.
    test('preserves a dispatched commit when close begins.', () async {
      // Arrange.
      final fixture = await _seeded();
      final callbackReturned = Completer<void>();
      final transaction = _Observed(
        fixture.database.writeTxn(() async {
          await fixture.database.apiProducts.put(_product(2, 'committed'));
          callbackReturned.complete();
          return 'committed';
        }),
      );
      await callbackReturned.future.timeout(_timeout);

      // Act. Worker replies are browser tasks; these microtasks dispatch commit
      // before requesting close in the same browser event-loop turn.
      await Future<void>.microtask(() {});
      await Future<void>.microtask(() {});
      final close = _Observed(fixture.database.close());
      await Future.wait([transaction.done, close.done]).timeout(_timeout);

      // Assert.
      expect(close.error, isNull);
      expect(transaction.error, isNull);
      expect(transaction.value, 'committed');
      await _stored(fixture.directory, committedId: 2);
    });
  }, timeout: const Timeout(Duration(seconds: 30)));
}

const _timeout = Duration(seconds: 10);

Future<CindelDatabase> _open(String directory) async {
  final database = await Cindel.open(
    directory: directory,
    schemas: [ApiProductSchema],
  );
  addTearDown(database.close);
  return database;
}

Future<({String directory, CindelDatabase database})> _seeded() async {
  final directory = await createCloseTestDirectory();
  // Register storage cleanup first, so all later handle/subscription teardown
  // completes before the runner's owned OPFS pool is removed.
  addTearDown(() => deleteCloseTestDirectory(directory));
  final database = await _open(directory);
  await database.apiProducts.put(_product(1, 'original'));
  return (directory: directory, database: database);
}

ApiProduct _product(int id, String name) => ApiProduct()
  ..dbId = id
  ..id = 'close-$id'
  ..name = name;

/// Storage checks always use a new real Worker after the old one has retired.
Future<void> _stored(
  String directory, {
  int? pendingId,
  int? committedId,
}) async {
  final reopened = await _open(directory);
  expect((await reopened.apiProducts.get(1))?.name, 'original');
  if (pendingId != null)
    expect(await reopened.apiProducts.get(pendingId), isNull);
  if (committedId != null) {
    expect((await reopened.apiProducts.get(committedId))?.name, 'committed');
  }
  await reopened.close();
}

/// Every intentionally racing Future is observed as soon as it is created.
final class _Observed<T> {
  _Observed(Future<T> operation) {
    done = operation.then<void>(
      (value) {
        this.value = value;
        finished = true;
      },
      onError: (Object error, StackTrace _) {
        this.error = error;
        finished = true;
      },
    );
  }
  late final Future<void> done;
  T? value;
  Object? error;
  bool finished = false;
}
