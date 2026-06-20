import 'cindel_error.dart';
import 'database.dart';
import 'migration.dart';
import 'schema.dart';
import 'text.dart';

/// Entry point for opening Cindel databases.
abstract final class Cindel {
  /// Opens a database stored under [directory].
  ///
  /// When [migrationPlan] is provided, Cindel runs the plan before registering
  /// [schemas] as the final target shape.
  ///
  /// Throws an [ArgumentError] when [directory] is empty and a
  /// [CindelOpenError] when the native engine cannot be opened.
  static Future<CindelDatabase> open({
    required String directory,
    Iterable<CindelCollectionSchema<dynamic>> schemas = const [],
    CindelStorageBackend backend = defaultCindelStorageBackend,
    CindelMigrationPlan? migrationPlan,
  }) {
    return CindelDatabase.open(
      directory: directory,
      schemas: schemas,
      backend: backend,
      migrationPlan: migrationPlan,
    );
  }

  /// Opens an in-memory database.
  ///
  /// This is useful for tests and short-lived isolates. Data is discarded when
  /// the returned database is closed.
  static Future<CindelDatabase> openInMemory({
    Iterable<CindelCollectionSchema<dynamic>> schemas = const [],
    CindelStorageBackend backend = defaultCindelStorageBackend,
  }) {
    return CindelDatabase.openInMemory(schemas: schemas, backend: backend);
  }

  /// Splits text the same way Cindel word indexes do.
  static List<String> splitWords(String text, {bool caseSensitive = false}) {
    return cindelSplitWords(text, caseSensitive: caseSensitive);
  }
}
