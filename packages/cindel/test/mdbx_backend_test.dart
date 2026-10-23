import 'relation_lifecycle_suite.dart' as relation_lifecycle;
import 'migration_atomic_suite.dart' as atomic_migrations;
import 'backup_contract_suite.dart' as backup_contract;
import 'package:cindel/cindel.dart';

import 'backup_suite.dart' as backup;
import 'backend_test_support.dart';
import 'bulk_id_suite.dart' as bulk_ids;
import 'close_suite.dart' as close;
import 'count_suite.dart' as count;
import 'dart_distinct_suite.dart' as dart_distinct;
import 'find_first_suite.dart' as find_first;
import 'links_backlinks_suite.dart' as links_backlinks;
import 'mdbx_contract_suite.dart' as mdbx_contract;
import 'mdbx_distinct_suite.dart' as distinct;
import 'mdbx_id_scan_suite.dart' as id_scan;
import 'mdbx_index_order_suite.dart' as index_order;
import 'mdbx_partial_selection_suite.dart' as partial_selection;
import 'migration_suite.dart' as migration;
import 'query_builder_suite.dart' as query_builder;
import 'schema_generation_suite.dart' as schema_generation;
import 'schema_version_suite.dart' as schema_version;
import 'sync_suite.dart' as sync;
import 'typed_collection_suite.dart' as typed_collection;

void main() {
  configureTestStorageBackend(CindelStorageBackend.mdbx);

  backup.main();
  atomic_migrations.main();
  relation_lifecycle.main();
  backup_contract.main();
  bulk_ids.main();
  close.main();
  count.main();
  dart_distinct.main();
  find_first.main();
  links_backlinks.main();
  mdbx_contract.main();
  distinct.main();
  id_scan.main();
  index_order.main();
  partial_selection.main();
  migration.main();
  schema_version.main();
  sync.main();
  query_builder.main();
  schema_generation.main(includeMdbxOnlyTests: true);
  typed_collection.main();
}
