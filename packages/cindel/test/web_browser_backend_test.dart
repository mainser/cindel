@TestOn('browser')
library;

import 'package:test/test.dart';

import 'close_suite.dart' as close;
import 'bulk_id_suite.dart' as bulk_ids;
import 'find_first_suite.dart' as find_first;
import 'sqlite_id_suite.dart' as ids;
import 'web_close_additional_suite.dart' as web_close;
import 'web_worker_close_suite.dart' as worker_close;

void main() {
  // The public scenarios run unchanged through Cindel's conditional exports.
  // The OPFS access-handle pool belongs to a Worker and cannot be opened by
  // two simultaneous Workers for the same origin. That storage restriction
  // is independent of close; native tests cover shared-directory handles.
  close.main(includeSameDirectoryHandles: false);
  ids.main(includeSameDirectoryHandles: false);
  bulk_ids.main(includeSameDirectoryHandles: false);
  find_first.main();
  web_close.main();
  worker_close.main();
}
