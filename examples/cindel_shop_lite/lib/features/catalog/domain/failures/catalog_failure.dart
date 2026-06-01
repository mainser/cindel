final class CatalogStorageFailure implements Exception {
  const CatalogStorageFailure(this.message, [this.cause]);

  factory CatalogStorageFailure.from(Object error) {
    if (error is CatalogStorageFailure) {
      return error;
    }
    return CatalogStorageFailure('Catalog storage operation failed.', error);
  }

  final String message;
  final Object? cause;

  @override
  String toString() => '$message ${cause ?? ''}'.trim();
}
