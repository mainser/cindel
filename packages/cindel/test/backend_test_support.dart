import 'dart:io';

import 'package:cindel/cindel.dart';

final CindelStorageBackend testStorageBackend = switch (Platform
    .environment['CINDEL_TEST_BACKEND']
    ?.toLowerCase()) {
  'mdbx' => CindelStorageBackend.mdbx,
  'default' => defaultCindelStorageBackend,
  'sqlite' || null || '' => CindelStorageBackend.sqlite,
  final backend => throw UnsupportedError('Unknown test backend `$backend`.'),
};

Future<CindelDatabase> openTestDatabase({
  required String directory,
  Iterable<CindelCollectionSchema<dynamic>> schemas = const [],
  CindelStorageBackend? backend,
}) {
  return Cindel.open(
    directory: directory,
    schemas: schemas,
    backend: backend ?? testStorageBackend,
  );
}

Future<CindelDatabase> openTestDatabaseInMemory({
  Iterable<CindelCollectionSchema<dynamic>> schemas = const [],
  CindelStorageBackend? backend,
}) {
  return Cindel.openInMemory(
    schemas: schemas,
    backend: backend ?? testStorageBackend,
  );
}
