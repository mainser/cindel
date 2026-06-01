import 'package:cindel/cindel.dart';
import 'package:cindel_shop_lite/features/catalog/domain/entities/product.dart';
import 'package:cindel_shop_lite/features/shopping/data/datasources/shopping_local_data_source.dart';
import 'package:cindel_shop_lite/features/shopping/domain/entities/shopping_cart.dart';
import 'package:cindel_shop_lite/features/shopping/domain/failures/shopping_failure.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ShoppingLocalDataSource', () {
    // Scenario: A cart with valid quantities is checked out.
    // Covers:
    // - [ShoppingLocalDataSource.checkout] current stock validation.
    // - Cindel write transactions for multi-product stock updates.
    // - Bulk stock persistence through generated [Product] collection APIs.
    // Expected: Product stock is decremented by the checked-out quantities.
    test('decrements product stock inside a write transaction.', () async {
      // Arrange.
      final keyboard = _product(id: 1, name: 'Keyboard', stock: 5);
      final mouse = _product(id: 2, name: 'Mouse', stock: 3);
      final database = await _openDatabase(products: [keyboard, mouse]);
      addTearDown(database.close);
      final dataSource = ShoppingLocalDataSource(Future.value(database));

      // Act.
      await dataSource.checkout([
        CartItem(product: keyboard, quantity: 2),
        CartItem(product: mouse, quantity: 1),
      ]);
      final updatedKeyboard = await database.products
          .filter()
          .dbIdEqualTo(keyboard.dbId)
          .findFirst();
      final updatedMouse = await database.products
          .filter()
          .dbIdEqualTo(mouse.dbId)
          .findFirst();

      // Assert.
      expect(updatedKeyboard?.stock, 3);
      expect(updatedMouse?.stock, 2);
    });

    // Scenario: A stale cart asks for more units than the database has.
    // Covers:
    // - Checkout re-reading current product stock before updating.
    // - Typed [ShoppingStockFailure] for insufficient stock.
    // - Transaction rollback when validation fails.
    // Expected: The checkout fails and stored stock is left unchanged.
    test('rejects stale quantities without changing stock.', () async {
      // Arrange.
      final keyboard = _product(id: 1, name: 'Keyboard', stock: 1);
      final database = await _openDatabase(products: [keyboard]);
      addTearDown(database.close);
      final dataSource = ShoppingLocalDataSource(Future.value(database));

      // Act.
      Future<void> result() {
        return dataSource.checkout([CartItem(product: keyboard, quantity: 2)]);
      }

      // Assert.
      await expectLater(result, throwsA(isA<ShoppingStockFailure>()));
      final unchangedKeyboard = await database.products
          .filter()
          .dbIdEqualTo(keyboard.dbId)
          .findFirst();
      expect(unchangedKeyboard?.stock, 1);
    });
  });
}

Future<CindelDatabase> _openDatabase({
  required Iterable<Product> products,
}) async {
  final database = await Cindel.openInMemory(schemas: [ProductSchema]);
  await database.products.putAll(products);
  return database;
}

Product _product({
  required int id,
  required String name,
  required int stock,
}) {
  return Product(
    dbId: id,
    sku: 'CART-$id',
    name: name,
    description: '$name description',
    searchText: '$name description'.toLowerCase(),
    category: 'Accessories',
    priceCents: 2500,
    stock: stock,
    createdAtMicros: id,
    tags: const ['demo'],
  );
}
