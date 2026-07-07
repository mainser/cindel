// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'category.dart';

// **************************************************************************
// CindelGenerator
// **************************************************************************

// ignore_for_file: non_constant_identifier_names

final CategorySchema = CindelCollectionSchema<Category>(
  name: "categories",
  dartName: "Category",
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
      name: "slug",
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
      isIndexed: false,
      isIndexUnique: false,
      isIndexReplace: false,
      indexCaseSensitive: true,
      indexType: CindelIndexType.value,
    ),
    CindelFieldSchema(
      name: "sortOrder",
      dartType: "int",
      binaryType: "int",
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
      name: "products",
      dartName: "products",
      targetCollection: "products",
      isToMany: true,
      isBacklink: true,
      backlinkTo: "category",
    ),
  ],
  compositeIndexes: <CindelCompositeIndexSchema>[],
  toDocument: _$CategoryToCindelDocument,
  fromDocument: _$CategoryFromCindelDocument,
  toBinaryDocument: _$CategoryToCindelBinaryDocument,
  fromBinaryDocument: _$CategoryFromCindelBinaryDocument,
  writeNativeDocument: _$CategoryWriteCindelNativeDocument,
  readNativeDocument: _$CategoryReadCindelNativeDocument,
  getId: _$CategoryGetCindelId,
  setId: _$CategorySetCindelId,
  bindLinks: _$CategoryBindCindelLinks,
);

void _$CategoryBindCindelLinks(
  Object database,
  CindelCollectionSchema<Category> schema,
  Category object,
) {
  final cindelDatabase = database as CindelDatabase;
  final ownerSchema = schema as dynamic;
  object.products.bind(
    cindelDatabase,
    ownerSchema,
    object,
    schema.links.firstWhere((link) => link.dartName == "products"),
  );
}

extension CategoryCindelCollectionAccess on CindelDatabase {
  CindelTypedCollection<Category> get categories =>
      typedCollection(CategorySchema);
}

extension CategoryCindelQueryAccess on CindelTypedCollection<Category> {
  CategoryQueryWhere where() => CategoryQueryWhere(this);

  CategoryQueryFilter filter() => CategoryQueryFilter(
    CindelQuery.all(database: database, schema: CategorySchema),
  );

  Future<void> putBySlug(Category object) {
    return putByUniqueIndex(
      object,
      indexName: "slug",
      values: <Object?>[object.slug],
      isComposite: false,
    );
  }

  Future<void> putAllBySlug(Iterable<Category> objects) {
    return putAllByUniqueIndex(
      objects,
      indexName: "slug",
      values: (object) => <Object?>[object.slug],
      isComposite: false,
    );
  }
}

extension CategoryCindelQueryFilterAccess on CindelQuery<Category> {
  CategoryQueryFilter filter() => CategoryQueryFilter(this);
}

extension CategoryCindelQueryModifierAccess on CindelQuery<Category> {
  CindelQuery<Category> sortByDbId({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return sortBy("dbId", order: order);
  }

  CindelQuery<Category> sortByDbIdDesc() {
    return sortBy("dbId", order: CindelSortOrder.descending);
  }

  CindelQuery<Category> thenByDbId({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return thenBy("dbId", order: order);
  }

  CindelQuery<Category> thenByDbIdDesc() {
    return thenBy("dbId", order: CindelSortOrder.descending);
  }

  CindelQuery<Category> distinctByDbId() {
    return distinctBy("dbId");
  }

  CindelPropertyQuery<Category, int> dbIdProperty() {
    return property<int>("dbId");
  }

  CindelQuery<Category> sortBySlug({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return sortBy("slug", order: order);
  }

  CindelQuery<Category> sortBySlugDesc() {
    return sortBy("slug", order: CindelSortOrder.descending);
  }

  CindelQuery<Category> thenBySlug({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return thenBy("slug", order: order);
  }

  CindelQuery<Category> thenBySlugDesc() {
    return thenBy("slug", order: CindelSortOrder.descending);
  }

  CindelQuery<Category> distinctBySlug() {
    return distinctBy("slug");
  }

  CindelPropertyQuery<Category, String> slugProperty() {
    return property<String>("slug");
  }

  CindelQuery<Category> sortByName({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return sortBy("name", order: order);
  }

  CindelQuery<Category> sortByNameDesc() {
    return sortBy("name", order: CindelSortOrder.descending);
  }

  CindelQuery<Category> thenByName({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return thenBy("name", order: order);
  }

  CindelQuery<Category> thenByNameDesc() {
    return thenBy("name", order: CindelSortOrder.descending);
  }

  CindelQuery<Category> distinctByName() {
    return distinctBy("name");
  }

  CindelPropertyQuery<Category, String> nameProperty() {
    return property<String>("name");
  }

  CindelQuery<Category> sortBySortOrder({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return sortBy("sortOrder", order: order);
  }

  CindelQuery<Category> sortBySortOrderDesc() {
    return sortBy("sortOrder", order: CindelSortOrder.descending);
  }

  CindelQuery<Category> thenBySortOrder({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return thenBy("sortOrder", order: order);
  }

  CindelQuery<Category> thenBySortOrderDesc() {
    return thenBy("sortOrder", order: CindelSortOrder.descending);
  }

  CindelQuery<Category> distinctBySortOrder() {
    return distinctBy("sortOrder");
  }

  CindelPropertyQuery<Category, int> sortOrderProperty() {
    return property<int>("sortOrder");
  }
}

final class CategoryQueryFilter {
  const CategoryQueryFilter(this._query);

  final CindelQuery<Category> _query;

  CindelQuery<Category> dbIdEqualTo(int value) {
    return _query.whereMatches(CindelFilter.field("dbId").equalTo(value));
  }

  CindelQuery<Category> dbIdGreaterThan(int value) {
    return _query.whereMatches(CindelFilter.field("dbId").greaterThan(value));
  }

  CindelQuery<Category> dbIdGreaterThanOrEqualTo(int value) {
    return _query.whereMatches(
      CindelFilter.field("dbId").greaterThanOrEqualTo(value),
    );
  }

  CindelQuery<Category> dbIdLessThan(int value) {
    return _query.whereMatches(CindelFilter.field("dbId").lessThan(value));
  }

  CindelQuery<Category> dbIdLessThanOrEqualTo(int value) {
    return _query.whereMatches(
      CindelFilter.field("dbId").lessThanOrEqualTo(value),
    );
  }

  CindelQuery<Category> dbIdBetween(int? lower, int? upper) {
    return _query.whereMatches(
      CindelFilter.field("dbId").between(lower, upper),
    );
  }

  CindelQuery<Category> slugEqualTo(String value) {
    return _query.whereMatches(CindelFilter.field("slug").equalTo(value));
  }

  CindelQuery<Category> slugContains(String value) {
    return _query.whereMatches(CindelFilter.field("slug").contains(value));
  }

  CindelQuery<Category> slugStartsWith(String value) {
    return _query.whereMatches(CindelFilter.field("slug").startsWith(value));
  }

  CindelQuery<Category> slugEndsWith(String value) {
    return _query.whereMatches(CindelFilter.field("slug").endsWith(value));
  }

  CindelQuery<Category> nameEqualTo(String value) {
    return _query.whereMatches(CindelFilter.field("name").equalTo(value));
  }

  CindelQuery<Category> nameContains(String value) {
    return _query.whereMatches(CindelFilter.field("name").contains(value));
  }

  CindelQuery<Category> nameStartsWith(String value) {
    return _query.whereMatches(CindelFilter.field("name").startsWith(value));
  }

  CindelQuery<Category> nameEndsWith(String value) {
    return _query.whereMatches(CindelFilter.field("name").endsWith(value));
  }

  CindelQuery<Category> sortOrderEqualTo(int value) {
    return _query.whereMatches(CindelFilter.field("sortOrder").equalTo(value));
  }

  CindelQuery<Category> sortOrderGreaterThan(int value) {
    return _query.whereMatches(
      CindelFilter.field("sortOrder").greaterThan(value),
    );
  }

  CindelQuery<Category> sortOrderGreaterThanOrEqualTo(int value) {
    return _query.whereMatches(
      CindelFilter.field("sortOrder").greaterThanOrEqualTo(value),
    );
  }

  CindelQuery<Category> sortOrderLessThan(int value) {
    return _query.whereMatches(CindelFilter.field("sortOrder").lessThan(value));
  }

  CindelQuery<Category> sortOrderLessThanOrEqualTo(int value) {
    return _query.whereMatches(
      CindelFilter.field("sortOrder").lessThanOrEqualTo(value),
    );
  }

  CindelQuery<Category> sortOrderBetween(int? lower, int? upper) {
    return _query.whereMatches(
      CindelFilter.field("sortOrder").between(lower, upper),
    );
  }

  CindelQuery<Category> optional(
    bool enabled,
    CindelQuery<Category> Function(CategoryQueryFilter q) option,
  ) {
    return _query.optional(
      enabled,
      (query) => option(CategoryQueryFilter(query)),
    );
  }

  CindelQuery<Category> anyOf<E>(
    Iterable<E> items,
    CindelQuery<Category> Function(CategoryQueryFilter q, E item) option,
  ) {
    return _query.anyOf(
      items,
      (query, item) => option(CategoryQueryFilter(query), item),
    );
  }

  CindelQuery<Category> allOf<E>(
    Iterable<E> items,
    CindelQuery<Category> Function(CategoryQueryFilter q, E item) option,
  ) {
    return _query.allOf(
      items,
      (query, item) => option(CategoryQueryFilter(query), item),
    );
  }
}

final class CategoryQueryWhere {
  const CategoryQueryWhere(this._collection);

  final CindelTypedCollection<Category> _collection;

  CindelQuery<Category> slugEqualTo(String value) {
    return CindelQuery.equal(
      database: _collection.database,
      schema: CategorySchema,
      field: "slug",
      value: value,
    );
  }

  CindelQuery<Category> slugStartsWith(String prefix) {
    return CindelQuery.stringStartsWith(
      database: _collection.database,
      schema: CategorySchema,
      field: "slug",
      prefix: prefix,
    );
  }

  CindelQuery<Category> slugBetween(String? lower, String? upper) {
    return CindelQuery.range(
      database: _collection.database,
      schema: CategorySchema,
      field: "slug",
      lower: lower,
      upper: upper,
    );
  }
}

Map<String, Object?> _$CategoryToCindelDocument(Category object) {
  return <String, Object?>{
    "slug": object.slug,
    "name": object.name,
    "sortOrder": object.sortOrder,
  };
}

Category _$CategoryFromCindelDocument(Map<String, Object?> document) {
  final object = Category();
  object.dbId = document["dbId"] as int;
  object.slug = document["slug"] as String;
  object.name = document["name"] as String;
  object.sortOrder = document["sortOrder"] as int;
  return object;
}

CindelBinaryDocumentBytes _$CategoryToCindelBinaryDocument(Category object) {
  return cindelEncodeSchemaBinaryDocument(
    <Object?>[object.name, object.slug, object.sortOrder],
    const <CindelBinaryFieldType>[
      CindelBinaryFieldType.stringValue,
      CindelBinaryFieldType.stringValue,
      CindelBinaryFieldType.intValue,
    ],
  );
}

Category _$CategoryFromCindelBinaryDocument(CindelBinaryDocumentBytes bytes) {
  final reader = CindelSchemaBinaryDocumentReader(bytes, staticSize: 14);
  final Object? field0 = reader.readString(0, 0);
  final Object? field1 = reader.readString(1, 3);
  final Object? field2 = reader.readInt(2, 6);
  final object = Category();
  object.dbId = autoIncrement;
  object.slug = field1 as String;
  object.name = field0 as String;
  object.sortOrder = field2 as int;
  return object;
}

void _$CategoryWriteCindelNativeDocument(
  CindelNativeDocumentWriter writer,
  Category object,
) {
  writer.writeString(0, object.name);
  writer.writeString(1, object.slug);
  writer.writeInt(2, object.sortOrder);
}

Category _$CategoryReadCindelNativeDocument(
  CindelNativeDocumentReader reader,
  int documentIndex,
) {
  final object = Category();
  object.dbId = reader.readId(documentIndex);
  object.slug = reader.readString(documentIndex, 1) as String;
  object.name = reader.readString(documentIndex, 0) as String;
  object.sortOrder = reader.readInt(documentIndex, 2) as int;
  return object;
}

int _$CategoryGetCindelId(Category object) {
  return object.dbId;
}

void _$CategorySetCindelId(Category object, int id) {
  object.dbId = id;
}
