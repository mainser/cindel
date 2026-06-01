import 'package:cindel/cindel.dart';
import 'package:cindel_shop_lite/features/catalog/domain/entities/product.dart';
import 'package:cindel_shop_lite/features/dashboard/data/datasources/dashboard_catalog_data_source.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DashboardCatalogDataSource', () {
    // Scenario: The dashboard opens after catalog products already exist.
    // Covers:
    // - [DashboardCatalogDataSource.readMetrics] Cindel count queries.
    // - Filtered low-stock and out-of-stock queries.
    // - Derived category and inventory totals from local products.
    // Expected: The dashboard snapshot matches the current collection state.
    test('builds inventory metrics from the products collection.', () async {
      // Arrange.
      final database = await _openDatabase(
        products: [
          _product(id: 1, name: 'Notebook', category: 'Desk', price: 2000),
          _product(
            id: 2,
            name: 'Headphones',
            category: 'Audio',
            price: 5000,
            stock: 4,
          ),
          _product(
            id: 3,
            name: 'Speaker',
            category: 'Audio',
            price: 3000,
            stock: 0,
          ),
        ],
      );
      addTearDown(database.close);
      final dataSource = DashboardCatalogDataSource(Future.value(database));

      // Act.
      final metrics = await dataSource.readMetrics();

      // Assert.
      expect(metrics.totalProducts, 3);
      expect(metrics.categoryCount, 2);
      expect(metrics.lowStockProducts, 2);
      expect(metrics.outOfStockProducts, 1);
      expect(metrics.inventoryValueCents, 40000);
      expect(metrics.categories.map((category) => category.name), [
        'Audio',
        'Desk',
      ]);
      expect(metrics.criticalProducts.map((product) => product.name), [
        'Speaker',
        'Headphones',
      ]);
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
  required String category,
  required int price,
  int stock = 10,
}) {
  return Product(
    dbId: id,
    sku: 'DASH-$id',
    name: name,
    description: '$name description',
    searchText: '$name description'.toLowerCase(),
    category: category,
    priceCents: price,
    stock: stock,
    createdAtMicros: id,
    tags: const ['demo'],
  );
}
