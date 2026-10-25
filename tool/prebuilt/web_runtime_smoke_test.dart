@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';

import 'package:cindel/cindel.dart';
import 'package:test/test.dart';
import 'package:web/web.dart' as web;

void main() {
  // Scenario: The packaged Web runtime is loaded by a probe worker and opened
  // through the public API.
  // Covers:
  // - Packaged Wasm ABI compatibility and repeated SQLite database
  // open/close.
  // Expected: The worker reports ABI 39 within the timeout and the same
  // database opens and closes twice without failure.
  test(
    'packaged Web runtime has ABI 39 and opens, closes and reopens',
    () async {
      // Arrange.
      final abi = Completer<int>();
      final probe = web.Worker(
        'abi_probe.js'.toJS,
        web.WorkerOptions(type: 'module'),
      );
      probe.onmessage = ((web.MessageEvent event) {
        abi.complete((event.data as JSNumber).toDartInt);
      }).toJS;
      probe.onerror = ((web.Event event) {
        event.preventDefault();
        if (!abi.isCompleted) {
          abi.completeError(StateError('Cannot initialize the packaged Wasm.'));
        }
      }).toJS;
      // Act / Assert.
      try {
        expect(await abi.future.timeout(const Duration(seconds: 15)), 39);
      } finally {
        probe.terminate();
      }

      final directory =
          'cindel-release-${DateTime.now().microsecondsSinceEpoch}';
      for (var attempt = 0; attempt < 2; attempt++) {
        final db = await Cindel.open(
          directory: directory,
          backend: CindelStorageBackend.sqlite,
        );
        await db.close();
      }
    },
  );
}
