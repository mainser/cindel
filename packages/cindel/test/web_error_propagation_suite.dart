import 'package:cindel/cindel.dart';
import 'package:cindel/src/web/worker_bridge.dart';
import 'package:test/test.dart';

void main() {
  group('Web error propagation', () {
    // Scenario: A worker returns controlled failures for several concurrently
    // queued operations.
    // Covers:
    // - Error class/context mapping, per-request isolation and bridge
    // recovery.
    // Expected: Each failure identifies its own operation and cause; a
    // healthy request succeeds with no pending requests.
    test(
      'keeps queued failures isolated and allows the next request.',
      () async {
        // Arrange.
        final bridge = CindelWebWorkerBridge(
          'fixtures/error_transport_worker.js',
        );
        addTearDown(bridge.close);
        await bridge.init();
        final operations = [
          'queryPlanDocuments',
          'commitTransaction',
          'rollbackTransaction',
          'replaceLinks',
          'compact',
        ];
        // Act.
        final failures = await Future.wait([
          for (final operation in operations)
            bridge
                .send(operation: operation)
                .then<Object>(
                  (_) => fail('Expected failure'),
                  onError: (Object error) => error,
                ),
        ]);
        // Assert.
        for (var i = 0; i < operations.length; i++) {
          final error = failures[i] as CindelError;
          expect(error.operation, operations[i]);
          expect(error.backend, 'sqlite');
          expect(error.code, 'operation_failed');
          expect(error.cause, isA<CindelWebWorkerException>());
          expect(
            (error.cause! as CindelWebWorkerException).message,
            'controlled ${operations[i]} failure',
          );
        }
        expect(failures[0], isA<CindelQueryError>());
        expect(failures[1], isA<CindelTransactionError>());
        expect(failures[1].toString(), isNot(contains('rollbackTransaction')));
        await bridge.send(operation: 'healthy');
        expect(bridge.pendingCount, 0);
      },
    );
  });
}
