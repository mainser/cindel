import 'dart:io';
import 'dart:isolate';

import 'package:test/test.dart';

Future<File> _packageFile(String packageUri) async {
  final uri = await Isolate.resolvePackageUri(Uri.parse(packageUri));
  if (uri == null) {
    throw StateError('Could not resolve $packageUri');
  }
  return File.fromUri(uri);
}

Future<String> _readPackageFile(String packageUri) async {
  return (await _packageFile(packageUri)).readAsString();
}

void main() {
  // Scenario: A Flutter Web app imports only the normal Cindel public library.
  // Covers:
  // - Conditional exports for the Web `Cindel.open(...)` facade.
  // - Conditional exports for the Web database and typed collection surfaces.
  // - Preventing a future split back into a separate app-facing Web library.
  // Expected: `package:cindel/cindel.dart` owns the Web application entrypoint.
  test(
    'package:cindel/cindel.dart owns the Web application entrypoint',
    () async {
      final source = await _readPackageFile('package:cindel/cindel.dart');

      expect(
        source,
        contains(
          "export 'src/cindel.dart' if (dart.library.js_interop) "
          "'src/web/cindel.dart';",
        ),
      );
      expect(
        source,
        contains(
          "export 'src/database.dart' if (dart.library.js_interop) "
          "'src/web/database.dart';",
        ),
      );
      expect(
        source,
        contains(
          "export 'src/typed_collection.dart'\n"
          "    if (dart.library.js_interop) 'src/web/typed_collection.dart';",
        ),
      );
    },
  );

  // Scenario: The old bridge-only Web library name is accidentally restored.
  // Covers:
  // - Public package surface cleanup after Web moved behind `Cindel.open(...)`.
  // - Keeping direct Worker access out of the application API.
  // Expected: No `cindel_web.dart` public entrypoint is present beside
  // `cindel.dart`.
  test('package:cindel/cindel_web.dart is not a public entrypoint', () async {
    final publicEntrypoint = await _packageFile('package:cindel/cindel.dart');
    final removedEntrypoint = File.fromUri(
      publicEntrypoint.uri.resolve('cindel_web.dart'),
    );

    expect(removedEntrypoint.existsSync(), isFalse);
  });

  // Scenario: The Web query facade drifts back to Dart-only execution.
  // Covers:
  // - Generated Web queries building native query plans.
  // - Worker-backed count, find, delete, update, projection, and aggregate
  //   operations.
  // Expected: Query execution uses the same Worker query-plan surface exposed
  // by the Web SQLite runtime when a generated SQLite-native schema can support
  // it.
  test(
    'web query facade routes generated queries through native plans',
    () async {
      final source = await _readPackageFile(
        'package:cindel/src/web/query.dart',
      );

      expect(source, contains('WireQueryPlan? _nativePlan'));
      expect(source, contains('queryNativePlanIds'));
      expect(source, contains('queryNativePlanCount'));
      expect(source, contains('deleteNativePlan'));
      expect(source, contains('updateNativePlan'));
      expect(source, contains('queryNativePlanProjection'));
      expect(source, contains('queryNativePlanAggregate'));
      expect(source, contains('queryNativePlanObjects'));
      expect(source, isNot(contains('collectionHasGenericDocuments')));
    },
  );

  // Scenario: Web drifts away from generated typed storage after the typed-only
  // contract was aligned with MDBX and SQLite native.
  // Covers:
  // - Old untyped methods being absent from the Web database facade.
  // - Generated typed collections using native rows for put/get/delete/watch.
  // - Query materialization using generated native readers.
  // Expected: No Web generated path calls the removed untyped facade methods.
  test('web generated APIs stay on generated typed storage', () async {
    final databaseSource = await _readPackageFile(
      'package:cindel/src/web/database.dart',
    );
    final querySource = await _readPackageFile(
      'package:cindel/src/web/query.dart',
    );
    final typedCollectionSource = await _readPackageFile(
      'package:cindel/src/web/typed_collection.dart',
    );

    expect(databaseSource, contains('getAllNativeBinaryDocuments'));
    expect(databaseSource, contains('CindelWebNativeDocumentReader'));
    expect(databaseSource, contains('queryNativePlanObjects'));
    expect(databaseSource, isNot(contains('Future<void> put(')));
    expect(databaseSource, isNot(contains('Future<void> putAll(')));
    expect(databaseSource, isNot(contains('Future<void> putMany(')));
    expect(databaseSource, isNot(contains('Future<CindelDocument?> get(')));
    expect(
      databaseSource,
      isNot(contains('Future<List<CindelDocument?>> getAll(')),
    );
    expect(databaseSource, isNot(contains('queryAll(')));
    expect(databaseSource, isNot(contains('documentsByIds(')));
    expect(
      databaseSource,
      isNot(contains('Future<List<CindelDocument>> queryEqual(')),
    );
    expect(databaseSource, isNot(contains('watchDocument(')));
    expect(databaseSource, isNot(contains('watchCollection(')));
    expect(databaseSource, isNot(contains('cindelEncodeGenericDocument')));
    expect(databaseSource, isNot(contains('cindelDecodeGenericDocument')));
    expect(databaseSource, contains('Future<void> deleteAll('));
    expect(databaseSource, isNot(contains('deleteAllNativeDocuments')));

    expect(typedCollectionSource, contains('getAllNativeBinaryDocuments'));
    expect(typedCollectionSource, contains('watchCollectionChanges'));
    expect(typedCollectionSource, isNot(contains('database.putAll(')));
    expect(typedCollectionSource, isNot(contains('database.getAll(')));
    expect(typedCollectionSource, contains('database.deleteAll('));
    expect(typedCollectionSource, isNot(contains('database.watchDocument(')));
    expect(typedCollectionSource, isNot(contains('database.watchCollection(')));

    expect(querySource, contains('queryNativePlanObjects'));
    expect(querySource, contains('_database.deleteAll('));
    expect(querySource, isNot(contains('database.documentsByIds')));
    expect(querySource, isNot(contains('database.queryAll(_schema.name)')));
  });

  // Scenario: Link/backlink support is added to native backends but Web drifts
  // out of parity.
  // Covers:
  // - Web database relation helper methods.
  // - Worker operation names for replacing forward links and loading forward
  //   or backlink ids.
  // Expected: SQLite Web/OPFS exposes the same relation operations as native
  // SQLite and MDBX.
  test('web exposes link and backlink worker contract', () async {
    final databaseSource = await _readPackageFile(
      'package:cindel/src/web/database.dart',
    );
    final publicEntrypoint = await _packageFile('package:cindel/cindel.dart');
    final workerSource = await File.fromUri(
      publicEntrypoint.uri.resolve('../web/cindel_worker.js'),
    ).readAsString();

    expect(databaseSource, contains('saveLinkIds'));
    expect(databaseSource, contains('loadLinkedObjects'));
    expect(databaseSource, contains('loadBacklinkObjects'));
    expect(workerSource, contains("case 'replaceLinks':"));
    expect(workerSource, contains("case 'forwardLinkIds':"));
    expect(workerSource, contains("case 'backlinkSourceIds':"));
  });

  // Scenario: Public migration tooling is added on native but Web drifts out of
  // parity.
  // Covers:
  // - `Cindel.open` accepting migration plans on Web.
  // - Web database exposing migration version, migrated schema registration,
  //   and compact operations.
  // - Worker operation names matching the Dart Web facade.
  // Expected: Web keeps the same migration/export/import/compact surface as
  // native callers.
  test('web exposes public migration tooling contract', () async {
    final publicSource = await _readPackageFile('package:cindel/cindel.dart');
    final cindelSource = await _readPackageFile(
      'package:cindel/src/web/cindel.dart',
    );
    final databaseSource = await _readPackageFile(
      'package:cindel/src/web/database.dart',
    );
    final publicEntrypoint = await _packageFile('package:cindel/cindel.dart');
    final workerSource = await File.fromUri(
      publicEntrypoint.uri.resolve('../web/cindel_worker.js'),
    ).readAsString();
    final packagedWorkerSource = await File.fromUri(
      publicEntrypoint.uri.resolve(
        '../../cindel_flutter_libs/web/cindel_worker.js',
      ),
    ).readAsString();

    expect(publicSource, contains("export 'src/migration.dart';"));
    expect(publicSource, contains("export 'src/backup.dart';"));
    expect(cindelSource, contains('CindelMigrationPlan? migrationPlan'));
    expect(databaseSource, contains('CindelMigrationPlan? migrationPlan'));
    expect(databaseSource, contains('Future<int?> migrationVersion()'));
    expect(databaseSource, contains('Future<void> setMigrationVersion'));
    expect(databaseSource, contains('Future<void> registerMigratedSchemas'));
    expect(databaseSource, contains('Future<void> compact()'));
    for (final source in [workerSource, packagedWorkerSource]) {
      expect(source, contains("case 'migrationVersion':"));
      expect(source, contains("case 'setMigrationVersion':"));
      expect(source, contains("case 'registerMigratedSchemas':"));
      expect(source, contains("case 'compact':"));
    }
  });

  // Scenario: Large export tooling needs bounded id scans on Web too.
  // Covers:
  // - Web database exposing the same id-page API as native.
  // - Worker operation names matching the Dart Web facade.
  // Expected: Web can page document ids without forcing a full id-list read.
  test('web exposes paged document id contract', () async {
    final databaseSource = await _readPackageFile(
      'package:cindel/src/web/database.dart',
    );
    final publicEntrypoint = await _packageFile('package:cindel/cindel.dart');
    final workerSource = await File.fromUri(
      publicEntrypoint.uri.resolve('../web/cindel_worker.js'),
    ).readAsString();
    final packagedWorkerSource = await File.fromUri(
      publicEntrypoint.uri.resolve(
        '../../cindel_flutter_libs/web/cindel_worker.js',
      ),
    ).readAsString();

    expect(databaseSource, contains('Future<List<int>> documentIdsPage'));
    for (final source in [workerSource, packagedWorkerSource]) {
      expect(source, contains("case 'documentIdsPage':"));
      expect(source, contains('documentIdsPage('));
    }
  });

  // Scenario: Full backup helpers are exported for Web without importing
  // `dart:io` from the shared backup API.
  // Covers:
  // - Public backup export from the normal package entrypoint.
  // - Conditional gzip helper import for native-only compression.
  // Expected: Web can use uncompressed JSONL backup streams through the same
  // package import.
  test('web exposes backup stream contract', () async {
    final publicSource = await _readPackageFile('package:cindel/cindel.dart');
    final backupSource = await _readPackageFile(
      'package:cindel/src/backup.dart',
    );

    expect(publicSource, contains("export 'src/backup.dart';"));
    expect(backupSource, contains('enum CindelBackupCompression'));
    expect(backupSource, contains('none,'));
    expect(backupSource, contains("if (dart.library.io)"));
    expect(backupSource, isNot(contains("import 'dart:io';")));
  });

  // Scenario: Web typed collections lose unique-index replacement semantics.
  // Covers:
  // - `putByUniqueIndex` and `putAllByUniqueIndex` reusing existing ids.
  // - Field and composite unique lookup hooks on the Web database facade.
  // Expected: Web generated APIs do not silently append duplicates when a
  // replace index should target the existing row.
  test('web typed collection reuses ids for unique replace indexes', () async {
    final collectionSource = await _readPackageFile(
      'package:cindel/src/web/typed_collection.dart',
    );
    final databaseSource = await _readPackageFile(
      'package:cindel/src/web/database.dart',
    );

    expect(collectionSource, contains('_reuseUniqueIndexId'));
    expect(collectionSource, contains('queryCompositeEqualIds'));
    expect(collectionSource, contains('queryEqualIds'));
    expect(databaseSource, contains('Future<List<int>> queryEqualIds'));
    expect(
      databaseSource,
      contains('Future<List<int>> queryCompositeEqualIds'),
    );
    expect(databaseSource, contains('WireQuerySource.indexEqual'));
  });

  // Scenario: Web watchers regress to unsupported stubs or stop consuming Worker
  // change sets.
  // Covers:
  // - Worker `takeChanges` and `collectionRevision` feeding Dart watchers.
  // - Collection/query/typed watcher APIs using the same change stream.
  // - Closing a Web database closing active watcher streams.
  // Expected: Single-tab Web watchers are wired through the Web database
  // facade and no longer throw the old UnsupportedError.
  test('web single-tab watchers are wired to Worker change sets', () async {
    final databaseSource = await _readPackageFile(
      'package:cindel/src/web/database.dart',
    );
    final querySource = await _readPackageFile(
      'package:cindel/src/web/query.dart',
    );
    final typedCollectionSource = await _readPackageFile(
      'package:cindel/src/web/typed_collection.dart',
    );

    expect(
      '$databaseSource$querySource$typedCollectionSource',
      isNot(contains('Cindel Web watchers are not available yet.')),
    );
    expect(databaseSource, contains("await _sendBytes('takeChanges'"));
    expect(databaseSource, contains("'collectionRevision'"));
    expect(databaseSource, contains('Stream<CindelChangeSet>'));
    expect(databaseSource, contains('await _closeWatchers();'));
    expect(databaseSource, contains('_controller.addError'));
    expect(querySource, contains('watchCollectionChanges'));
    expect(querySource, contains('_watchMatchingDocuments'));
    expect(querySource, contains('_watchMatchingIds'));
    expect(typedCollectionSource, contains('watchCollectionChanges'));
    expect(typedCollectionSource, contains('watchObject('));
    expect(typedCollectionSource, contains('watchCollection('));
  });
}
