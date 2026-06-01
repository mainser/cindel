import 'package:cindel_shop_lite/features/catalog/domain/repositories/catalog_repository.dart';

final class CountCatalogProducts {
  const CountCatalogProducts(this._repository);

  final CatalogRepository _repository;

  Future<int> call() {
    return _repository.countProducts();
  }
}
