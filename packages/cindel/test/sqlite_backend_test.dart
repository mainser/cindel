import 'package:cindel/cindel.dart';

import 'backend_test_support.dart';
import 'query_builder_suite.dart' as query_builder;
import 'schema_generation_suite.dart' as schema_generation;
import 'sqlite_contract_suite.dart' as sqlite_contract;
import 'typed_collection_suite.dart' as typed_collection;

void main() {
  configureTestStorageBackend(CindelStorageBackend.sqlite);

  sqlite_contract.main();
  query_builder.main();
  schema_generation.main();
  typed_collection.main();
}
