// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'product.dart';

// **************************************************************************
// CindelGenerator
// **************************************************************************

// ignore_for_file: non_constant_identifier_names

final ProductSchema = CindelCollectionSchema<Product>(
  name: "products",
  dartName: "Product",
  idField: "dbId",
  fields: <CindelFieldSchema>[
    CindelFieldSchema(
      name: "dbId",
      dartType: "int",
      binaryType: "int",
      isId: true,
      isIndexed: false,
      isIndexUnique: false,
      isIndexReplace: false,
      indexCaseSensitive: true,
      indexType: CindelIndexType.value,
    ),
    CindelFieldSchema(
      name: "sku",
      dartType: "String",
      binaryType: "string",
      isId: false,
      isIndexed: true,
      isIndexUnique: true,
      isIndexReplace: false,
      indexCaseSensitive: true,
      indexType: CindelIndexType.value,
    ),
    CindelFieldSchema(
      name: "name",
      dartType: "String",
      binaryType: "string",
      isId: false,
      isIndexed: true,
      isIndexUnique: false,
      isIndexReplace: false,
      indexCaseSensitive: true,
      indexType: CindelIndexType.value,
    ),
    CindelFieldSchema(
      name: "description",
      dartType: "String",
      binaryType: "string",
      isId: false,
      isIndexed: false,
      isIndexUnique: false,
      isIndexReplace: false,
      indexCaseSensitive: true,
      indexType: CindelIndexType.value,
    ),
    CindelFieldSchema(
      name: "searchText",
      dartType: "String",
      binaryType: "string",
      isId: false,
      isIndexed: true,
      isIndexUnique: false,
      isIndexReplace: false,
      indexCaseSensitive: false,
      indexType: CindelIndexType.words,
    ),
    CindelFieldSchema(
      name: "category",
      dartType: "String",
      binaryType: "string",
      isId: false,
      isIndexed: true,
      isIndexUnique: false,
      isIndexReplace: false,
      indexCaseSensitive: true,
      indexType: CindelIndexType.value,
    ),
    CindelFieldSchema(
      name: "priceCents",
      dartType: "int",
      binaryType: "int",
      isId: false,
      isIndexed: true,
      isIndexUnique: false,
      isIndexReplace: false,
      indexCaseSensitive: true,
      indexType: CindelIndexType.value,
    ),
    CindelFieldSchema(
      name: "stock",
      dartType: "int",
      binaryType: "int",
      isId: false,
      isIndexed: true,
      isIndexUnique: false,
      isIndexReplace: false,
      indexCaseSensitive: true,
      indexType: CindelIndexType.value,
    ),
    CindelFieldSchema(
      name: "createdAtMicros",
      dartType: "int",
      binaryType: "int",
      isId: false,
      isIndexed: false,
      isIndexUnique: false,
      isIndexReplace: false,
      indexCaseSensitive: true,
      indexType: CindelIndexType.value,
    ),
    CindelFieldSchema(
      name: "tags",
      dartType: "List<String>",
      binaryType: "list",
      isId: false,
      isIndexed: true,
      isIndexUnique: false,
      isIndexReplace: false,
      indexCaseSensitive: false,
      indexType: CindelIndexType.multiEntry,
    ),
  ],
  links: <CindelLinkSchema>[],
  compositeIndexes: <CindelCompositeIndexSchema>[],
  toDocument: _$ProductToCindelDocument,
  fromDocument: _$ProductFromCindelDocument,
  toBinaryDocument: _$ProductToCindelBinaryDocument,
  fromBinaryDocument: _$ProductFromCindelBinaryDocument,
  writeNativeDocument: _$ProductWriteCindelNativeDocument,
  readNativeDocument: _$ProductReadCindelNativeDocument,
  getId: _$ProductGetCindelId,
);

extension ProductCindelCollectionAccess on CindelDatabase {
  CindelTypedCollection<Product> get products => typedCollection(ProductSchema);
}

extension ProductCindelQueryAccess on CindelTypedCollection<Product> {
  ProductQueryWhere where() => ProductQueryWhere(this);

  ProductQueryFilter filter() => ProductQueryFilter(
    CindelQuery.all(database: database, schema: ProductSchema),
  );
}

extension ProductCindelQueryFilterAccess on CindelQuery<Product> {
  ProductQueryFilter filter() => ProductQueryFilter(this);
}

extension ProductCindelQueryModifierAccess on CindelQuery<Product> {
  CindelQuery<Product> sortByDbId({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return sortBy("dbId", order: order);
  }

  CindelQuery<Product> sortByDbIdDesc() {
    return sortBy("dbId", order: CindelSortOrder.descending);
  }

  CindelQuery<Product> thenByDbId({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return thenBy("dbId", order: order);
  }

  CindelQuery<Product> thenByDbIdDesc() {
    return thenBy("dbId", order: CindelSortOrder.descending);
  }

  CindelQuery<Product> distinctByDbId() {
    return distinctBy("dbId");
  }

  CindelPropertyQuery<Product, int> dbIdProperty() {
    return property<int>("dbId");
  }

  CindelQuery<Product> sortBySku({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return sortBy("sku", order: order);
  }

  CindelQuery<Product> sortBySkuDesc() {
    return sortBy("sku", order: CindelSortOrder.descending);
  }

  CindelQuery<Product> thenBySku({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return thenBy("sku", order: order);
  }

  CindelQuery<Product> thenBySkuDesc() {
    return thenBy("sku", order: CindelSortOrder.descending);
  }

  CindelQuery<Product> distinctBySku() {
    return distinctBy("sku");
  }

  CindelPropertyQuery<Product, String> skuProperty() {
    return property<String>("sku");
  }

  CindelQuery<Product> sortByName({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return sortBy("name", order: order);
  }

  CindelQuery<Product> sortByNameDesc() {
    return sortBy("name", order: CindelSortOrder.descending);
  }

  CindelQuery<Product> thenByName({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return thenBy("name", order: order);
  }

  CindelQuery<Product> thenByNameDesc() {
    return thenBy("name", order: CindelSortOrder.descending);
  }

  CindelQuery<Product> distinctByName() {
    return distinctBy("name");
  }

  CindelPropertyQuery<Product, String> nameProperty() {
    return property<String>("name");
  }

  CindelQuery<Product> sortByDescription({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return sortBy("description", order: order);
  }

  CindelQuery<Product> sortByDescriptionDesc() {
    return sortBy("description", order: CindelSortOrder.descending);
  }

  CindelQuery<Product> thenByDescription({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return thenBy("description", order: order);
  }

  CindelQuery<Product> thenByDescriptionDesc() {
    return thenBy("description", order: CindelSortOrder.descending);
  }

  CindelQuery<Product> distinctByDescription() {
    return distinctBy("description");
  }

  CindelPropertyQuery<Product, String> descriptionProperty() {
    return property<String>("description");
  }

  CindelQuery<Product> sortBySearchText({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return sortBy("searchText", order: order);
  }

  CindelQuery<Product> sortBySearchTextDesc() {
    return sortBy("searchText", order: CindelSortOrder.descending);
  }

  CindelQuery<Product> thenBySearchText({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return thenBy("searchText", order: order);
  }

  CindelQuery<Product> thenBySearchTextDesc() {
    return thenBy("searchText", order: CindelSortOrder.descending);
  }

  CindelQuery<Product> distinctBySearchText() {
    return distinctBy("searchText");
  }

  CindelPropertyQuery<Product, String> searchTextProperty() {
    return property<String>("searchText");
  }

  CindelQuery<Product> sortByCategory({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return sortBy("category", order: order);
  }

  CindelQuery<Product> sortByCategoryDesc() {
    return sortBy("category", order: CindelSortOrder.descending);
  }

  CindelQuery<Product> thenByCategory({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return thenBy("category", order: order);
  }

  CindelQuery<Product> thenByCategoryDesc() {
    return thenBy("category", order: CindelSortOrder.descending);
  }

  CindelQuery<Product> distinctByCategory() {
    return distinctBy("category");
  }

  CindelPropertyQuery<Product, String> categoryProperty() {
    return property<String>("category");
  }

  CindelQuery<Product> sortByPriceCents({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return sortBy("priceCents", order: order);
  }

  CindelQuery<Product> sortByPriceCentsDesc() {
    return sortBy("priceCents", order: CindelSortOrder.descending);
  }

  CindelQuery<Product> thenByPriceCents({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return thenBy("priceCents", order: order);
  }

  CindelQuery<Product> thenByPriceCentsDesc() {
    return thenBy("priceCents", order: CindelSortOrder.descending);
  }

  CindelQuery<Product> distinctByPriceCents() {
    return distinctBy("priceCents");
  }

  CindelPropertyQuery<Product, int> priceCentsProperty() {
    return property<int>("priceCents");
  }

  CindelQuery<Product> sortByStock({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return sortBy("stock", order: order);
  }

  CindelQuery<Product> sortByStockDesc() {
    return sortBy("stock", order: CindelSortOrder.descending);
  }

  CindelQuery<Product> thenByStock({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return thenBy("stock", order: order);
  }

  CindelQuery<Product> thenByStockDesc() {
    return thenBy("stock", order: CindelSortOrder.descending);
  }

  CindelQuery<Product> distinctByStock() {
    return distinctBy("stock");
  }

  CindelPropertyQuery<Product, int> stockProperty() {
    return property<int>("stock");
  }

  CindelQuery<Product> sortByCreatedAtMicros({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return sortBy("createdAtMicros", order: order);
  }

  CindelQuery<Product> sortByCreatedAtMicrosDesc() {
    return sortBy("createdAtMicros", order: CindelSortOrder.descending);
  }

  CindelQuery<Product> thenByCreatedAtMicros({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return thenBy("createdAtMicros", order: order);
  }

  CindelQuery<Product> thenByCreatedAtMicrosDesc() {
    return thenBy("createdAtMicros", order: CindelSortOrder.descending);
  }

  CindelQuery<Product> distinctByCreatedAtMicros() {
    return distinctBy("createdAtMicros");
  }

  CindelPropertyQuery<Product, int> createdAtMicrosProperty() {
    return property<int>("createdAtMicros");
  }

  CindelQuery<Product> sortByTags({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return sortBy("tags", order: order);
  }

  CindelQuery<Product> sortByTagsDesc() {
    return sortBy("tags", order: CindelSortOrder.descending);
  }

  CindelQuery<Product> thenByTags({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return thenBy("tags", order: order);
  }

  CindelQuery<Product> thenByTagsDesc() {
    return thenBy("tags", order: CindelSortOrder.descending);
  }

  CindelQuery<Product> distinctByTags() {
    return distinctBy("tags");
  }

  CindelPropertyQuery<Product, List<String>> tagsProperty() {
    return property<List<String>>(
      "tags",
      decode: (value) => (value as List<Object?>)
          .map((value) => value as String)
          .toList(growable: false),
    );
  }
}

final class ProductQueryFilter {
  const ProductQueryFilter(this._query);

  final CindelQuery<Product> _query;

  CindelQuery<Product> dbIdEqualTo(int value) {
    return _query.whereMatches(CindelFilter.field("dbId").equalTo(value));
  }

  CindelQuery<Product> dbIdGreaterThan(int value) {
    return _query.whereMatches(CindelFilter.field("dbId").greaterThan(value));
  }

  CindelQuery<Product> dbIdGreaterThanOrEqualTo(int value) {
    return _query.whereMatches(
      CindelFilter.field("dbId").greaterThanOrEqualTo(value),
    );
  }

  CindelQuery<Product> dbIdLessThan(int value) {
    return _query.whereMatches(CindelFilter.field("dbId").lessThan(value));
  }

  CindelQuery<Product> dbIdLessThanOrEqualTo(int value) {
    return _query.whereMatches(
      CindelFilter.field("dbId").lessThanOrEqualTo(value),
    );
  }

  CindelQuery<Product> dbIdBetween(int? lower, int? upper) {
    return _query.whereMatches(
      CindelFilter.field("dbId").between(lower, upper),
    );
  }

  CindelQuery<Product> skuEqualTo(String value) {
    return _query.whereMatches(CindelFilter.field("sku").equalTo(value));
  }

  CindelQuery<Product> skuContains(String value) {
    return _query.whereMatches(CindelFilter.field("sku").contains(value));
  }

  CindelQuery<Product> skuStartsWith(String value) {
    return _query.whereMatches(CindelFilter.field("sku").startsWith(value));
  }

  CindelQuery<Product> skuEndsWith(String value) {
    return _query.whereMatches(CindelFilter.field("sku").endsWith(value));
  }

  CindelQuery<Product> nameEqualTo(String value) {
    return _query.whereMatches(CindelFilter.field("name").equalTo(value));
  }

  CindelQuery<Product> nameContains(String value) {
    return _query.whereMatches(CindelFilter.field("name").contains(value));
  }

  CindelQuery<Product> nameStartsWith(String value) {
    return _query.whereMatches(CindelFilter.field("name").startsWith(value));
  }

  CindelQuery<Product> nameEndsWith(String value) {
    return _query.whereMatches(CindelFilter.field("name").endsWith(value));
  }

  CindelQuery<Product> descriptionEqualTo(String value) {
    return _query.whereMatches(
      CindelFilter.field("description").equalTo(value),
    );
  }

  CindelQuery<Product> descriptionContains(String value) {
    return _query.whereMatches(
      CindelFilter.field("description").contains(value),
    );
  }

  CindelQuery<Product> descriptionStartsWith(String value) {
    return _query.whereMatches(
      CindelFilter.field("description").startsWith(value),
    );
  }

  CindelQuery<Product> descriptionEndsWith(String value) {
    return _query.whereMatches(
      CindelFilter.field("description").endsWith(value),
    );
  }

  CindelQuery<Product> searchTextEqualTo(String value) {
    return _query.whereMatches(CindelFilter.field("searchText").equalTo(value));
  }

  CindelQuery<Product> categoryEqualTo(String value) {
    return _query.whereMatches(CindelFilter.field("category").equalTo(value));
  }

  CindelQuery<Product> categoryContains(String value) {
    return _query.whereMatches(CindelFilter.field("category").contains(value));
  }

  CindelQuery<Product> categoryStartsWith(String value) {
    return _query.whereMatches(
      CindelFilter.field("category").startsWith(value),
    );
  }

  CindelQuery<Product> categoryEndsWith(String value) {
    return _query.whereMatches(CindelFilter.field("category").endsWith(value));
  }

  CindelQuery<Product> priceCentsEqualTo(int value) {
    return _query.whereMatches(CindelFilter.field("priceCents").equalTo(value));
  }

  CindelQuery<Product> priceCentsGreaterThan(int value) {
    return _query.whereMatches(
      CindelFilter.field("priceCents").greaterThan(value),
    );
  }

  CindelQuery<Product> priceCentsGreaterThanOrEqualTo(int value) {
    return _query.whereMatches(
      CindelFilter.field("priceCents").greaterThanOrEqualTo(value),
    );
  }

  CindelQuery<Product> priceCentsLessThan(int value) {
    return _query.whereMatches(
      CindelFilter.field("priceCents").lessThan(value),
    );
  }

  CindelQuery<Product> priceCentsLessThanOrEqualTo(int value) {
    return _query.whereMatches(
      CindelFilter.field("priceCents").lessThanOrEqualTo(value),
    );
  }

  CindelQuery<Product> priceCentsBetween(int? lower, int? upper) {
    return _query.whereMatches(
      CindelFilter.field("priceCents").between(lower, upper),
    );
  }

  CindelQuery<Product> stockEqualTo(int value) {
    return _query.whereMatches(CindelFilter.field("stock").equalTo(value));
  }

  CindelQuery<Product> stockGreaterThan(int value) {
    return _query.whereMatches(CindelFilter.field("stock").greaterThan(value));
  }

  CindelQuery<Product> stockGreaterThanOrEqualTo(int value) {
    return _query.whereMatches(
      CindelFilter.field("stock").greaterThanOrEqualTo(value),
    );
  }

  CindelQuery<Product> stockLessThan(int value) {
    return _query.whereMatches(CindelFilter.field("stock").lessThan(value));
  }

  CindelQuery<Product> stockLessThanOrEqualTo(int value) {
    return _query.whereMatches(
      CindelFilter.field("stock").lessThanOrEqualTo(value),
    );
  }

  CindelQuery<Product> stockBetween(int? lower, int? upper) {
    return _query.whereMatches(
      CindelFilter.field("stock").between(lower, upper),
    );
  }

  CindelQuery<Product> createdAtMicrosEqualTo(int value) {
    return _query.whereMatches(
      CindelFilter.field("createdAtMicros").equalTo(value),
    );
  }

  CindelQuery<Product> createdAtMicrosGreaterThan(int value) {
    return _query.whereMatches(
      CindelFilter.field("createdAtMicros").greaterThan(value),
    );
  }

  CindelQuery<Product> createdAtMicrosGreaterThanOrEqualTo(int value) {
    return _query.whereMatches(
      CindelFilter.field("createdAtMicros").greaterThanOrEqualTo(value),
    );
  }

  CindelQuery<Product> createdAtMicrosLessThan(int value) {
    return _query.whereMatches(
      CindelFilter.field("createdAtMicros").lessThan(value),
    );
  }

  CindelQuery<Product> createdAtMicrosLessThanOrEqualTo(int value) {
    return _query.whereMatches(
      CindelFilter.field("createdAtMicros").lessThanOrEqualTo(value),
    );
  }

  CindelQuery<Product> createdAtMicrosBetween(int? lower, int? upper) {
    return _query.whereMatches(
      CindelFilter.field("createdAtMicros").between(lower, upper),
    );
  }

  CindelQuery<Product> tagsEqualTo(List<String> value) {
    return _query.whereMatches(
      CindelFilter.field(
        "tags",
      ).equalTo(value.map((value) => value).toList(growable: false)),
    );
  }

  CindelQuery<Product> tagsElementEqualTo(String value) {
    return _query.whereMatches(CindelFilter.field("tags").contains(value));
  }

  CindelQuery<Product> tagsIsEmpty() {
    return _query.whereMatches(CindelFilter.field("tags").isEmpty());
  }

  CindelQuery<Product> tagsIsNotEmpty() {
    return _query.whereMatches(CindelFilter.field("tags").isNotEmpty());
  }

  CindelQuery<Product> tagsLengthEqualTo(int length) {
    return _query.whereMatches(
      CindelFilter.field("tags").lengthEqualTo(length),
    );
  }

  CindelQuery<Product> tagsLengthLessThan(int length, {bool include = false}) {
    return _query.whereMatches(
      CindelFilter.field("tags").lengthLessThan(length, include: include),
    );
  }

  CindelQuery<Product> tagsLengthGreaterThan(
    int length, {
    bool include = false,
  }) {
    return _query.whereMatches(
      CindelFilter.field("tags").lengthGreaterThan(length, include: include),
    );
  }

  CindelQuery<Product> tagsLengthBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return _query.whereMatches(
      CindelFilter.field("tags").lengthBetween(
        lower,
        upper,
        includeLower: includeLower,
        includeUpper: includeUpper,
      ),
    );
  }

  CindelQuery<Product> optional(
    bool enabled,
    CindelQuery<Product> Function(ProductQueryFilter q) option,
  ) {
    return _query.optional(
      enabled,
      (query) => option(ProductQueryFilter(query)),
    );
  }

  CindelQuery<Product> anyOf<E>(
    Iterable<E> items,
    CindelQuery<Product> Function(ProductQueryFilter q, E item) option,
  ) {
    return _query.anyOf(
      items,
      (query, item) => option(ProductQueryFilter(query), item),
    );
  }

  CindelQuery<Product> allOf<E>(
    Iterable<E> items,
    CindelQuery<Product> Function(ProductQueryFilter q, E item) option,
  ) {
    return _query.allOf(
      items,
      (query, item) => option(ProductQueryFilter(query), item),
    );
  }
}

final class ProductQueryWhere {
  const ProductQueryWhere(this._collection);

  final CindelTypedCollection<Product> _collection;

  CindelQuery<Product> skuEqualTo(String value) {
    return CindelQuery.equal(
      database: _collection.database,
      schema: ProductSchema,
      field: "sku",
      value: value,
    );
  }

  CindelQuery<Product> skuStartsWith(String prefix) {
    return CindelQuery.stringStartsWith(
      database: _collection.database,
      schema: ProductSchema,
      field: "sku",
      prefix: prefix,
    );
  }

  CindelQuery<Product> skuBetween(String? lower, String? upper) {
    return CindelQuery.range(
      database: _collection.database,
      schema: ProductSchema,
      field: "sku",
      lower: lower,
      upper: upper,
    );
  }

  CindelQuery<Product> nameEqualTo(String value) {
    return CindelQuery.equal(
      database: _collection.database,
      schema: ProductSchema,
      field: "name",
      value: value,
    );
  }

  CindelQuery<Product> nameStartsWith(String prefix) {
    return CindelQuery.stringStartsWith(
      database: _collection.database,
      schema: ProductSchema,
      field: "name",
      prefix: prefix,
    );
  }

  CindelQuery<Product> nameBetween(String? lower, String? upper) {
    return CindelQuery.range(
      database: _collection.database,
      schema: ProductSchema,
      field: "name",
      lower: lower,
      upper: upper,
    );
  }

  CindelQuery<Product> searchTextEqualTo(String word) {
    return searchTextWordEqualTo(word);
  }

  CindelQuery<Product> searchTextStartsWith(String prefix) {
    return searchTextWordStartsWith(prefix);
  }

  CindelQuery<Product> searchTextWordEqualTo(String word) {
    return CindelQuery.wordsContain(
      database: _collection.database,
      schema: ProductSchema,
      field: "searchText",
      word: word,
    );
  }

  CindelQuery<Product> searchTextWordStartsWith(String prefix) {
    return CindelQuery.wordsStartWith(
      database: _collection.database,
      schema: ProductSchema,
      field: "searchText",
      prefix: prefix,
    );
  }

  CindelQuery<Product> searchTextWordsContain(String word) {
    return searchTextWordEqualTo(word);
  }

  CindelQuery<Product> searchTextWordsStartWith(String prefix) {
    return searchTextWordStartsWith(prefix);
  }

  CindelQuery<Product> categoryEqualTo(String value) {
    return CindelQuery.equal(
      database: _collection.database,
      schema: ProductSchema,
      field: "category",
      value: value,
    );
  }

  CindelQuery<Product> categoryStartsWith(String prefix) {
    return CindelQuery.stringStartsWith(
      database: _collection.database,
      schema: ProductSchema,
      field: "category",
      prefix: prefix,
    );
  }

  CindelQuery<Product> categoryBetween(String? lower, String? upper) {
    return CindelQuery.range(
      database: _collection.database,
      schema: ProductSchema,
      field: "category",
      lower: lower,
      upper: upper,
    );
  }

  CindelQuery<Product> priceCentsEqualTo(int value) {
    return CindelQuery.equal(
      database: _collection.database,
      schema: ProductSchema,
      field: "priceCents",
      value: value,
    );
  }

  CindelQuery<Product> priceCentsBetween(int? lower, int? upper) {
    return CindelQuery.range(
      database: _collection.database,
      schema: ProductSchema,
      field: "priceCents",
      lower: lower,
      upper: upper,
    );
  }

  CindelQuery<Product> stockEqualTo(int value) {
    return CindelQuery.equal(
      database: _collection.database,
      schema: ProductSchema,
      field: "stock",
      value: value,
    );
  }

  CindelQuery<Product> stockBetween(int? lower, int? upper) {
    return CindelQuery.range(
      database: _collection.database,
      schema: ProductSchema,
      field: "stock",
      lower: lower,
      upper: upper,
    );
  }

  CindelQuery<Product> tagsContains(String value) {
    return CindelQuery.equal(
      database: _collection.database,
      schema: ProductSchema,
      field: "tags",
      value: value,
    );
  }
}

Map<String, Object?> _$ProductToCindelDocument(Product object) {
  return <String, Object?>{
    "sku": object.sku,
    "name": object.name,
    "description": object.description,
    "searchText": object.searchText,
    "category": object.category,
    "priceCents": object.priceCents,
    "stock": object.stock,
    "createdAtMicros": object.createdAtMicros,
    "tags": object.tags.map((value) => value).toList(growable: false),
  };
}

Product _$ProductFromCindelDocument(Map<String, Object?> document) {
  return Product(
    dbId: document["dbId"] as int,
    sku: document["sku"] as String,
    name: document["name"] as String,
    description: document["description"] as String,
    searchText: document["searchText"] as String,
    category: document["category"] as String,
    priceCents: document["priceCents"] as int,
    stock: document["stock"] as int,
    createdAtMicros: document["createdAtMicros"] as int,
    tags: (document["tags"] as List<Object?>)
        .map((value) => value as String)
        .toList(growable: false),
  );
}

CindelBinaryDocumentBytes _$ProductToCindelBinaryDocument(Product object) {
  return cindelEncodeSchemaBinaryDocument(
    <Object?>[
      object.category,
      object.createdAtMicros,
      object.description,
      object.name,
      object.priceCents,
      object.searchText,
      object.sku,
      object.stock,
      object.tags.map((value) => value).toList(growable: false),
    ],
    const <CindelBinaryFieldType>[
      CindelBinaryFieldType.stringValue,
      CindelBinaryFieldType.intValue,
      CindelBinaryFieldType.stringValue,
      CindelBinaryFieldType.stringValue,
      CindelBinaryFieldType.intValue,
      CindelBinaryFieldType.stringValue,
      CindelBinaryFieldType.stringValue,
      CindelBinaryFieldType.intValue,
      CindelBinaryFieldType.listValue,
    ],
  );
}

Product _$ProductFromCindelBinaryDocument(CindelBinaryDocumentBytes bytes) {
  final reader = CindelSchemaBinaryDocumentReader(bytes, staticSize: 42);
  final Object? field0 = reader.readString(0, 0);
  final Object? field1 = reader.readInt(1, 3);
  final Object? field2 = reader.readString(2, 11);
  final Object? field3 = reader.readString(3, 14);
  final Object? field4 = reader.readInt(4, 17);
  final Object? field5 = reader.readString(5, 25);
  final Object? field6 = reader.readString(6, 28);
  final Object? field7 = reader.readInt(7, 31);
  final Object? field8 = reader.readList(8, 39);
  return Product(
    dbId: autoIncrement,
    sku: field6 as String,
    name: field3 as String,
    description: field2 as String,
    searchText: field5 as String,
    category: field0 as String,
    priceCents: field4 as int,
    stock: field7 as int,
    createdAtMicros: field1 as int,
    tags: (field8 as List<Object?>)
        .map((value) => value as String)
        .toList(growable: false),
  );
}

void _$ProductWriteCindelNativeDocument(
  CindelNativeDocumentWriter writer,
  Product object,
) {
  writer.writeString(0, object.category);
  writer.writeInt(1, object.createdAtMicros);
  writer.writeString(2, object.description);
  writer.writeString(3, object.name);
  writer.writeInt(4, object.priceCents);
  writer.writeString(5, object.searchText);
  writer.writeString(6, object.sku);
  writer.writeInt(7, object.stock);
  cindelWriteNativeStringList(writer, 8, object.tags);
}

Product _$ProductReadCindelNativeDocument(
  CindelNativeDocumentReader reader,
  int documentIndex,
) {
  return Product(
    dbId: reader.readId(documentIndex),
    sku: reader.readString(documentIndex, 6) as String,
    name: reader.readString(documentIndex, 3) as String,
    description: reader.readString(documentIndex, 2) as String,
    searchText: reader.readString(documentIndex, 5) as String,
    category: reader.readString(documentIndex, 0) as String,
    priceCents: reader.readInt(documentIndex, 4) as int,
    stock: reader.readInt(documentIndex, 7) as int,
    createdAtMicros: reader.readInt(documentIndex, 1) as int,
    tags: reader.readStringList(documentIndex, 8) ?? const <String>[],
  );
}

int _$ProductGetCindelId(Product object) {
  return object.dbId;
}
