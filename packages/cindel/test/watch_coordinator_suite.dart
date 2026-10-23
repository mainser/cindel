import 'dart:async';

import 'package:cindel/src/watch_coordinator.dart';
import 'package:test/test.dart';

import 'watch_test_clock.dart';

void main() {
  group('shared watcher coordinator', () {
    // Scenario: Local metadata has no revision and several changes arrive together.
    // Covers: Shared revision lookup, merging, and local delivery before the timer.
    // Expected: A single current read fans the merged change out to every listener.
    test(
      'shares revision lookups for local changes without a revision.',
      () async {
        final fixture = _Fixture();
        final values = <int>[];
        final subscriptions = [
          for (var i = 0; i < 100; i++) fixture.watch().listen(values.add),
        ];
        await fixture.clock.advance(Duration.zero);
        fixture.revision = 1;
        fixture.coordinator.notify('items', _Change(null, {1}));
        await settleWatchMicrotasks();
        expect(values.where((value) => value == 1), hasLength(100));
        expect(fixture.reads, 2);
        for (final subscription in subscriptions) {
          await subscription.cancel();
        }
        await fixture.coordinator.close();
      },
    );

    // Scenario: An external poll and a local change arrive during a slow snapshot.
    // Covers: Unknown change metadata must dominate exact local ID shortcuts.
    // Expected: The following snapshot performs a full refresh.
    test('keeps external changes while coalescing local metadata.', () async {
      final fixture = _Fixture();
      final pending = Completer<int>();
      final changes = <Set<int>?>[];
      final subscription = fixture
          .watch(
            snapshot: (change) {
              changes.add(change?.ids);
              return changes.length == 2
                  ? pending.future
                  : Future.value(fixture.revision);
            },
          )
          .listen((_) {});
      await fixture.clock.advance(Duration.zero);
      fixture.notify(1, {1});
      fixture.revision = 2;
      await fixture.clock.advance(const Duration(milliseconds: 50));
      fixture.notify(3, {3});
      pending.complete(1);
      await settleWatchMicrotasks();
      expect(changes, [
        null,
        {1},
        null,
      ]);
      await subscription.cancel();
      await fixture.coordinator.close();
    });

    // Scenario: A snapshot is suspended when a transaction begins.
    // Covers: A completed snapshot must not be emitted through an active transaction.
    // Expected: It is refreshed after the transaction instead of acknowledging stale data.
    test('rechecks transaction state after a suspended snapshot.', () async {
      final fixture = _Fixture();
      final pending = Completer<int>();
      var snapshots = 0;
      final values = <int>[];
      final subscription = fixture
          .watch(
            snapshot: (_) {
              snapshots++;
              return snapshots == 1
                  ? pending.future
                  : Future.value(fixture.revision);
            },
          )
          .listen(values.add);
      await fixture.clock.advance(Duration.zero);
      fixture.allowed = false;
      pending.complete(0);
      await settleWatchMicrotasks();
      expect(values, isEmpty);
      fixture.revision = 1;
      fixture.allowed = true;
      await fixture.clock.advance(const Duration(milliseconds: 50));
      expect(values, [1]);
      await subscription.cancel();
      await fixture.coordinator.close();
    });

    for (final count in [1, 100, 1000]) {
      // Scenario: Many idle subscribers observe the same collection.
      // Covers: Shared initialization, cadence, one timer, and final cancellation.
      // Expected: 21 reads (initial + 20 polls), independently of subscriber count.
      test('shares revision reads across $count subscribers.', () async {
        final fixture = _Fixture();
        final subscriptions = [
          for (var i = 0; i < count; i++) fixture.watch().listen((_) {}),
        ];
        await fixture.clock.advance(const Duration(seconds: 1));
        expect(fixture.reads, 21);
        expect(fixture.clock.activeTimers, 1);
        expect(fixture.clock.peakTimers, 1);
        for (final subscription in subscriptions) {
          await subscription.cancel();
        }
        expect(fixture.coordinator.isEmpty, isTrue);
        expect(fixture.clock.activeTimers, 0);
        await fixture.clock.advance(const Duration(seconds: 1));
        expect(fixture.reads, 21);
        await fixture.coordinator.close();
      });
    }

    // Scenario: New subscriptions join between existing polling deadlines.
    // Covers: Cadence alignment and subscribers with different intervals.
    // Expected: Existing deadlines remain stable; slow subscribers retain theirs.
    test('aligns late subscribers and preserves mixed intervals.', () async {
      final fixture = _Fixture();
      final fast = <int>[];
      final slow = <int>[];
      final subscriptions = [
        fixture.watch().listen(fast.add),
        fixture
            .watch(interval: const Duration(milliseconds: 120))
            .listen(slow.add),
      ];
      await fixture.clock.advance(const Duration(milliseconds: 25));
      subscriptions.add(fixture.watch().listen((_) {}));
      await fixture.clock.advance(Duration.zero);
      expect(fixture.reads, 2);
      fixture.revision = 1;
      await fixture.clock.advance(const Duration(milliseconds: 25));
      expect(fast, [0, 1]);
      expect(slow, [0]);
      await subscriptions.removeAt(2).cancel();
      await fixture.clock.advance(const Duration(milliseconds: 70));
      expect(slow, [0, 1]);
      expect(fixture.reads, 5); // Initial, late initial, 50, 100, 120.
      await subscriptions.first.cancel();
      fixture.revision = 2;
      await fixture.clock.advance(const Duration(milliseconds: 120));
      expect(slow, [0, 1, 2]);
      expect(fixture.reads, 6);
      await subscriptions.last.cancel();
      await fixture.coordinator.close();
    });

    // Scenario: Two collections have many independent subscribers.
    // Covers: Collection isolation and one handle-level timer.
    // Expected: Reads scale with collections, not subscription count.
    test('shares only within each collection.', () async {
      final fixture = _Fixture();
      final subscriptions = [
        for (final name in ['a', 'b'])
          for (var i = 0; i < 100; i++)
            fixture.watch(collection: name).listen((_) {}),
      ];
      await fixture.clock.advance(const Duration(seconds: 1));
      expect(fixture.reads, 42);
      expect(fixture.clock.peakTimers, 1);
      for (final subscription in subscriptions) {
        await subscription.cancel();
      }
      await fixture.coordinator.close();
    });

    // Scenario: A Web-style revision request is slower than several intervals.
    // Covers: In-flight sharing, cancellation/re-subscription, and resource release.
    // Expected: One outstanding read, including when the last listener changes.
    test('never overlaps a collection revision read.', () async {
      final pending = Completer<int>();
      final fixture = _Fixture(read: () => pending.future);
      final first = fixture.watch().listen((_) {});
      await fixture.clock.advance(const Duration(milliseconds: 200));
      expect(fixture.reads, 1);
      await first.cancel();
      final values = <int>[];
      final second = fixture.watch().listen(values.add);
      await fixture.clock.advance(Duration.zero);
      expect(fixture.reads, 1);
      pending.complete(0);
      await settleWatchMicrotasks();
      expect(values, [0]);
      await second.cancel();
      expect(fixture.clock.activeTimers, 0);
      await fixture.coordinator.close();
    });

    // Scenario: Local commit metadata arrives before an older revision response.
    // Covers: Response invalidation and independent snapshot consumers.
    // Expected: The stale response does not trigger an old/duplicate snapshot.
    test('ignores a revision response superseded by a local commit.', () async {
      final pending = Completer<int>();
      final fixture = _Fixture(read: () => pending.future);
      final values = <int>[];
      final subscription = fixture.watch().listen(values.add);
      await fixture.clock.advance(Duration.zero);
      fixture.notify(2, {2});
      await settleWatchMicrotasks();
      pending.complete(0);
      await settleWatchMicrotasks();
      expect(values, [2]);
      expect(fixture.reads, 1);
      await subscription.cancel();
      await fixture.coordinator.close();
    });

    // Scenario: Changes accumulate while an initial snapshot is suspended.
    // Covers: Merging changed IDs, lazy priming, and isolation of slow consumers.
    // Expected: All changed IDs survive and other subscribers receive updates.
    test('merges changes during slow lazy initialization.', () async {
      final fixture = _Fixture();
      final pending = Completer<int>();
      final seenChanges = <Set<int>?>[];
      final slowValues = <int>[];
      final fastValues = <int>[];
      final slow = fixture
          .watch(
            immediate: false,
            snapshot: (change) {
              seenChanges.add(change?.ids);
              return seenChanges.length == 1
                  ? pending.future
                  : Future.value(fixture.revision);
            },
          )
          .listen(slowValues.add);
      final fast = fixture.watch().listen(fastValues.add);
      await fixture.clock.advance(Duration.zero);
      fixture.notify(1, {1});
      fixture.notify(2, {2});
      fixture.notify(3, {3});
      await settleWatchMicrotasks();
      expect(fastValues.last, 3);
      expect(slowValues, isEmpty);
      pending.complete(0);
      await settleWatchMicrotasks();
      expect(seenChanges, [
        null,
        {1, 2, 3},
      ]);
      expect(slowValues, [3]);
      await slow.cancel();
      await fast.cancel();
      await fixture.coordinator.close();
    });

    // Scenario: A shared revision read fails once, then succeeds unchanged.
    // Covers: Error fan-out, retained causes, retry cadence, and no busy loop.
    // Expected: Each listener receives the same error and then initializes.
    test('recovers from shared revision failures.', () async {
      final failure = StateError('controlled revision failure');
      var attempts = 0;
      final fixture = _Fixture(
        read: () {
          if (attempts++ == 0) throw failure;
          return 0;
        },
      );
      final errors = <Object>[];
      final values = <int>[];
      final subscriptions = [
        for (var i = 0; i < 100; i++)
          fixture.watch().listen(values.add, onError: errors.add),
      ];
      await fixture.clock.advance(Duration.zero);
      expect(errors, hasLength(100));
      expect(errors.every((error) => identical(error, failure)), isTrue);
      expect(fixture.reads, 1);
      await fixture.clock.advance(const Duration(milliseconds: 50));
      expect(values, List.filled(100, 0));
      expect(fixture.reads, 2);
      for (final subscription in subscriptions) {
        await subscription.cancel();
      }
      await fixture.coordinator.close();
    });

    // Scenario: A snapshot fails and the next commit concerns another ID.
    // Covers: Snapshot retry without acknowledging failed data, and exact filters.
    // Expected: The failed snapshot is retried rather than skipped by metadata.
    test(
      'retries a failed snapshot before applying local ID shortcuts.',
      () async {
        final fixture = _Fixture();
        var fail = false;
        final errors = <Object>[];
        final values = <int>[];
        final subscription = fixture
            .watch(
              shouldRead: (change) => change.ids.contains(1),
              snapshot: (_) async {
                if (fail) {
                  fail = false;
                  throw StateError('controlled snapshot failure');
                }
                return fixture.revision;
              },
            )
            .listen(values.add, onError: errors.add);
        await fixture.clock.advance(Duration.zero);
        fail = true;
        fixture.notify(1, {1});
        await settleWatchMicrotasks();
        expect(errors, hasLength(1));
        fixture.notify(2, {9});
        await settleWatchMicrotasks();
        expect(values, [0, 2]);
        await subscription.cancel();
        await fixture.coordinator.close();
      },
    );

    // Scenario: A transaction suspends polling while storage revisions change.
    // Covers: No reads/initial emissions during a transaction and later recovery.
    // Expected: Subscriptions resume without leaking an uncommitted snapshot.
    test('defers initialization and polling during transactions.', () async {
      final fixture = _Fixture()..allowed = false;
      final values = <int>[];
      final subscription = fixture.watch().listen(values.add);
      await fixture.clock.advance(const Duration(milliseconds: 200));
      expect(fixture.reads, 0);
      fixture.allowed = true;
      await fixture.clock.advance(const Duration(milliseconds: 50));
      expect(values, [0]);
      fixture.allowed = false;
      fixture.revision = 1;
      await fixture.clock.advance(const Duration(milliseconds: 200));
      expect(values, [0]);
      fixture.allowed = true;
      await fixture.clock.advance(const Duration(milliseconds: 50));
      expect(values, [0, 1]);
      await subscription.cancel();
      await fixture.coordinator.close();
    });

    // Scenario: Close begins while a revision read is still in flight.
    // Covers: Timer release, idempotent close, and suppression of late errors.
    // Expected: Close finishes without waiting for the read; no late event escapes.
    test('stops before close and ignores in-flight failures.', () async {
      final pending = Completer<int>();
      final fixture = _Fixture(read: () => pending.future);
      final errors = <Object>[];
      final values = <int>[];
      fixture.watch().listen(values.add, onError: errors.add);
      await fixture.clock.advance(Duration.zero);
      final close = fixture.coordinator.close();
      expect(identical(close, fixture.coordinator.close()), isTrue);
      await close;
      pending.completeError(StateError('late read failure'));
      await settleWatchMicrotasks();
      expect(errors, isEmpty);
      expect(values, isEmpty);
      expect(fixture.clock.activeTimers, 0);
      expect(fixture.coordinator.isEmpty, isTrue);
    });

    // Scenario: A paused subscription delays stream completion during close.
    // Covers: Existing StreamController completion semantics and timer shutdown.
    // Expected: Polling stops immediately; cancellation allows close to complete.
    test('preserves paused subscription closure.', () async {
      final fixture = _Fixture();
      final subscription = fixture.watch().listen((_) {});
      await fixture.clock.advance(Duration.zero);
      subscription.pause();
      var closed = false;
      final close = fixture.coordinator.close().then((_) => closed = true);
      await settleWatchMicrotasks();
      expect(closed, isFalse);
      expect(fixture.clock.activeTimers, 0);
      await subscription.cancel();
      await close;
      expect(closed, isTrue);
    });
  });
}

final class _Change {
  _Change(this.revision, this.ids);
  final int? revision;
  final Set<int> ids;
}

final class _Fixture {
  _Fixture({FutureOr<int> Function()? read}) {
    coordinator = CindelWatchCoordinator<_Change>(
      readRevision: (_) {
        reads++;
        return read == null ? revision : read();
      },
      shouldPoll: () => allowed,
      revisionOf: (change) => change.revision,
      mergeChanges: (left, right) =>
          _Change(right.revision, {...left.ids, ...right.ids}),
      now: () => clock.now,
      createTimer: clock.timer,
    );
  }
  final clock = WatchTestClock();
  late final CindelWatchCoordinator<_Change> coordinator;
  int reads = 0;
  int revision = 0;
  bool allowed = true;

  void notify(int value, Set<int> ids) {
    revision = value;
    coordinator.notify('items', _Change(value, ids));
  }

  Stream<int> watch({
    String collection = 'items',
    Duration interval = const Duration(milliseconds: 50),
    bool immediate = true,
    bool Function(_Change)? shouldRead,
    Future<int> Function(_Change?)? snapshot,
  }) => coordinator.watch<int>(
    collection,
    pollInterval: interval,
    fireImmediately: immediate,
    shouldReadChange: shouldRead ?? (_) => true,
    readSnapshot: snapshot ?? (_) async => revision,
    areSnapshotsEqual: (a, b) => a == b,
  );
}
