import 'package:cindel_shop_lite/features/catalog/domain/entities/catalog_query.dart';
import 'package:cindel_shop_lite/features/catalog/domain/entities/product.dart';

abstract interface class CatalogRepository {
  Future<void> seedIfEmpty();

  Future<List<Product>> readProductsPage(
    CatalogQuery query, {
    required int offset,
    required int limit,
  });

  Future<int> countProducts();
}
