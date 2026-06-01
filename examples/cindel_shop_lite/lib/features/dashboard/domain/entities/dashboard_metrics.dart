import 'package:cindel_shop_lite/features/catalog/domain/entities/product.dart';

final class DashboardMetrics {
  const DashboardMetrics({
    required this.totalProducts,
    required this.outOfStockProducts,
    required this.lowStockProducts,
    required this.inventoryValueCents,
    required this.categoryCount,
    required this.categories,
    required this.criticalProducts,
  });

  final int totalProducts;
  final int outOfStockProducts;
  final int lowStockProducts;
  final int inventoryValueCents;
  final int categoryCount;
  final List<CategoryMetric> categories;
  final List<Product> criticalProducts;
}

final class CategoryMetric {
  const CategoryMetric({
    required this.name,
    required this.productCount,
    required this.stock,
  });

  final String name;
  final int productCount;
  final int stock;
}
