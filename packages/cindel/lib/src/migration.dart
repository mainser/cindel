import 'dart:async';

import 'database.dart';

/// Callback used to migrate data before a new schema manifest is committed.
typedef CindelMigrationCallback =
    FutureOr<void> Function(CindelMigration migration);

/// Migrates one document and returns the replacement document.
///
/// Return `null` to leave the document unchanged.
typedef CindelDocumentMigration =
    FutureOr<CindelDocument?> Function(int id, CindelDocument document);

/// One operation recorded while a migration callback runs.
final class CindelMigrationDiagnostic {
  /// Creates a migration diagnostic entry.
  const CindelMigrationDiagnostic({
    required this.operation,
    required this.collection,
    required this.affectedCount,
    this.details = const {},
  });

  /// Operation name, such as `renameField` or `rebuildIndexes`.
  final String operation;

  /// Collection affected by the operation.
  final String collection;

  /// Number of documents affected or inspected by the operation.
  final int affectedCount;

  /// Extra operation details useful for dry-run output.
  final Map<String, Object?> details;
}

/// Summary produced by a dry-run migration.
final class CindelMigrationReport {
  /// Creates a migration report.
  const CindelMigrationReport({
    required this.oldVersions,
    required this.diagnostics,
  });

  /// Schema versions observed before the migration callback ran.
  final Map<String, int?> oldVersions;

  /// Operations requested by the migration callback.
  final List<CindelMigrationDiagnostic> diagnostics;
}

/// Context passed to migration callbacks.
final class CindelMigration {
  /// Creates a migration context.
  CindelMigration({
    required CindelDatabase database,
    required Map<String, int?> oldVersions,
    bool dryRun = false,
  }) : _database = database,
       _oldVersions = Map.unmodifiable(oldVersions),
       _dryRun = dryRun;

  final CindelDatabase _database;
  final Map<String, int?> _oldVersions;
  final bool _dryRun;
  final List<CindelMigrationDiagnostic> _diagnostics = [];

  /// Database handle available during the migration.
  CindelDatabase get database => _database;

  /// Whether helper operations should only record diagnostics.
  bool get isDryRun => _dryRun;

  /// Schema versions observed before the migration callback ran.
  Map<String, int?> get oldVersions => _oldVersions;

  /// Operations recorded so far.
  List<CindelMigrationDiagnostic> get diagnostics {
    return List.unmodifiable(_diagnostics);
  }

  /// Returns the schema version observed before the migration callback started.
  int? oldVersion(String collection) => _oldVersions[collection];

  /// Reads the currently stored schema version for any collection.
  Future<int?> schemaVersion(String collection) {
    return _database.schemaVersion(collection);
  }

  /// Renames one persisted document field across a collection.
  Future<int> renameField(
    String collection, {
    required String from,
    required String to,
    bool overwrite = false,
  }) async {
    _checkName(collection, 'collection');
    _checkName(from, 'from');
    _checkName(to, 'to');
    if (from == to) {
      return 0;
    }

    var affected = 0;
    await backfillCollection(collection, (id, document) {
      if (!document.containsKey(from)) {
        return null;
      }
      if (!overwrite && document.containsKey(to)) {
        return null;
      }
      affected += 1;
      return {...document, to: document[from]}..remove(from);
    }, recordDiagnostic: false);

    _record(
      CindelMigrationDiagnostic(
        operation: 'renameField',
        collection: collection,
        affectedCount: affected,
        details: {'from': from, 'to': to, 'overwrite': overwrite},
      ),
    );
    return affected;
  }

  /// Moves every document from [from] to [to], preserving ids.
  Future<int> renameCollection(String from, String to) async {
    _checkName(from, 'from');
    _checkName(to, 'to');
    if (from == to) {
      return 0;
    }

    final ids = await _database.documentIds(from);
    if (!_dryRun && ids.isNotEmpty) {
      final documents = await _database.getAll(from, ids);
      final values = <int, CindelDocument>{};
      for (var index = 0; index < ids.length; index += 1) {
        final document = documents[index];
        if (document != null) {
          values[ids[index]] = document;
        }
      }
      if (values.isNotEmpty) {
        await _database.putAll(to, values);
        await _database.deleteAll(from, values.keys);
      }
    }

    _record(
      CindelMigrationDiagnostic(
        operation: 'renameCollection',
        collection: from,
        affectedCount: ids.length,
        details: {'to': to},
      ),
    );
    return ids.length;
  }

  /// Updates documents in [collection] with [migrate].
  Future<int> backfillCollection(
    String collection,
    CindelDocumentMigration migrate, {
    bool recordDiagnostic = true,
  }) async {
    _checkName(collection, 'collection');
    final ids = await _database.documentIds(collection);
    var affected = 0;

    for (final id in ids) {
      final document = await _database.get(collection, id);
      if (document == null) {
        continue;
      }
      final replacement = await migrate(id, Map<String, Object?>.of(document));
      if (replacement == null) {
        continue;
      }
      affected += 1;
      if (!_dryRun) {
        await _database.put(collection, id, replacement);
      }
    }

    if (recordDiagnostic) {
      _record(
        CindelMigrationDiagnostic(
          operation: 'backfillCollection',
          collection: collection,
          affectedCount: affected,
        ),
      );
    }
    return affected;
  }

  /// Rewrites documents so index entries match the target schema.
  Future<int> rebuildIndexes(String collection) async {
    _checkName(collection, 'collection');
    final ids = await _database.documentIds(collection);
    if (!_dryRun) {
      for (final id in ids) {
        final document = await _database.get(collection, id);
        if (document != null) {
          await _database.put(collection, id, document);
        }
      }
    }

    _record(
      CindelMigrationDiagnostic(
        operation: 'rebuildIndexes',
        collection: collection,
        affectedCount: ids.length,
      ),
    );
    return ids.length;
  }

  CindelMigrationReport toReport() {
    return CindelMigrationReport(
      oldVersions: _oldVersions,
      diagnostics: diagnostics,
    );
  }

  void _record(CindelMigrationDiagnostic diagnostic) {
    _diagnostics.add(diagnostic);
  }
}

void _checkName(String value, String name) {
  if (value.trim().isEmpty) {
    throw ArgumentError.value(value, name, 'Must not be empty.');
  }
}
