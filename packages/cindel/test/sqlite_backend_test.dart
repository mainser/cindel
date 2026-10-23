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
import 'migration_suite.dart' as migration;
import 'native_binding_validation_suite.dart' as native_binding_validation;
import 'query_builder_suite.dart' as query_builder;
import 'schema_generation_suite.dart' as schema_generation;
import 'schema_version_suite.dart' as schema_version;
import 'sqlite_contract_suite.dart' as sqlite_contract;
import 'sqlite_projection_suite.dart' as sqlite_projection;
import 'sync_suite.dart' as sync;
import 'typed_collection_suite.dart' as typed_collection;

void main() {
  configureTestStorageBackend(CindelStorageBackend.sqlite);

  backup.main();
  backup_contract.main();
  bulk_ids.main();
  close.main();
  count.main();
  dart_distinct.main();
  find_first.main();
  links_backlinks.main();
  sqlite_contract.main();
  sqlite_projection.main();
  migration.main();
  native_binding_validation.main();
  schema_version.main();
  sync.main();
  query_builder.main();
  schema_generation.main();
  typed_collection.main();
}
