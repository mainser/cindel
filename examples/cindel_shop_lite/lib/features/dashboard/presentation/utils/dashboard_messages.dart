import 'package:cindel_shop_lite/features/catalog/domain/failures/catalog_failure.dart';

String dashboardErrorMessage(Object error) {
  if (error is CatalogStorageFailure) {
    return error.message;
  }
  return 'Dashboard is unavailable.';
}
