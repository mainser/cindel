import 'package:cindel/cindel.dart';

import 'backup_suite.dart' as backup;
import 'backend_test_support.dart';
import 'migration_suite.dart' as migration;
import 'query_builder_suite.dart' as query_builder;
import 'schema_generation_suite.dart' as schema_generation;
import 'schema_version_suite.dart' as schema_version;
import 'sqlite_contract_suite.dart' as sqlite_contract;
import 'typed_collection_suite.dart' as typed_collection;

void main() {
  configureTestStorageBackend(CindelStorageBackend.sqlite);

  backup.main();
  sqlite_contract.main();
  migration.main();
  schema_version.main();
  query_builder.main();
  schema_generation.main();
  typed_collection.main();
}
