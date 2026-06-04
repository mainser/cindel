import 'package:cindel/cindel.dart';

import 'backend_test_support.dart';
import 'in_memory_database_suite.dart' as in_memory_database;
import 'index_query_suite.dart' as index_query;
import 'native_bindings_suite.dart' as native_bindings;
import 'query_builder_suite.dart' as query_builder;
import 'schema_generation_suite.dart' as schema_generation;
import 'schema_version_suite.dart' as schema_version;
import 'transactions_suite.dart' as transactions;
import 'typed_collection_suite.dart' as typed_collection;
import 'watchers_suite.dart' as watchers;

void main() {
  configureTestStorageBackend(CindelStorageBackend.mdbx);

  in_memory_database.main();
  index_query.main();
  native_bindings.main(includeMdbxOnlyTests: true);
  query_builder.main(includeMdbxOnlyTests: true);
  schema_generation.main(includeMdbxOnlyTests: true);
  schema_version.main();
  transactions.main(includeMdbxOnlyTests: true);
  typed_collection.main();
  watchers.main();
}
