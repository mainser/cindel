import 'database.dart';
import 'schema.dart';
import 'text.dart';

/// Entry point for opening Cindel databases.
abstract final class Cindel {
  /// Opens a database stored under [directory].
  ///
  /// Throws an [ArgumentError] when [directory] is empty and a [StateError] when
  /// the native engine cannot be opened.
  static Future<CindelDatabase> open({
    required String directory,
    Iterable<CindelCollectionSchema<dynamic>> schemas = const [],
  }) {
    return CindelDatabase.open(directory: directory, schemas: schemas);
  }

  /// Opens an in-memory database.
  ///
  /// This is useful for tests and short-lived isolates. Data is discarded when
  /// the returned database is closed.
  static Future<CindelDatabase> openInMemory({
    Iterable<CindelCollectionSchema<dynamic>> schemas = const [],
  }) {
    return CindelDatabase.openInMemory(schemas: schemas);
  }

  /// Splits text the same way Cindel word indexes do.
  static List<String> splitWords(String text, {bool caseSensitive = false}) {
    return cindelSplitWords(text, caseSensitive: caseSensitive);
  }
}
