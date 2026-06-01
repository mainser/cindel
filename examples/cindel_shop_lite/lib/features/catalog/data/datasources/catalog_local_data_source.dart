import 'package:cindel/cindel.dart';
import 'package:cindel_shop_lite/features/catalog/data/demo/catalog_seed_data.dart';
import 'package:cindel_shop_lite/features/catalog/domain/entities/catalog_query.dart';
import 'package:cindel_shop_lite/features/catalog/domain/entities/product.dart';

final class CatalogLocalDataSource {
  const CatalogLocalDataSource(this._database);

  final Future<CindelDatabase> _database;

  Future<void> seedIfEmpty() async {
    final database = await _database;
    final productCount = await database.products.all().count();
    if (productCount > 0) {
      return;
    }

    await database.writeTxn(() {
      return database.products.putAll(buildDemoCatalogProducts());
    });
  }

  Future<List<Product>> readProductsPage(
    CatalogQuery catalogQuery, {
    required int offset,
    required int limit,
  }) async {
    final database = await _database;
    return _buildQuery(
      database,
      catalogQuery,
    ).offset(offset).limit(limit).findAll();
  }

  Future<int> countProducts() async {
    final database = await _database;
    return database.products.all().count();
  }
}

CindelQuery<Product> _buildQuery(
  CindelDatabase database,
  CatalogQuery catalogQuery,
) {
  final searchText = catalogQuery.searchText.trim().toLowerCase();
  final searchTerms = searchText.isEmpty
      ? const <String>[]
      : searchText.split(RegExp(r'\s+'));
  final searchToken = searchTerms.isEmpty ? '' : searchTerms.first;

  var query = searchToken.isEmpty
      ? database.products.all()
      : database.products.where().searchTextStartsWith(searchToken);

  if (catalogQuery.category != 'All') {
    query = query.filter().categoryEqualTo(catalogQuery.category);
  }

  if (catalogQuery.inStockOnly) {
    query = query.filter().stockGreaterThan(0);
  }

  return switch (catalogQuery.sort) {
    CatalogSort.newest => query.sortByCreatedAtMicrosDesc(),
    CatalogSort.nameAsc => query.sortByName(),
    CatalogSort.priceAsc => query.sortByPriceCents(),
    CatalogSort.priceDesc => query.sortByPriceCentsDesc(),
    CatalogSort.stockAsc => query.sortByStock(),
  };
}
