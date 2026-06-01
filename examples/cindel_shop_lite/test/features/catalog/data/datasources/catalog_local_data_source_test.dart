import 'package:cindel/cindel.dart';
import 'package:cindel_shop_lite/features/catalog/data/datasources/catalog_local_data_source.dart';
import 'package:cindel_shop_lite/features/catalog/domain/entities/catalog_query.dart';
import 'package:cindel_shop_lite/features/catalog/domain/entities/product.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CatalogLocalDataSource', () {
    // Scenario: The app starts with an empty local products collection.
    // Covers:
    // - [CatalogLocalDataSource.seedIfEmpty] empty-collection guard.
    // - Cindel generated [ProductSchema] registration in memory.
    // - Bulk product insertion through the generated typed collection.
    // Expected: The deterministic demo catalog is inserted once.
    test('seeds the demo catalog only when the collection is empty.', () async {
      // Arrange.
      final database = await _openDatabase();
      addTearDown(database.close);
      final dataSource = CatalogLocalDataSource(Future.value(database));

      // Act.
      await dataSource.seedIfEmpty();
      final firstCount = await database.products.all().count();
      await dataSource.seedIfEmpty();
      final secondCount = await database.products.all().count();

      // Assert.
      expect(firstCount, 100);
      expect(secondCount, 100);
    });

    // Scenario: A catalog view requests one page from a filtered query.
    // Covers:
    // - [CatalogLocalDataSource.readProductsPage] applying filters before
    //   pagination.
    // - Cindel generated category and stock filters.
    // - Cindel generated price sorting with offset/limit pagination.
    // Expected: Only matching products are returned in page order.
    test('reads filtered and sorted pages through Cindel queries.', () async {
      // Arrange.
      final database = await _openDatabase(
        products: [
          _product(id: 1, name: 'Desk Lamp', category: 'Desk', price: 4500),
          _product(id: 2, name: 'Studio Headphones', price: 12000),
          _product(id: 3, name: 'Pocket Speaker', price: 3500),
          _product(id: 4, name: 'Silent Headphones', price: 9800, stock: 0),
        ],
      );
      addTearDown(database.close);
      final dataSource = CatalogLocalDataSource(Future.value(database));
      const query = CatalogQuery(
        category: 'Audio',
        inStockOnly: true,
        sort: CatalogSort.priceAsc,
      );

      // Act.
      final firstPage = await dataSource.readProductsPage(
        query,
        offset: 0,
        limit: 1,
      );
      final secondPage = await dataSource.readProductsPage(
        query,
        offset: 1,
        limit: 1,
      );

      // Assert.
      expect(firstPage.map((product) => product.name), ['Pocket Speaker']);
      expect(secondPage.map((product) => product.name), ['Studio Headphones']);
    });
  });
}

Future<CindelDatabase> _openDatabase({
  Iterable<Product> products = const [],
}) async {
  final database = await Cindel.openInMemory(schemas: [ProductSchema]);
  if (products.isNotEmpty) {
    await database.products.putAll(products);
  }
  return database;
}

Product _product({
  required int id,
  required String name,
  int price = 1000,
  int stock = 12,
  String category = 'Audio',
}) {
  return Product(
    dbId: id,
    sku: 'SHOP-$id',
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
