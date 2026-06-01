import 'package:cindel_shop_lite/features/catalog/data/datasources/catalog_local_data_source.dart';
import 'package:cindel_shop_lite/features/catalog/domain/entities/catalog_query.dart';
import 'package:cindel_shop_lite/features/catalog/domain/entities/product.dart';
import 'package:cindel_shop_lite/features/catalog/domain/failures/catalog_failure.dart';
import 'package:cindel_shop_lite/features/catalog/domain/repositories/catalog_repository.dart';

final class CindelCatalogRepository implements CatalogRepository {
  const CindelCatalogRepository(this._dataSource);

  final CatalogLocalDataSource _dataSource;

  @override
  Future<void> seedIfEmpty() async {
    try {
      await _dataSource.seedIfEmpty();
    } catch (error) {
      throw CatalogStorageFailure.from(error);
    }
  }

  @override
  Stream<List<Product>> watchProducts(CatalogQuery query) {
    return _dataSource.watchProducts(query).handleError((Object error) {
      throw CatalogStorageFailure.from(error);
    });
  }

  @override
  Future<int> countProducts() async {
    try {
      return await _dataSource.countProducts();
    } catch (error) {
      throw CatalogStorageFailure.from(error);
    }
  }
}
