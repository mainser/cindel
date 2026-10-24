import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'native/wire.dart' if (dart.library.js_interop) 'web/wire.dart';

import 'database.dart' if (dart.library.js_interop) 'web/database.dart';
import 'schema.dart';
import 'migration_reader.dart'
    if (dart.library.js_interop) 'web/migration_reader.dart';
import 'typed_collection.dart'
    if (dart.library.js_interop) 'web/typed_collection.dart';

/// Callback used by [CindelMigrationStep].
typedef CindelMigrationCallback =
    FutureOr<void> Function(CindelMigrationContext context);

/// Database-level migration plan executed by `Cindel.open`.
final class CindelMigrationPlan {
  /// Creates a migration plan that advances the database to [targetVersion].
  CindelMigrationPlan({
    required this.targetVersion,
    required Iterable<CindelMigrationStep> steps,
    this.baselineVersion = 0,
    this.compactOnSuccess = true,
  }) : steps = List.unmodifiable(steps) {
    if (targetVersion < 0) {
      throw ArgumentError.value(
        targetVersion,
        'targetVersion',
        'Must not be negative.',
      );
    }
    if (baselineVersion < 0) {
      throw ArgumentError.value(
        baselineVersion,
        'baselineVersion',
        'Must not be negative.',
      );
    }
  }

  /// Final data version expected after all migrations complete.
  final int targetVersion;

  /// Version to assume for a database that has schemas but no migration marker.
  final int baselineVersion;

  /// Ordered migration steps.
  final List<CindelMigrationStep> steps;

  /// Whether to compact the backend after a successful migration run.
  final bool compactOnSuccess;

  /// Runs this plan for `Cindel.open`.
  ///
  /// This is public so the native and Web database facades can share one
  /// implementation. Application code should usually pass the plan to
  /// `Cindel.open` instead of calling this method directly.
  Future<void> run({
    required String directory,
    required Iterable<CindelCollectionSchema<dynamic>> targetSchemas,
    required Object backend,
  }) async {
    final storageBackend = backend as CindelStorageBackend;
    final targetSchemaList = List<CindelCollectionSchema<dynamic>>.unmodifiable(
      targetSchemas,
    );
    final schemaNames = {
      for (final schema in targetSchemaList) schema.name,
      for (final step in steps)
        for (final schema in step.openSchemas) schema.name,
      for (final step in steps)
        for (final schema in step.targetSchemas ?? const []) schema.name,
    };

    final metadataDatabase = await CindelDatabase.open(
      directory: directory,
      backend: storageBackend,
    );
    int currentVersion;
    try {
      final storedVersion = await metadataDatabase.migrationVersion();
      var hasPersistedSchema = false;
      for (final name in schemaNames) {
        if (await metadataDatabase.schemaVersion(name) != null) {
          hasPersistedSchema = true;
          break;
        }
      }
      currentVersion =
          storedVersion ??
          (hasPersistedSchema ? baselineVersion : targetVersion);
      if (storedVersion == null && !hasPersistedSchema) {
        await metadataDatabase.setMigrationVersion(targetVersion);
      }
    } finally {
      await metadataDatabase.close();
    }

    while (currentVersion < targetVersion) {
      final step = steps.singleWhere(
        (step) => step.fromVersion == currentVersion,
        orElse: () => throw StateError(
          'Missing Cindel migration step from version $currentVersion.',
        ),
      );
      if (step.toVersion <= step.fromVersion) {
        throw StateError(
          'Cindel migration steps must advance the data version.',
        );
      }
      if (step.toVersion > targetVersion) {
        throw StateError(
          'Cindel migration step ${step.fromVersion}->${step.toVersion} '
          'exceeds target version $targetVersion.',
        );
      }

      final database = await CindelDatabase.open(
        directory: directory,
        backend: storageBackend,
      );
      final context = CindelMigrationContext._(
        database: database,
        fromVersion: step.fromVersion,
        toVersion: step.toVersion,
        targetSchemas: step.targetSchemas ?? targetSchemaList,
      );
      try {
        final token =
            '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 30)}';
        await database.beginMigrationStep(step.openSchemas, token);
        final snapshotVersion = await database.migrationVersion();
        if (snapshotVersion != null && snapshotVersion != step.fromVersion) {
          throw StateError(
            'Migration source version changed before preparation.',
          );
        }
        await step.verifyBefore?.call(context);
        await step.migrate(context);
        if (!context.targetSchemasRegistered) {
          await context.registerTargetSchemas();
        }
        await database.cleanupOrphanLinks();
        await step.verifyAfter?.call(context);
        await cindelMigrationCommand(database.backupCommand, {
          'op': 'migration_commit',
          'version': step.toVersion,
        });
        if (compactOnSuccess) {
          try {
            await database.compact();
          } catch (error) {
            throw CindelMigrationMaintenanceError(step.toVersion, error);
          }
        }
      } finally {
        await database.close();
      }
      currentVersion = step.toVersion;
    }

    if (currentVersion != targetVersion) {
      throw StateError(
        'Cindel migration ended at version $currentVersion, expected '
        '$targetVersion.',
      );
    }
  }
}

/// One version-to-version migration step.
final class CindelMigrationStep {
  /// Creates a migration step from [fromVersion] to [toVersion].
  CindelMigrationStep({
    required this.fromVersion,
    required this.toVersion,
    required Iterable<CindelCollectionSchema<dynamic>> openSchemas,
    Iterable<CindelCollectionSchema<dynamic>>? targetSchemas,
    this.verifyBefore,
    required this.migrate,
    this.verifyAfter,
  }) : openSchemas = List.unmodifiable(openSchemas),
       targetSchemas = targetSchemas == null
           ? null
           : List.unmodifiable(targetSchemas);

  /// Data version expected before this step starts.
  final int fromVersion;

  /// Data version persisted after this step succeeds.
  final int toVersion;

  /// Schemas used to open and read the database before rewriting data.
  final List<CindelCollectionSchema<dynamic>> openSchemas;

  /// Schemas registered by [CindelMigrationContext.registerTargetSchemas].
  final List<CindelCollectionSchema<dynamic>>? targetSchemas;

  /// Optional verification callback executed before [migrate].
  final CindelMigrationCallback? verifyBefore;

  /// Migration callback. It should export old data, register target schemas,
  /// and import rewritten target data.
  final CindelMigrationCallback migrate;

  /// Optional verification callback executed after [migrate].
  final CindelMigrationCallback? verifyAfter;
}

/// Context passed to Cindel data migration callbacks.
final class CindelMigrationContext {
  CindelMigrationContext._({
    required this.database,
    required this.fromVersion,
    required this.toVersion,
    required Iterable<CindelCollectionSchema<dynamic>> targetSchemas,
  }) : targetSchemas = List.unmodifiable(targetSchemas);

  /// Database handle used by the running migration step.
  final CindelDatabase database;

  /// Source data version for this step.
  final int fromVersion;

  /// Target data version for this step.
  final int toVersion;

  /// Schemas that will be registered as the target shape.
  final List<CindelCollectionSchema<dynamic>> targetSchemas;

  bool _targetSchemasRegistered = false;

  /// Whether [registerTargetSchemas] has already run.
  bool get targetSchemasRegistered => _targetSchemasRegistered;

  /// Registers the target schemas in migrated mode.
  Future<void> registerTargetSchemas() async {
    if (_targetSchemasRegistered) {
      return;
    }
    await database.registerMigratedSchemas(targetSchemas);
    _targetSchemasRegistered = true;
  }

  /// Reads the original step snapshot in ascending ID order, including after
  /// target schemas have been registered. Retains at most one native page.
  /// The caller may retain yielded objects; that memory is outside this bound.
  Stream<T> streamObjects<T>(
    CindelCollectionSchema<T> schema, {
    int batchSize = 100,
  }) async* {
    _checkBatchSize(batchSize);
    int? after;
    while (true) {
      final bytes = await cindelMigrationCommand(database.backupCommand, {
        'op': 'migration_source',
        'collection': schema.name,
        'after': after,
        'limit': batchSize.clamp(1, 4096),
      });
      final page = decodeDocumentWriteBatch(bytes);
      if (page.isEmpty) break;
      for (final row in page) {
        final object = cindelReadMigrationObject(
          schema,
          row.id,
          row.bytes,
          sqlite: database.backend == CindelStorageBackend.sqlite,
        );
        schema.bindLinks?.call(database, schema, object);
        yield object;
      }
      after = page.last.id;
    }
  }

  /// Streams original documents without retaining the collection.
  Stream<CindelDocument> streamDocuments<T>(
    CindelCollectionSchema<T> schema, {
    int batchSize = 100,
  }) async* {
    await for (final object in streamObjects(schema, batchSize: batchSize)) {
      yield {
        ...schema.toDocument(object),
        if (schema.getId != null) schema.idField: schema.getId!(object),
      };
    }
  }

  /// Materializes all original objects. Use [streamObjects] for bounded memory.
  Future<List<T>> exportObjects<T>(
    CindelCollectionSchema<T> schema, {
    int batchSize = 100,
  }) => streamObjects(schema, batchSize: batchSize).toList();

  /// Materializes all original documents. Use [streamDocuments] for bounded memory.
  Future<List<CindelDocument>> exportDocuments<T>(
    CindelCollectionSchema<T> schema, {
    int batchSize = 100,
  }) => streamDocuments(schema, batchSize: batchSize).toList();

  /// Consumes an iterable lazily, committing only to the private workspace.
  Future<void> importObjects<T>(
    CindelCollectionSchema<T> schema,
    Iterable<T> objects, {
    int batchSize = 100,
  }) => importObjectStream(
    schema,
    Stream<T>.fromIterable(objects),
    batchSize: batchSize,
  );

  /// Imports an asynchronous transformation with at most [batchSize] objects
  /// retained by this helper. The whole step is published only after verification.
  Future<void> importObjectStream<T>(
    CindelCollectionSchema<T> schema,
    Stream<T> objects, {
    int batchSize = 100,
  }) async {
    _checkBatchSize(batchSize);
    var batch = <T>[];
    Future<void> flush() async {
      if (batch.isEmpty) return;
      await database.writeTxn(
        () => database.typedCollection(schema).putAll(batch),
      );
      batch = <T>[];
    }

    await for (final object in objects) {
      batch.add(object);
      if (batch.length == batchSize) await flush();
    }
    await flush();
  }

  /// Imports documents from a stream without materializing the input.
  Future<void> importDocumentStream<T>(
    CindelCollectionSchema<T> schema,
    Stream<CindelDocument> documents, {
    int batchSize = 100,
  }) => importObjectStream(
    schema,
    documents.map((document) {
      final object = schema.fromDocument(document);
      final id = document[schema.idField];
      if (id is int) schema.setId?.call(object, id);
      return object;
    }),
    batchSize: batchSize,
  );

  /// Imports map-shaped Cindel [documents] into [schema] in batches.
  Future<void> importDocuments<T>(
    CindelCollectionSchema<T> schema,
    Iterable<CindelDocument> documents, {
    int batchSize = 100,
  }) {
    return importObjects(
      schema,
      documents.map((document) {
        final object = schema.fromDocument(document);
        final id = document[schema.idField];
        if (id is int && schema.setId != null) {
          schema.setId!(object, id);
        }
        return object;
      }),
      batchSize: batchSize,
    );
  }
}

void _checkBatchSize(int batchSize) {
  if (batchSize <= 0) {
    throw ArgumentError.value(
      batchSize,
      'batchSize',
      'Must be greater than zero.',
    );
  }
}

/// The data migration committed successfully, but subsequent maintenance failed.
/// Reopening skips the committed step; callers must not repeat its external effects.
final class CindelMigrationMaintenanceError implements Exception {
  CindelMigrationMaintenanceError(this.committedVersion, this.cause);
  final int committedVersion;
  final Object cause;
  @override
  String toString() =>
      'Migration to $committedVersion committed; compaction failed: $cause';
}

/// Internal bounded maintenance protocol shared by native and Web facades.
Future<Uint8List> cindelMigrationCommand(
  Future<Uint8List> Function(Uint8List) send,
  Map<String, Object?> args, [
  Uint8List? payload,
]) async {
  WireValue encode(Object? value) => switch (value) {
    null => const WireValue.nullValue(),
    int v => WireValue.int(v),
    String v => WireValue.string(v),
    _ => throw StateError('Invalid migration argument.'),
  };
  final header = encodeFieldUpdates({
    for (final entry in args.entries) entry.key: encode(entry.value),
  });
  final request = Uint8List(4 + header.length + (payload?.length ?? 0));
  ByteData.sublistView(request).setUint32(0, header.length, Endian.little);
  request.setRange(4, 4 + header.length, header);
  if (payload != null) {
    request.setRange(4 + header.length, request.length, payload);
  }
  final response = await send(request);
  if (response.isEmpty || response[0] != 0) {
    throw StateError(
      response.isEmpty
          ? 'Empty migration response.'
          : utf8.decode(response.sublist(1)),
    );
  }
  return Uint8List.sublistView(response, 1);
}
