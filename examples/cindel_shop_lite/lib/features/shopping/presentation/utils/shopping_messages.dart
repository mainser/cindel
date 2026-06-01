import 'package:cindel_shop_lite/features/shopping/domain/failures/shopping_failure.dart';
import 'package:cindel_shop_lite/l10n/l10n.dart';

String shoppingErrorMessage(Object error, AppLocalizations l10n) {
  if (error is ShoppingStorageFailure) {
    final cause = error.cause;
    if (cause is ShoppingStockFailure) {
      return _stockFailureMessage(cause, l10n);
    }
    return l10n.checkout_operation_failed;
  }
  if (error is ShoppingStockFailure) {
    return _stockFailureMessage(error, l10n);
  }
  return l10n.checkout_unavailable;
}

String _stockFailureMessage(
  ShoppingStockFailure error,
  AppLocalizations l10n,
) {
  if (error.available == 0) {
    return l10n.product_out_of_stock(error.productName);
  }
  return l10n.product_only_available(error.productName, error.available);
}
