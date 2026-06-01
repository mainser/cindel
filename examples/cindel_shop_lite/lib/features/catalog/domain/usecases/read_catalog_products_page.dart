import 'package:cindel_shop_lite/features/catalog/domain/entities/catalog_query.dart';
import 'package:cindel_shop_lite/features/catalog/domain/entities/product.dart';
import 'package:cindel_shop_lite/features/catalog/domain/repositories/catalog_repository.dart';

final class ReadCatalogProductsPage {
  const ReadCatalogProductsPage(this._repository);

  final CatalogRepository _repository;

  Future<List<Product>> call(
    CatalogQuery query, {
    required int offset,
    required int limit,
  }) {
    return _repository.readProductsPage(query, offset: offset, limit: limit);
  }
}
