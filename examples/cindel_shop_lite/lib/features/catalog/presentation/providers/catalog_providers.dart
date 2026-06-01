import 'dart:async';

import 'package:cindel_shop_lite/features/catalog/di/catalog_di.dart';
import 'package:cindel_shop_lite/features/catalog/domain/entities/catalog_query.dart';
import 'package:cindel_shop_lite/features/catalog/domain/entities/product.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'catalog_providers.g.dart';

@riverpod
Future<void> catalogStartup(Ref ref) async {
  await ref.watch(ensureCatalogSeededUseCaseProvider).call();
  ref.invalidate(catalogProductCountProvider);
}

@riverpod
Stream<List<Product>> catalogProducts(Ref ref) {
  final query = ref.watch(catalogQueryControllerProvider);
  return ref.watch(watchCatalogProductsUseCaseProvider).call(query);
}

@riverpod
Future<int> catalogProductCount(Ref ref) {
  return ref.watch(countCatalogProductsUseCaseProvider).call();
}

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
