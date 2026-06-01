import 'package:cindel_shop_lite/features/catalog/domain/failures/catalog_failure.dart';

String catalogErrorMessage(Object error) {
  if (error is CatalogStorageFailure) {
    return error.message;
  }
  return 'Catalog is unavailable.';
}
