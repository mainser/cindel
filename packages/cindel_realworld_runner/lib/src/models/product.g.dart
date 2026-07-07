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
      isIndexReplace: true,
      indexCaseSensitive: false,
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
      indexCaseSensitive: false,
      indexType: CindelIndexType.value,
    ),
    CindelFieldSchema(
      name: "description",
      dartType: "String?",
      binaryType: "string",
      isId: false,
      isIndexed: true,
      isIndexUnique: false,
      isIndexReplace: false,
      indexCaseSensitive: false,
      indexType: CindelIndexType.words,
    ),
    CindelFieldSchema(
      name: "price",
      dartType: "double",
      binaryType: "double",
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
      name: "active",
      dartType: "bool",
      binaryType: "bool",
      isId: false,
      isIndexed: false,
      isIndexUnique: false,
      isIndexReplace: false,
      indexCaseSensitive: true,
      indexType: CindelIndexType.value,
    ),
    CindelFieldSchema(
      name: "createdAt",
      dartType: "DateTime",
      binaryType: "int",
      isId: false,
      isIndexed: true,
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
    CindelFieldSchema(
      name: "details",
      dartType: "ProductDetails?",
      binaryType: "object",
      isId: false,
      isIndexed: false,
      isIndexUnique: false,
      isIndexReplace: false,
      indexCaseSensitive: true,
      indexType: CindelIndexType.value,
    ),
  ],
  links: <CindelLinkSchema>[
    CindelLinkSchema(
      name: "category",
      dartName: "category",
      targetCollection: "categories",
      isToMany: false,
      isBacklink: false,
      backlinkTo: null,
    ),
  ],
  compositeIndexes: <CindelCompositeIndexSchema>[
    CindelCompositeIndexSchema(
      name: "active_stock",
      fields: <String>["active", "stock"],
      isUnique: false,
      isReplace: false,
      caseSensitive: true,
    ),
  ],
  toDocument: _$ProductToCindelDocument,
  fromDocument: _$ProductFromCindelDocument,
  toBinaryDocument: _$ProductToCindelBinaryDocument,
  fromBinaryDocument: _$ProductFromCindelBinaryDocument,
  writeNativeDocument: _$ProductWriteCindelNativeDocument,
  readNativeDocument: _$ProductReadCindelNativeDocument,
  getId: _$ProductGetCindelId,
  setId: _$ProductSetCindelId,
  bindLinks: _$ProductBindCindelLinks,
);

void _$ProductBindCindelLinks(
  Object database,
  CindelCollectionSchema<Product> schema,
  Product object,
) {
  final cindelDatabase = database as CindelDatabase;
  final ownerSchema = schema as dynamic;
  object.category.bind(
    cindelDatabase,
    ownerSchema,
    object,
    schema.links.firstWhere((link) => link.dartName == "category"),
  );
}

extension ProductCindelCollectionAccess on CindelDatabase {
  CindelTypedCollection<Product> get products => typedCollection(ProductSchema);
}

extension ProductCindelQueryAccess on CindelTypedCollection<Product> {
  ProductQueryWhere where() => ProductQueryWhere(this);

  ProductQueryFilter filter() => ProductQueryFilter(
    CindelQuery.all(database: database, schema: ProductSchema),
  );

  Future<void> putBySku(Product object) {
    return putByUniqueIndex(
      object,
      indexName: "sku",
      values: <Object?>[object.sku],
      isComposite: false,
    );
  }

  Future<void> putAllBySku(Iterable<Product> objects) {
    return putAllByUniqueIndex(
      objects,
      indexName: "sku",
      values: (object) => <Object?>[object.sku],
      isComposite: false,
    );
  }
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

  CindelPropertyQuery<Product, String?> descriptionProperty() {
    return property<String?>("description");
  }

  CindelQuery<Product> sortByPrice({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return sortBy("price", order: order);
  }

  CindelQuery<Product> sortByPriceDesc() {
    return sortBy("price", order: CindelSortOrder.descending);
  }

  CindelQuery<Product> thenByPrice({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return thenBy("price", order: order);
  }

  CindelQuery<Product> thenByPriceDesc() {
    return thenBy("price", order: CindelSortOrder.descending);
  }

  CindelQuery<Product> distinctByPrice() {
    return distinctBy("price");
  }

  CindelPropertyQuery<Product, double> priceProperty() {
    return property<double>("price");
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

  CindelQuery<Product> sortByActive({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return sortBy("active", order: order);
  }

  CindelQuery<Product> sortByActiveDesc() {
    return sortBy("active", order: CindelSortOrder.descending);
  }

  CindelQuery<Product> thenByActive({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return thenBy("active", order: order);
  }

  CindelQuery<Product> thenByActiveDesc() {
    return thenBy("active", order: CindelSortOrder.descending);
  }

  CindelQuery<Product> distinctByActive() {
    return distinctBy("active");
  }

  CindelPropertyQuery<Product, bool> activeProperty() {
    return property<bool>("active");
  }

  CindelQuery<Product> sortByCreatedAt({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return sortBy("createdAt", order: order);
  }

  CindelQuery<Product> sortByCreatedAtDesc() {
    return sortBy("createdAt", order: CindelSortOrder.descending);
  }

  CindelQuery<Product> thenByCreatedAt({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return thenBy("createdAt", order: order);
  }

  CindelQuery<Product> thenByCreatedAtDesc() {
    return thenBy("createdAt", order: CindelSortOrder.descending);
  }

  CindelQuery<Product> distinctByCreatedAt() {
    return distinctBy("createdAt");
  }

  CindelPropertyQuery<Product, DateTime> createdAtProperty() {
    return property<DateTime>(
      "createdAt",
      decode: (value) =>
          DateTime.fromMicrosecondsSinceEpoch(value as int, isUtc: true),
    );
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

  CindelQuery<Product> sortByDetails({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return sortBy("details", order: order);
  }

  CindelQuery<Product> sortByDetailsDesc() {
    return sortBy("details", order: CindelSortOrder.descending);
  }

  CindelQuery<Product> thenByDetails({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return thenBy("details", order: order);
  }

  CindelQuery<Product> thenByDetailsDesc() {
    return thenBy("details", order: CindelSortOrder.descending);
  }

  CindelQuery<Product> distinctByDetails() {
    return distinctBy("details");
  }

  CindelPropertyQuery<Product, ProductDetails?> detailsProperty() {
    return property<ProductDetails?>(
      "details",
      decode: (value) => value == null
          ? null
          : _$ProductDetailsFromCindelEmbedded(
              (value as Map).cast<String, Object?>(),
            ),
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

  CindelQuery<Product> descriptionEqualTo(String? value) {
    return _query.whereMatches(
      CindelFilter.field("description").equalTo(value),
    );
  }

  CindelQuery<Product> priceEqualTo(double value) {
    return _query.whereMatches(CindelFilter.field("price").equalTo(value));
  }

  CindelQuery<Product> priceGreaterThan(double value) {
    return _query.whereMatches(CindelFilter.field("price").greaterThan(value));
  }

  CindelQuery<Product> priceGreaterThanOrEqualTo(double value) {
    return _query.whereMatches(
      CindelFilter.field("price").greaterThanOrEqualTo(value),
    );
  }

  CindelQuery<Product> priceLessThan(double value) {
    return _query.whereMatches(CindelFilter.field("price").lessThan(value));
  }

  CindelQuery<Product> priceLessThanOrEqualTo(double value) {
    return _query.whereMatches(
      CindelFilter.field("price").lessThanOrEqualTo(value),
    );
  }

  CindelQuery<Product> priceBetween(double? lower, double? upper) {
    return _query.whereMatches(
      CindelFilter.field("price").between(lower, upper),
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

  CindelQuery<Product> activeEqualTo(bool value) {
    return _query.whereMatches(CindelFilter.field("active").equalTo(value));
  }

  CindelQuery<Product> createdAtEqualTo(DateTime value) {
    return _query.whereMatches(
      CindelFilter.field("createdAt").equalTo(value.microsecondsSinceEpoch),
    );
  }

  CindelQuery<Product> createdAtGreaterThan(DateTime value) {
    return _query.whereMatches(
      CindelFilter.field("createdAt").greaterThan(value.microsecondsSinceEpoch),
    );
  }

  CindelQuery<Product> createdAtGreaterThanOrEqualTo(DateTime value) {
    return _query.whereMatches(
      CindelFilter.field(
        "createdAt",
      ).greaterThanOrEqualTo(value.microsecondsSinceEpoch),
    );
  }

  CindelQuery<Product> createdAtLessThan(DateTime value) {
    return _query.whereMatches(
      CindelFilter.field("createdAt").lessThan(value.microsecondsSinceEpoch),
    );
  }

  CindelQuery<Product> createdAtLessThanOrEqualTo(DateTime value) {
    return _query.whereMatches(
      CindelFilter.field(
        "createdAt",
      ).lessThanOrEqualTo(value.microsecondsSinceEpoch),
    );
  }

  CindelQuery<Product> createdAtBetween(DateTime? lower, DateTime? upper) {
    return _query.whereMatches(
      CindelFilter.field(
        "createdAt",
      ).between(lower?.microsecondsSinceEpoch, upper?.microsecondsSinceEpoch),
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

  CindelQuery<Product> detailsEqualTo(ProductDetails? value) {
    return _query.whereMatches(
      CindelFilter.field(
        "details",
      ).equalTo(value == null ? null : _$ProductDetailsToCindelEmbedded(value)),
    );
  }

  CindelQuery<Product> details(
    CindelFilterPredicate Function(ProductProductDetailsCindelEmbeddedFilter q)
    filter,
  ) {
    return _query.whereMatches(
      filter(
        const ProductProductDetailsCindelEmbeddedFilter._(<String>["details"]),
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

  CindelQuery<Product> descriptionEqualTo(String word) {
    return descriptionWordEqualTo(word);
  }

  CindelQuery<Product> descriptionStartsWith(String prefix) {
    return descriptionWordStartsWith(prefix);
  }

  CindelQuery<Product> descriptionWordEqualTo(String word) {
    return CindelQuery.wordsContain(
      database: _collection.database,
      schema: ProductSchema,
      field: "description",
      word: word,
    );
  }

  CindelQuery<Product> descriptionWordStartsWith(String prefix) {
    return CindelQuery.wordsStartWith(
      database: _collection.database,
      schema: ProductSchema,
      field: "description",
      prefix: prefix,
    );
  }

  CindelQuery<Product> descriptionWordsContain(String word) {
    return descriptionWordEqualTo(word);
  }

  CindelQuery<Product> descriptionWordsStartWith(String prefix) {
    return descriptionWordStartsWith(prefix);
  }

  CindelQuery<Product> priceEqualTo(double value) {
    return CindelQuery.equal(
      database: _collection.database,
      schema: ProductSchema,
      field: "price",
      value: value,
    );
  }

  CindelQuery<Product> priceBetween(double? lower, double? upper) {
    return CindelQuery.range(
      database: _collection.database,
      schema: ProductSchema,
      field: "price",
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

  CindelQuery<Product> createdAtEqualTo(DateTime value) {
    return CindelQuery.equal(
      database: _collection.database,
      schema: ProductSchema,
      field: "createdAt",
      value: value.microsecondsSinceEpoch,
    );
  }

  CindelQuery<Product> createdAtBetween(DateTime? lower, DateTime? upper) {
    return CindelQuery.range(
      database: _collection.database,
      schema: ProductSchema,
      field: "createdAt",
      lower: lower?.microsecondsSinceEpoch,
      upper: upper?.microsecondsSinceEpoch,
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

  CindelQuery<Product> activeStockEqualTo(bool active, int stock) {
    return CindelQuery.compositeEqual(
      database: _collection.database,
      schema: ProductSchema,
      index: "active_stock",
      values: <Object>[active, stock],
    );
  }
}

final class ProductProductDetailsCindelEmbeddedFilter {
  const ProductProductDetailsCindelEmbeddedFilter._(this._path);

  final List<String> _path;

  CindelFilterPredicate manufacturerEqualTo(String? value) {
    return CindelFilter.path(<String>[..._path, "manufacturer"]).equalTo(value);
  }

  CindelFilterPredicate manufacturerContains(String value) {
    return CindelFilter.path(<String>[
      ..._path,
      "manufacturer",
    ]).contains(value);
  }

  CindelFilterPredicate manufacturerStartsWith(String value) {
    return CindelFilter.path(<String>[
      ..._path,
      "manufacturer",
    ]).startsWith(value);
  }

  CindelFilterPredicate manufacturerEndsWith(String value) {
    return CindelFilter.path(<String>[
      ..._path,
      "manufacturer",
    ]).endsWith(value);
  }

  CindelFilterPredicate weightEqualTo(double value) {
    return CindelFilter.path(<String>[..._path, "weight"]).equalTo(value);
  }

  CindelFilterPredicate weightGreaterThan(double value) {
    return CindelFilter.path(<String>[..._path, "weight"]).greaterThan(value);
  }

  CindelFilterPredicate weightGreaterThanOrEqualTo(double value) {
    return CindelFilter.path(<String>[
      ..._path,
      "weight",
    ]).greaterThanOrEqualTo(value);
  }

  CindelFilterPredicate weightLessThan(double value) {
    return CindelFilter.path(<String>[..._path, "weight"]).lessThan(value);
  }

  CindelFilterPredicate weightLessThanOrEqualTo(double value) {
    return CindelFilter.path(<String>[
      ..._path,
      "weight",
    ]).lessThanOrEqualTo(value);
  }

  CindelFilterPredicate weightBetween(double? lower, double? upper) {
    return CindelFilter.path(<String>[
      ..._path,
      "weight",
    ]).between(lower, upper);
  }

  CindelFilterPredicate materialsEqualTo(List<String> value) {
    return CindelFilter.path(<String>[
      ..._path,
      "materials",
    ]).equalTo(value.map((value) => value).toList(growable: false));
  }

  CindelFilterPredicate materialsElementEqualTo(String value) {
    return CindelFilter.path(<String>[..._path, "materials"]).contains(value);
  }

  CindelFilterPredicate materialsIsEmpty() {
    return CindelFilter.path(<String>[..._path, "materials"]).isEmpty();
  }

  CindelFilterPredicate materialsIsNotEmpty() {
    return CindelFilter.path(<String>[..._path, "materials"]).isNotEmpty();
  }

  CindelFilterPredicate materialsLengthEqualTo(int length) {
    return CindelFilter.path(<String>[
      ..._path,
      "materials",
    ]).lengthEqualTo(length);
  }

  CindelFilterPredicate materialsLengthLessThan(
    int length, {
    bool include = false,
  }) {
    return CindelFilter.path(<String>[
      ..._path,
      "materials",
    ]).lengthLessThan(length, include: include);
  }

  CindelFilterPredicate materialsLengthGreaterThan(
    int length, {
    bool include = false,
  }) {
    return CindelFilter.path(<String>[
      ..._path,
      "materials",
    ]).lengthGreaterThan(length, include: include);
  }

  CindelFilterPredicate materialsLengthBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return CindelFilter.path(<String>[..._path, "materials"]).lengthBetween(
      lower,
      upper,
      includeLower: includeLower,
      includeUpper: includeUpper,
    );
  }

  CindelFilterPredicate warrantyEqualTo(Warranty? value) {
    return CindelFilter.path(<String>[
      ..._path,
      "warranty",
    ]).equalTo(value == null ? null : _$WarrantyToCindelEmbedded(value));
  }

  CindelFilterPredicate warranty(
    CindelFilterPredicate Function(ProductWarrantyCindelEmbeddedFilter q)
    filter,
  ) {
    return filter(
      ProductWarrantyCindelEmbeddedFilter._(<String>[..._path, "warranty"]),
    );
  }
}

final class ProductWarrantyCindelEmbeddedFilter {
  const ProductWarrantyCindelEmbeddedFilter._(this._path);

  final List<String> _path;

  CindelFilterPredicate monthsEqualTo(int value) {
    return CindelFilter.path(<String>[..._path, "months"]).equalTo(value);
  }

  CindelFilterPredicate monthsGreaterThan(int value) {
    return CindelFilter.path(<String>[..._path, "months"]).greaterThan(value);
  }

  CindelFilterPredicate monthsGreaterThanOrEqualTo(int value) {
    return CindelFilter.path(<String>[
      ..._path,
      "months",
    ]).greaterThanOrEqualTo(value);
  }

  CindelFilterPredicate monthsLessThan(int value) {
    return CindelFilter.path(<String>[..._path, "months"]).lessThan(value);
  }

  CindelFilterPredicate monthsLessThanOrEqualTo(int value) {
    return CindelFilter.path(<String>[
      ..._path,
      "months",
    ]).lessThanOrEqualTo(value);
  }

  CindelFilterPredicate monthsBetween(int? lower, int? upper) {
    return CindelFilter.path(<String>[
      ..._path,
      "months",
    ]).between(lower, upper);
  }

  CindelFilterPredicate providerEqualTo(String? value) {
    return CindelFilter.path(<String>[..._path, "provider"]).equalTo(value);
  }

  CindelFilterPredicate providerContains(String value) {
    return CindelFilter.path(<String>[..._path, "provider"]).contains(value);
  }

  CindelFilterPredicate providerStartsWith(String value) {
    return CindelFilter.path(<String>[..._path, "provider"]).startsWith(value);
  }

  CindelFilterPredicate providerEndsWith(String value) {
    return CindelFilter.path(<String>[..._path, "provider"]).endsWith(value);
  }
}

Map<String, Object?> _$ProductToCindelDocument(Product object) {
  return <String, Object?>{
    "sku": object.sku,
    "name": object.name,
    "description": object.description,
    "price": object.price,
    "stock": object.stock,
    "active": object.active,
    "createdAt": object.createdAt.microsecondsSinceEpoch,
    "tags": object.tags.map((value) => value).toList(growable: false),
    "details": object.details == null
        ? null
        : _$ProductDetailsToCindelEmbedded(object.details as ProductDetails),
  };
}

Product _$ProductFromCindelDocument(Map<String, Object?> document) {
  final object = Product();
  object.dbId = document["dbId"] as int;
  object.sku = document["sku"] as String;
  object.name = document["name"] as String;
  object.description = document["description"] == null
      ? null
      : document["description"] as String?;
  object.price = document["price"] as double;
  object.stock = document["stock"] as int;
  object.active = document["active"] as bool;
  object.createdAt = DateTime.fromMicrosecondsSinceEpoch(
    document["createdAt"] as int,
    isUtc: true,
  );
  object.tags = (document["tags"] as List<Object?>)
      .map((value) => value as String)
      .toList(growable: false);
  object.details = document["details"] == null
      ? null
      : _$ProductDetailsFromCindelEmbedded(
          (document["details"] as Map).cast<String, Object?>(),
        );
  return object;
}

CindelBinaryDocumentBytes _$ProductToCindelBinaryDocument(Product object) {
  return cindelEncodeSchemaBinaryDocument(
    <Object?>[
      object.active,
      object.createdAt.microsecondsSinceEpoch,
      object.description,
      object.details == null
          ? null
          : _$ProductDetailsToCindelEmbedded(object.details as ProductDetails),
      object.name,
      object.price,
      object.sku,
      object.stock,
      object.tags.map((value) => value).toList(growable: false),
    ],
    const <CindelBinaryFieldType>[
      CindelBinaryFieldType.boolValue,
      CindelBinaryFieldType.intValue,
      CindelBinaryFieldType.stringValue,
      CindelBinaryFieldType.objectValue,
      CindelBinaryFieldType.stringValue,
      CindelBinaryFieldType.doubleValue,
      CindelBinaryFieldType.stringValue,
      CindelBinaryFieldType.intValue,
      CindelBinaryFieldType.listValue,
    ],
  );
}

Product _$ProductFromCindelBinaryDocument(CindelBinaryDocumentBytes bytes) {
  final reader = CindelSchemaBinaryDocumentReader(bytes, staticSize: 40);
  final Object? field0 = reader.readBool(0, 0);
  final Object? field1 = reader.readInt(1, 1);
  final Object? field2 = reader.readString(2, 9);
  final Object? field3 = reader.readObject(3, 12);
  final Object? field4 = reader.readString(4, 15);
  final Object? field5 = reader.readDouble(5, 18);
  final Object? field6 = reader.readString(6, 26);
  final Object? field7 = reader.readInt(7, 29);
  final Object? field8 = reader.readList(8, 37);
  final object = Product();
  object.dbId = autoIncrement;
  object.sku = field6 as String;
  object.name = field4 as String;
  object.description = field2 == null ? null : field2 as String?;
  object.price = field5 as double;
  object.stock = field7 as int;
  object.active = field0 as bool;
  object.createdAt = DateTime.fromMicrosecondsSinceEpoch(
    field1 as int,
    isUtc: true,
  );
  object.tags = (field8 as List<Object?>)
      .map((value) => value as String)
      .toList(growable: false);
  object.details = field3 == null
      ? null
      : _$ProductDetailsFromCindelEmbedded(
          (field3 as Map).cast<String, Object?>(),
        );
  return object;
}

void _$ProductWriteCindelNativeDocument(
  CindelNativeDocumentWriter writer,
  Product object,
) {
  writer.writeBool(0, object.active);
  writer.writeInt(1, object.createdAt.microsecondsSinceEpoch);
  {
    final value = object.description;
    if (value == null) {
      writer.writeNull(2);
    } else {
      writer.writeString(2, value);
    }
  }
  {
    final value = object.details;
    if (value == null) {
      writer.writeNull(3);
    } else {
      cindelWriteNativeObject<ProductDetails>(
        writer,
        3,
        _$ProductDetailsCindelNativeFieldNames,
        value,
        _$ProductDetailsWriteCindelNativeEmbedded,
        _$ProductDetailsToCindelEmbedded,
      );
    }
  }
  writer.writeString(4, object.name);
  writer.writeDouble(5, object.price);
  writer.writeString(6, object.sku);
  writer.writeInt(7, object.stock);
  cindelWriteNativeStringList(writer, 8, object.tags);
}

Product _$ProductReadCindelNativeDocument(
  CindelNativeDocumentReader reader,
  int documentIndex,
) {
  final object = Product();
  object.dbId = reader.readId(documentIndex);
  object.sku = reader.readString(documentIndex, 6) as String;
  object.name = reader.readString(documentIndex, 4) as String;
  object.description = reader.readString(documentIndex, 2);
  object.price = reader.readDouble(documentIndex, 5) as double;
  object.stock = reader.readInt(documentIndex, 7) as int;
  object.active = reader.readBool(documentIndex, 0) as bool;
  object.createdAt = DateTime.fromMicrosecondsSinceEpoch(
    reader.readInt(documentIndex, 1) as int,
    isUtc: true,
  );
  object.tags = reader.readStringList(documentIndex, 8) ?? const <String>[];
  object.details = cindelReadNativeObject<ProductDetails>(
    reader,
    documentIndex,
    3,
    _$ProductDetailsCindelNativeFieldNames,
    _$ProductDetailsReadCindelNativeEmbedded,
    _$ProductDetailsFromCindelEmbedded,
  );
  return object;
}

int _$ProductGetCindelId(Product object) {
  return object.dbId;
}

void _$ProductSetCindelId(Product object, int id) {
  object.dbId = id;
}

const _$ProductDetailsCindelNativeFieldNames = <String>[
  "manufacturer",
  "weight",
  "materials",
  "warranty",
];

Map<String, Object?> _$ProductDetailsToCindelEmbedded(ProductDetails object) {
  return <String, Object?>{
    "manufacturer": object.manufacturer,
    "weight": object.weight,
    "materials": object.materials.map((value) => value).toList(growable: false),
    "warranty": object.warranty == null
        ? null
        : _$WarrantyToCindelEmbedded(object.warranty as Warranty),
  };
}

ProductDetails _$ProductDetailsFromCindelEmbedded(
  Map<String, Object?> document,
) {
  final object = ProductDetails();
  object.manufacturer = document["manufacturer"] == null
      ? null
      : document["manufacturer"] as String?;
  object.weight = document["weight"] as double;
  object.materials = (document["materials"] as List<Object?>)
      .map((value) => value as String)
      .toList(growable: false);
  object.warranty = document["warranty"] == null
      ? null
      : _$WarrantyFromCindelEmbedded(
          (document["warranty"] as Map).cast<String, Object?>(),
        );
  return object;
}

void _$ProductDetailsWriteCindelNativeEmbedded(
  CindelNativeDocumentWriter writer,
  ProductDetails object,
) {
  {
    final value = object.manufacturer;
    if (value == null) {
      writer.writeNull(0);
    } else {
      writer.writeString(0, value);
    }
  }
  writer.writeDouble(1, object.weight);
  cindelWriteNativeStringList(writer, 2, object.materials);
  {
    final value = object.warranty;
    if (value == null) {
      writer.writeNull(3);
    } else {
      cindelWriteNativeObject<Warranty>(
        writer,
        3,
        _$WarrantyCindelNativeFieldNames,
        value,
        _$WarrantyWriteCindelNativeEmbedded,
        _$WarrantyToCindelEmbedded,
      );
    }
  }
}

ProductDetails _$ProductDetailsReadCindelNativeEmbedded(
  CindelNativeDocumentReader reader,
  int documentIndex,
) {
  final object = ProductDetails();
  object.manufacturer = reader.readString(documentIndex, 0);
  object.weight = reader.readDouble(documentIndex, 1) as double;
  object.materials =
      reader.readStringList(documentIndex, 2) ?? const <String>[];
  object.warranty = cindelReadNativeObject<Warranty>(
    reader,
    documentIndex,
    3,
    _$WarrantyCindelNativeFieldNames,
    _$WarrantyReadCindelNativeEmbedded,
    _$WarrantyFromCindelEmbedded,
  );
  return object;
}

const _$WarrantyCindelNativeFieldNames = <String>["months", "provider"];

Map<String, Object?> _$WarrantyToCindelEmbedded(Warranty object) {
  return <String, Object?>{
    "months": object.months,
    "provider": object.provider,
  };
}

Warranty _$WarrantyFromCindelEmbedded(Map<String, Object?> document) {
  final object = Warranty();
  object.months = document["months"] as int;
  object.provider = document["provider"] == null
      ? null
      : document["provider"] as String?;
  return object;
}

void _$WarrantyWriteCindelNativeEmbedded(
  CindelNativeDocumentWriter writer,
  Warranty object,
) {
  writer.writeInt(0, object.months);
  {
    final value = object.provider;
    if (value == null) {
      writer.writeNull(1);
    } else {
      writer.writeString(1, value);
    }
  }
}

Warranty _$WarrantyReadCindelNativeEmbedded(
  CindelNativeDocumentReader reader,
  int documentIndex,
) {
  final object = Warranty();
  object.months = reader.readInt(documentIndex, 0) as int;
  object.provider = reader.readString(documentIndex, 1);
  return object;
}
