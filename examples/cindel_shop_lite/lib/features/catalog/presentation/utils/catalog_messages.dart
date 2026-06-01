import 'package:cindel_shop_lite/features/catalog/domain/failures/catalog_failure.dart';
import 'package:cindel_shop_lite/l10n/l10n.dart';

String catalogErrorMessage(Object error, AppLocalizations l10n) {
  if (error is CatalogStorageFailure) {
    return error.message;
  }
  return l10n.catalog_unavailable;
}
