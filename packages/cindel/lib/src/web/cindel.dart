import '../schema.dart';
import '../text.dart';
import 'database.dart';

/// Entry point for opening Cindel databases on Dart Web.
///
/// This class mirrors the native `Cindel` facade so app code can keep using the
/// same `Cindel.open(...)` call on every supported platform. Web-specific
/// Worker, Wasm, schema manifest, and asset-loading details stay behind
/// [CindelDatabase].
abstract final class Cindel {
  /// Opens a Web SQLite database stored by the browser runtime.
  ///
  /// The [backend] argument is kept for source compatibility with native code.
  /// Browsers do not use MDBX, so Web always routes through the packaged
  /// Worker/Wasm SQLite runtime.
  static Future<CindelDatabase> open({
    required String directory,
    Iterable<CindelCollectionSchema<dynamic>> schemas = const [],
    CindelStorageBackend backend = defaultCindelStorageBackend,
  }) {
    return CindelDatabase.open(
      directory: directory,
      schemas: schemas,
      backend: backend,
    );
  }

  /// Opens a short-lived Web SQLite database name.
  ///
  /// Web does not have the same native in-memory backend as desktop/mobile.
  /// This creates a unique browser database name suitable for tests and
  /// temporary work.
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
