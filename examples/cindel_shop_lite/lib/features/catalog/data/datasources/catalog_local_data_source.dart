import 'package:cindel/cindel.dart';
import 'package:cindel_shop_lite/features/catalog/data/demo/catalog_seed_data.dart';
import 'package:cindel_shop_lite/features/catalog/domain/entities/catalog_query.dart';
import 'package:cindel_shop_lite/features/catalog/domain/entities/product.dart';

/// Local catalog persistence implemented with Cindel generated product APIs.
final class CatalogLocalDataSource {
  const CatalogLocalDataSource(this._database);

  final Future<CindelDatabase> _database;

  /// Seeds the demo catalog once, only when the products collection is empty.
  ///
  /// This keeps app startup idempotent while still giving first-run users a
  /// useful local dataset.
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

  /// Reads one page of products using Cindel query pagination.
  ///
  /// Filters and sorting are applied before `offset` and `limit`, so the UI can
  /// request pages of 20 without loading the whole catalog into memory.
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

  /// Counts all products currently stored in the Cindel collection.
  Future<int> countProducts() async {
    final database = await _database;
    return database.products.all().count();
  }
}

/// Converts the presentation catalog query into a generated Cindel query.
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
