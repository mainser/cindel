import 'package:cindel/cindel.dart';
import 'package:cindel_shop_lite/features/catalog/domain/entities/product.dart';
import 'package:cindel_shop_lite/features/shopping/domain/entities/shopping_cart.dart';
import 'package:cindel_shop_lite/features/shopping/domain/failures/shopping_failure.dart';

/// Local checkout persistence backed by the same Cindel product collection.
final class ShoppingLocalDataSource {
  const ShoppingLocalDataSource(this._database);

  final Future<CindelDatabase> _database;

  /// Validates stock and decrements products inside one Cindel write
  /// transaction.
  ///
  /// The cart itself is intentionally in memory for the demo. Checkout is the
  /// durable operation: it re-reads current products, rejects stale quantities,
  /// and writes updated stock with `putAll`.
  Future<void> checkout(List<CartItem> items) async {
    final database = await _database;

    await database.writeTxn(() async {
      final updatedProducts = <Product>[];

      for (final item in items) {
        final product = await database.products
            .filter()
            .dbIdEqualTo(item.product.dbId)
            .findFirst();

        if (product == null || product.stock < item.quantity) {
          throw ShoppingStockFailure(
            productName: item.product.name,
            requested: item.quantity,
            available: product?.stock ?? 0,
          );
        }

        updatedProducts.add(
          product.copyWith(stock: product.stock - item.quantity),
        );
      }

      await database.products.putAll(updatedProducts);
    });
  }
}
