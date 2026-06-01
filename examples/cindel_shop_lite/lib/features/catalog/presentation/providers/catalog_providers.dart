import 'package:cindel_shop_lite/features/catalog/di/catalog_di.dart';
import 'package:cindel_shop_lite/features/catalog/domain/entities/catalog_query.dart';
import 'package:cindel_shop_lite/features/catalog/domain/entities/product.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'catalog_providers.g.dart';

const _catalogPageSize = 20;

/// Runs catalog startup work that should happen once when the app launches.
///
/// The seed is guarded by the data source, so watching this provider from the
/// app shell does not duplicate demo products.
@riverpod
Future<void> catalogStartup(Ref ref) async {
  await ref.watch(ensureCatalogSeededUseCaseProvider).call();
  ref
    ..invalidate(catalogProductCountProvider)
    ..invalidate(catalogProductsControllerProvider);
}

/// Immutable page state for the paginated product grid.
final class CatalogProductsPage {
  const CatalogProductsPage({
    required this.products,
    required this.hasMore,
    required this.isLoadingMore,
  });

  final List<Product> products;
  final bool hasMore;
  final bool isLoadingMore;

  CatalogProductsPage copyWith({
    List<Product>? products,
    bool? hasMore,
    bool? isLoadingMore,
  }) {
    return CatalogProductsPage(
      products: products ?? this.products,
      hasMore: hasMore ?? this.hasMore,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    );
  }
}

/// Loads and appends catalog pages in response to scroll position.
@riverpod
class CatalogProductsController extends _$CatalogProductsController {
  @override
  Future<CatalogProductsPage> build() async {
    final query = ref.watch(catalogQueryControllerProvider);
    final products = await ref
        .watch(readCatalogProductsPageUseCaseProvider)
        .call(query, offset: 0, limit: _catalogPageSize);

    return CatalogProductsPage(
      products: products,
      hasMore: products.length == _catalogPageSize,
      isLoadingMore: false,
    );
  }

  /// Loads the next page unless a page is already loading or the query is done.
  Future<void> loadNextPage() async {
    final current = state.value;
    if (current == null || current.isLoadingMore || !current.hasMore) {
      return;
    }

    state = AsyncData(current.copyWith(isLoadingMore: true));

    try {
      final query = ref.read(catalogQueryControllerProvider);
      final nextProducts = await ref
          .read(readCatalogProductsPageUseCaseProvider)
          .call(
            query,
            offset: current.products.length,
            limit: _catalogPageSize,
          );

      state = AsyncData(
        CatalogProductsPage(
          products: [...current.products, ...nextProducts],
          hasMore: nextProducts.length == _catalogPageSize,
          isLoadingMore: false,
        ),
      );
    } on Object catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
    }
  }
}

/// Product count used by catalog chrome and lightweight status surfaces.
@riverpod
Future<int> catalogProductCount(Ref ref) {
  return ref.watch(countCatalogProductsUseCaseProvider).call();
}

/// Stores the active catalog query selected by search and filter controls.
@riverpod
class CatalogQueryController extends _$CatalogQueryController {
  @override
  CatalogQuery build() {
    return const CatalogQuery();
  }

  void setSearchText(String value) {
    state = state.copyWith(searchText: value);
  }

  void setCategory(String value) {
    state = state.copyWith(category: value);
  }

  void setInStockOnly({required bool value}) {
    state = state.copyWith(inStockOnly: value);
  }

  void setSort(CatalogSort value) {
    state = state.copyWith(sort: value);
  }

  void clearSearch() {
    state = state.copyWith(searchText: '');
  }
}
