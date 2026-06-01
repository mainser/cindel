import 'package:freezed_annotation/freezed_annotation.dart';

part 'catalog_query.freezed.dart';

enum CatalogSort {
  newest,
  nameAsc,
  priceAsc,
  priceDesc,
  stockAsc,
}

@freezed
abstract class CatalogQuery with _$CatalogQuery {
  const factory CatalogQuery({
    @Default('') String searchText,
    @Default('All') String category,
    @Default(false) bool inStockOnly,
    @Default(CatalogSort.newest) CatalogSort sort,
  }) = _CatalogQuery;
}
