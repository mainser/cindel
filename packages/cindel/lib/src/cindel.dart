import 'database.dart';
import 'schema.dart';

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
}
