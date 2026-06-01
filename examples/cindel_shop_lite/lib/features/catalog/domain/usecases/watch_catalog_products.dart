import 'package:cindel_shop_lite/features/catalog/domain/entities/catalog_query.dart';
import 'package:cindel_shop_lite/features/catalog/domain/entities/product.dart';
import 'package:cindel_shop_lite/features/catalog/domain/repositories/catalog_repository.dart';

final class WatchCatalogProducts {
  const WatchCatalogProducts(this._repository);

  final CatalogRepository _repository;

  Stream<List<Product>> call(CatalogQuery query) {
    return _repository.watchProducts(query);
  }
}
