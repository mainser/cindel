import 'package:cindel_shop_lite/features/catalog/domain/entities/catalog_query.dart';
import 'package:cindel_shop_lite/features/catalog/domain/entities/product.dart';

abstract interface class CatalogRepository {
  Future<void> seedIfEmpty();

  Stream<List<Product>> watchProducts(CatalogQuery query);

  Future<int> countProducts();
}
