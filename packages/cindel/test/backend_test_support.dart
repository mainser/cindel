import 'dart:io';

import 'package:cindel/cindel.dart';

final CindelStorageBackend testStorageBackend = switch (Platform
    .environment['CINDEL_TEST_BACKEND']
    ?.toLowerCase()) {
  'mdbx' => CindelStorageBackend.mdbx,
  'sqlite' || null || '' => CindelStorageBackend.sqlite,
  final backend => throw UnsupportedError('Unknown test backend `$backend`.'),
};

Future<CindelDatabase> openTestDatabase({
  required String directory,
  Iterable<CindelCollectionSchema<dynamic>> schemas = const [],
  CindelMigrationCallback? migration,
  CindelStorageBackend? backend,
}) {
  return Cindel.open(
    directory: directory,
    schemas: schemas,
    migration: migration,
    backend: backend ?? testStorageBackend,
  );
}

Future<CindelDatabase> openTestDatabaseInMemory({
  Iterable<CindelCollectionSchema<dynamic>> schemas = const [],
  CindelMigrationCallback? migration,
  CindelStorageBackend? backend,
}) {
  return Cindel.openInMemory(
    schemas: schemas,
    migration: migration,
    backend: backend ?? testStorageBackend,
  );
}

Future<CindelMigrationReport> dryRunTestMigration({
  required String directory,
  Iterable<CindelCollectionSchema<dynamic>> schemas = const [],
  required CindelMigrationCallback migration,
  CindelStorageBackend? backend,
}) {
  return Cindel.dryRunMigration(
    directory: directory,
    schemas: schemas,
    migration: migration,
    backend: backend ?? testStorageBackend,
  );
}
