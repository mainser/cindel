import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

int _directorySerial = 0;

/// The normal Cindel open call treats this string as its browser storage name.
Future<String> createCloseTestDirectory() async =>
    'cindel-close-${DateTime.now().microsecondsSinceEpoch}-${_directorySerial++}';

/// Removes only test-owned storage after every handle for a case has closed.
/// The Wasm access-handle pool has six initial file slots, shared by all named
/// databases in its `.opfs-sahpool` folder. Releasing this pool between cases
/// gives each test fresh storage, like native temporary-directory cleanup.
/// This helper is limited to the runner's isolated loopback origin/profile;
/// persisted rows are checked by reopening before teardown removes the pool.
Future<void> deleteCloseTestDirectory(String directory) async {
  final origin = Uri.base;
  if ((origin.host != 'localhost' && origin.host != '127.0.0.1') ||
      !origin.hasPort ||
      origin.port == 0) {
    throw StateError(
      'Browser close cleanup requires an isolated loopback origin.',
    );
  }
  final root = await web.window.navigator.storage.getDirectory().toDart;
  for (var attempt = 0; ; attempt += 1) {
    try {
      await root
          .removeEntry(
            '.opfs-sahpool',
            web.FileSystemRemoveOptions(recursive: true),
          )
          .toDart;
      return;
    } catch (error) {
      final description = error.toString();
      if (description.contains('NotFoundError')) return;
      // A just-terminated Worker can briefly retain an access-handle lock.
      // Retry only lock-release errors, never hide unrelated storage failures.
      if (attempt >= 9 ||
          (!description.contains('NoModificationAllowedError') &&
              !description.contains('InvalidStateError'))) {
        rethrow;
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }
}
