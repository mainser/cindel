import 'package:cindel/cindel.dart';

var _testStorageBackend = CindelStorageBackend.sqlite;

CindelStorageBackend get testStorageBackend => _testStorageBackend;

void configureTestStorageBackend(CindelStorageBackend backend) {
  _testStorageBackend = backend;
}

Future<CindelDatabase> openTestDatabase({
  required String directory,
  Iterable<CindelCollectionSchema<dynamic>> schemas = const [],
  CindelStorageBackend? backend,
  CindelSyncConfig? sync,
}) {
  return Cindel.open(
    directory: directory,
    schemas: schemas,
    backend: backend ?? testStorageBackend,
    sync: sync,
  );
}

Future<CindelDatabase> openTestDatabaseInMemory({
  Iterable<CindelCollectionSchema<dynamic>> schemas = const [],
  CindelStorageBackend? backend,
  CindelSyncConfig? sync,
}) {
  return Cindel.openInMemory(
    schemas: schemas,
    backend: backend ?? testStorageBackend,
    sync: sync,
  );
}
