import 'package:cindel/cindel.dart';

import 'backend_test_support.dart';
import 'mdbx_contract_suite.dart' as mdbx_contract;
import 'query_builder_suite.dart' as query_builder;
import 'schema_generation_suite.dart' as schema_generation;
import 'typed_collection_suite.dart' as typed_collection;

void main() {
  configureTestStorageBackend(CindelStorageBackend.mdbx);

  mdbx_contract.main();
  query_builder.main(includeMdbxOnlyTests: true);
  schema_generation.main(includeMdbxOnlyTests: true);
  typed_collection.main();
}
