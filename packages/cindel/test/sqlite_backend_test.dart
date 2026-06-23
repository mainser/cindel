import 'package:cindel/cindel.dart';

import 'backup_suite.dart' as backup;
import 'backend_test_support.dart';
import 'links_backlinks_suite.dart' as links_backlinks;
import 'migration_suite.dart' as migration;
import 'native_binding_validation_suite.dart' as native_binding_validation;
import 'query_builder_suite.dart' as query_builder;
import 'schema_generation_suite.dart' as schema_generation;
import 'schema_version_suite.dart' as schema_version;
import 'sqlite_contract_suite.dart' as sqlite_contract;
import 'sync_suite.dart' as sync;
import 'typed_collection_suite.dart' as typed_collection;

void main() {
  configureTestStorageBackend(CindelStorageBackend.sqlite);

  backup.main();
  links_backlinks.main();
  sqlite_contract.main();
  migration.main();
  native_binding_validation.main();
  schema_version.main();
  sync.main();
  query_builder.main();
  schema_generation.main();
  typed_collection.main();
}
