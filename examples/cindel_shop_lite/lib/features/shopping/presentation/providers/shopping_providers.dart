import 'package:cindel_shop_lite/features/catalog/domain/entities/product.dart';
import 'package:cindel_shop_lite/features/catalog/presentation/providers/catalog_providers.dart';
import 'package:cindel_shop_lite/features/dashboard/presentation/providers/dashboard_providers.dart';
import 'package:cindel_shop_lite/features/shopping/di/shopping_di.dart';
import 'package:cindel_shop_lite/features/shopping/domain/entities/shopping_cart.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'shopping_providers.g.dart';

/// In-memory cart state shared across tabs.
///
/// The provider is kept alive because products are added from the catalog tab
/// before the shopping page may be mounted.
@Riverpod(keepAlive: true)
class ShoppingCartController extends _$ShoppingCartController {
  @override
  ShoppingCart build() {
    return const ShoppingCart.empty();
  }

  /// Adds one unit of [product] when stock allows it.
  ///
  /// Returns whether the cart changed so callers can show accurate feedback.
  bool addProduct(Product product) {
    if (product.stock <= 0) {
      return false;
    }

    final index = state.items.indexWhere(
      (item) => item.product.dbId == product.dbId,
    );

    if (index == -1) {
      state = ShoppingCart(
        items: [
          ...state.items,
          CartItem(product: product, quantity: 1),
        ],
      );
      return true;
    }

    final current = state.items[index];
    if (current.quantity >= product.stock) {
      return false;
    }

    _replaceItem(index, current.copyWith(quantity: current.quantity + 1));
    return true;
  }

  void increment(int productId) {
    final index = state.items.indexWhere(
      (item) => item.product.dbId == productId,
    );
    if (index == -1) {
      return;
    }

    final item = state.items[index];
    if (item.quantity >= item.product.stock) {
      return;
    }

    _replaceItem(index, item.copyWith(quantity: item.quantity + 1));
  }

  void decrement(int productId) {
    final index = state.items.indexWhere(
      (item) => item.product.dbId == productId,
    );
    if (index == -1) {
      return;
    }

    final item = state.items[index];
    if (item.quantity <= 1) {
      remove(productId);
      return;
    }

    _replaceItem(index, item.copyWith(quantity: item.quantity - 1));
  }

  void remove(int productId) {
    state = ShoppingCart(
      items: [
        for (final item in state.items)
          if (item.product.dbId != productId) item,
      ],
    );
  }

  void clear() {
    state = const ShoppingCart.empty();
  }

  void _replaceItem(int index, CartItem item) {
    final nextItems = [...state.items];
    nextItems[index] = item;
    state = ShoppingCart(items: nextItems);
  }
}

/// Executes the simulated checkout and refreshes Cindel-backed UI state.
@riverpod
class CheckoutController extends _$CheckoutController {
  @override
  Future<void> build() async {}

  /// Persists checkout stock changes, clears the cart, and refreshes readers.
  Future<void> checkout(ShoppingCart cart) async {
    if (cart.isEmpty || state.isLoading) {
      return;
    }

    state = const AsyncLoading();

    try {
      await ref.read(checkoutCartUseCaseProvider).call(cart.items);
      ref.read(shoppingCartControllerProvider.notifier).clear();
      ref
        ..invalidate(catalogProductsControllerProvider)
        ..invalidate(catalogProductCountProvider)
        ..invalidate(dashboardMetricsProvider);
      state = const AsyncData(null);
    } on Object catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      rethrow;
    }
  }
}
