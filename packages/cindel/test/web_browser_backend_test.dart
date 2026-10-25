@TestOn('browser')
library;

import 'watch_coordinator_suite.dart' as watcher_coordinator;
import 'package:cindel/cindel.dart';
import 'type_compatibility_suite.dart';
import 'web_watch_contract_suite.dart' as watch_contract;
import 'shared_watchers_suite.dart' as shared_watchers;
import 'sqlite_revision_suite.dart' as persistent_revisions;
import 'web_watch_polling_suite.dart' as web_watch_polling;
import 'web_error_propagation_suite.dart' as web_errors;
import 'error_propagation_suite.dart' as errors;

import 'relation_lifecycle_suite.dart' as relation_lifecycle;
import 'migration_atomic_suite.dart' as atomic_migrations;
import 'backup_contract_suite.dart' as backup_contract;
import 'package:test/test.dart';

import 'close_suite.dart' as close;
import 'bulk_id_suite.dart' as bulk_ids;
import 'count_suite.dart' as count;
import 'dart_distinct_suite.dart' as dart_distinct;
import 'find_first_suite.dart' as find_first;
import 'get_all_transaction_suite.dart' as get_all_transactions;
import 'query_public_contract_suite.dart' as query_public_contract;
import 'sqlite_id_suite.dart' as ids;
import 'sqlite_projection_suite.dart' as sqlite_projection;
import 'web_close_additional_suite.dart' as web_close;
import 'web_worker_close_suite.dart' as worker_close;

void main() {
  runTypeCompatibility(CindelStorageBackend.sqlite);
  watch_contract.main();
  persistent_revisions.main(concurrentHandles: false);
  watcher_coordinator.main();
  shared_watchers.main(includeExternalHandle: false);
  errors.main();
  web_errors.main();
  web_watch_polling.main();
  atomic_migrations.main(concurrentHandles: false);
  relation_lifecycle.main();
  backup_contract.main(includeSameDirectoryHandles: false);
  // The public scenarios run unchanged through Cindel's conditional exports.
  // The OPFS access-handle pool belongs to a Worker and cannot be opened by
  // two simultaneous Workers for the same origin. That storage restriction
  // is independent of close; native tests cover shared-directory handles.
  close.main(includeSameDirectoryHandles: false);
  ids.main(includeSameDirectoryHandles: false);
  bulk_ids.main(includeSameDirectoryHandles: false);
  count.main(includeSameDirectoryHandles: false);
  dart_distinct.main();
  sqlite_projection.main(includeSameDirectoryHandles: false);
  find_first.main();
  get_all_transactions.main();
  query_public_contract.main();
  web_close.main();
  worker_close.main();
}
