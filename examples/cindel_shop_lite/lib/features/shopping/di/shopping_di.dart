import 'package:cindel_shop_lite/features/catalog/di/catalog_di.dart';
import 'package:cindel_shop_lite/features/shopping/data/datasources/shopping_local_data_source.dart';
import 'package:cindel_shop_lite/features/shopping/data/repositories/cindel_shopping_repository.dart';
import 'package:cindel_shop_lite/features/shopping/domain/repositories/shopping_repository.dart';
import 'package:cindel_shop_lite/features/shopping/domain/usecases/checkout_cart.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'shopping_di.g.dart';

/// Shopping data source that performs checkout against catalog products.
@riverpod
ShoppingLocalDataSource shoppingLocalDataSource(Ref ref) {
  return ShoppingLocalDataSource(ref.watch(catalogDatabaseProvider.future));
}

/// Repository boundary for the simulated checkout flow.
@riverpod
ShoppingRepository shoppingRepository(Ref ref) {
  return CindelShoppingRepository(ref.watch(shoppingLocalDataSourceProvider));
}

/// Use case that commits cart checkout effects to local storage.
@riverpod
CheckoutCart checkoutCartUseCase(Ref ref) {
  return CheckoutCart(ref.watch(shoppingRepositoryProvider));
}
