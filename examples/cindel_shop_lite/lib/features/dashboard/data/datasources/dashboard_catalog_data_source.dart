import 'package:cindel/cindel.dart';
import 'package:cindel_shop_lite/features/catalog/domain/entities/product.dart';
import 'package:cindel_shop_lite/features/dashboard/domain/entities/dashboard_metrics.dart';

final class DashboardCatalogDataSource {
  const DashboardCatalogDataSource(this._database);

  final Future<CindelDatabase> _database;

  Future<DashboardMetrics> readMetrics() async {
    final database = await _database;
    final allProducts = await database.products.all().findAll();
    final totalProducts = await database.products.all().count();
    final outOfStockProducts = await database.products
        .where()
        .stockEqualTo(0)
        .count();
    final lowStockProducts = await database.products
        .filter()
        .stockLessThan(8)
        .count();
    final criticalProducts = await database.products
        .filter()
        .stockLessThan(8)
        .sortByStock()
        .limit(5)
        .findAll();

    final categoriesByName = <String, ({int productCount, int stock})>{};
    var inventoryValueCents = 0;

    for (final product in allProducts) {
      inventoryValueCents += product.priceCents * product.stock;
      final current =
          categoriesByName[product.category] ?? (productCount: 0, stock: 0);
      categoriesByName[product.category] = (
        productCount: current.productCount + 1,
        stock: current.stock + product.stock,
      );
    }

    final categories = [
      for (final entry in categoriesByName.entries)
        CategoryMetric(
          name: entry.key,
          productCount: entry.value.productCount,
          stock: entry.value.stock,
        ),
    ]..sort((left, right) => left.name.compareTo(right.name));

    return DashboardMetrics(
      totalProducts: totalProducts,
      outOfStockProducts: outOfStockProducts,
      lowStockProducts: lowStockProducts,
      inventoryValueCents: inventoryValueCents,
      categoryCount: categories.length,
      categories: categories,
      criticalProducts: criticalProducts,
    );
  }
}
