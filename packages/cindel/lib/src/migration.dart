import 'dart:async';

import 'database.dart' if (dart.library.js_interop) 'web/database.dart';
import 'schema.dart';
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

      final database = await CindelDatabase.openForMigration(
        directory: directory,
        schemas: step.openSchemas,
        backend: storageBackend,
      );
      final context = CindelMigrationContext._(
        database: database,
        fromVersion: step.fromVersion,
        toVersion: step.toVersion,
        targetSchemas: step.targetSchemas ?? targetSchemaList,
      );
      try {
        await step.verifyBefore?.call(context);
        await step.migrate(context);
        if (!context.targetSchemasRegistered) {
          await context.registerTargetSchemas();
        }
        await step.verifyAfter?.call(context);
        await database.setMigrationVersion(step.toVersion);
        if (compactOnSuccess) {
          await database.compact();
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

  /// Exports all typed objects in [schema] in id order.
  Future<List<T>> exportObjects<T>(
    CindelCollectionSchema<T> schema, {
    int batchSize = 100,
  }) async {
    _checkBatchSize(batchSize);
    final ids = await database.documentIds(schema.name);
    final objects = <T>[];
    for (var offset = 0; offset < ids.length; offset += batchSize) {
      final end = offset + batchSize < ids.length
          ? offset + batchSize
          : ids.length;
      final batch = await database
          .typedCollection(schema)
          .getAll(ids.sublist(offset, end));
      for (final object in batch) {
        if (object != null) {
          objects.add(object);
        }
      }
    }
    return objects;
  }

  /// Exports all documents in [schema] as map-shaped Cindel documents.
  Future<List<CindelDocument>> exportDocuments<T>(
    CindelCollectionSchema<T> schema, {
    int batchSize = 100,
  }) async {
    final objects = await exportObjects(schema, batchSize: batchSize);
    return [
      for (final object in objects)
        {
          if (schema.getId != null) schema.idField: schema.getId!(object),
          ...schema.toDocument(object),
        },
    ];
  }

  /// Imports typed [objects] into [schema] in batches.
  Future<void> importObjects<T>(
    CindelCollectionSchema<T> schema,
    Iterable<T> objects, {
    int batchSize = 100,
  }) async {
    _checkBatchSize(batchSize);
    final list = objects is List<T> ? objects : objects.toList();
    for (var offset = 0; offset < list.length; offset += batchSize) {
      final end = offset + batchSize < list.length
          ? offset + batchSize
          : list.length;
      final batch = list.sublist(offset, end);
      await database.writeTxn(() async {
        await database.typedCollection(schema).putAll(batch);
      });
    }
  }

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
