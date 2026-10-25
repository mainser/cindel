import 'dart:async';

import 'package:cindel/src/watch_coordinator.dart';
import 'package:cindel/src/web/worker_bridge.dart';
import 'package:test/test.dart';

import 'watch_test_clock.dart';

void main() {
  group('shared watcher Web transport', () {
    // Scenario: 100 subscribers poll through an actual browser Worker.
    // Covers: Shared async revision requests and the serial Worker bridge.
    // Expected: The Worker receives 21 requests over 20 controlled polling cycles.
    test('sends one revision request per collection and cycle.', () async {
      // Arrange.
      final bridge = CindelWebWorkerBridge(
        'fixtures/close_transport_worker.js',
      );
      addTearDown(bridge.close);
      await bridge.init();
      final clock = WatchTestClock();
      var responses = 0;
      final coordinator = CindelWatchCoordinator<int>(
        readRevision: (_) async {
          await bridge.send(operation: 'collectionRevision');
          responses++;
          return 0;
        },
        shouldPoll: () => true,
        revisionOf: (revision) => revision,
        mergeChanges: (_, latest) => latest,
        now: () => clock.now,
        createTimer: clock.timer,
      );
      addTearDown(coordinator.close);
      for (var i = 0; i < 100; i++) {
        coordinator
            .watch<int>(
              'items',
              pollInterval: const Duration(milliseconds: 50),
              fireImmediately: true,
              shouldReadChange: (_) => true,
              readSnapshot: (_) async => 0,
              areSnapshotsEqual: (a, b) => a == b,
            )
            .listen((_) {});
      }
      // Act.
      for (var cycle = 0; cycle <= 20; cycle++) {
        await clock.advance(Duration(milliseconds: cycle == 0 ? 0 : 50));
        final deadline = DateTime.now().add(const Duration(seconds: 5));
        while (responses < cycle + 1) {
          if (DateTime.now().isAfter(deadline)) {
            throw TimeoutException('Worker response missing.');
          }
          await Future<void>.delayed(const Duration(milliseconds: 1));
        }
      }
      final count = await bridge.send(operation: 'requestCount');
      // The protocol fixture returns the zero-based request order independently
      // of the client counter: requestCount must be exactly request number 21.
      // Assert.
      expect(count.payload, '21:requestCount');
      expect(responses, 21);
      expect(clock.peakTimers, 1);
      await coordinator.close();
      expect(clock.activeTimers, 0);
      expect(bridge.pendingCount, 0);
    });
  });
}
