import 'package:cindel_shop_lite/features/catalog/domain/repositories/catalog_repository.dart';

final class EnsureCatalogSeeded {
  const EnsureCatalogSeeded(this._repository);

  final CatalogRepository _repository;

  Future<void> call() {
    return _repository.seedIfEmpty();
  }
}
