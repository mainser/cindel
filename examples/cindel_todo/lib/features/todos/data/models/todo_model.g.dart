// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'todo_model.dart';

// **************************************************************************
// CindelGenerator
// **************************************************************************

// ignore_for_file: non_constant_identifier_names

final TodoModelSchema = CindelCollectionSchema<TodoModel>(
  name: "todos",
  dartName: "TodoModel",
  idField: "id",
  fields: <CindelFieldSchema>[
    CindelFieldSchema(
      name: "id",
      dartType: "int",
      isId: true,
      isIndexed: false,
      isIndexUnique: false,
      indexCaseSensitive: true,
      indexType: CindelIndexType.value,
    ),
    CindelFieldSchema(
      name: "title",
      dartType: "String",
      isId: false,
      isIndexed: true,
      isIndexUnique: false,
      indexCaseSensitive: true,
      indexType: CindelIndexType.value,
    ),
    CindelFieldSchema(
      name: "completed",
      dartType: "bool",
      isId: false,
      isIndexed: false,
      isIndexUnique: false,
      indexCaseSensitive: true,
      indexType: CindelIndexType.value,
    ),
    CindelFieldSchema(
      name: "createdAtMicros",
      dartType: "int",
      isId: false,
      isIndexed: false,
      isIndexUnique: false,
      indexCaseSensitive: true,
      indexType: CindelIndexType.value,
    ),
  ],
  toDocument: _$TodoModelToCindelDocument,
  fromDocument: _$TodoModelFromCindelDocument,
  setId: _$TodoModelSetCindelId,
);

extension TodoModelCindelCollectionAccess on CindelDatabase {
  CindelTypedCollection<TodoModel> get todos =>
      typedCollection(TodoModelSchema);
}

extension TodoModelCindelQueryAccess on CindelTypedCollection<TodoModel> {
  TodoModelQueryWhere where() => TodoModelQueryWhere(this);

  TodoModelQueryFilter filter() => TodoModelQueryFilter(
    CindelQuery.all(database: database, schema: TodoModelSchema),
  );
}

extension TodoModelCindelQueryFilterAccess on CindelQuery<TodoModel> {
  TodoModelQueryFilter filter() => TodoModelQueryFilter(this);
}

extension TodoModelCindelQueryModifierAccess on CindelQuery<TodoModel> {
  CindelQuery<TodoModel> sortById({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return sortBy("id", order: order);
  }

  CindelQuery<TodoModel> sortByIdDesc() {
    return sortBy("id", order: CindelSortOrder.descending);
  }

  CindelQuery<TodoModel> thenById({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return thenBy("id", order: order);
  }

  CindelQuery<TodoModel> thenByIdDesc() {
    return thenBy("id", order: CindelSortOrder.descending);
  }

  CindelQuery<TodoModel> distinctById() {
    return distinctBy("id");
  }

  CindelPropertyQuery<TodoModel, int> idProperty() {
    return property<int>("id");
  }

  CindelQuery<TodoModel> sortByTitle({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return sortBy("title", order: order);
  }

  CindelQuery<TodoModel> sortByTitleDesc() {
    return sortBy("title", order: CindelSortOrder.descending);
  }

  CindelQuery<TodoModel> thenByTitle({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return thenBy("title", order: order);
  }

  CindelQuery<TodoModel> thenByTitleDesc() {
    return thenBy("title", order: CindelSortOrder.descending);
  }

  CindelQuery<TodoModel> distinctByTitle() {
    return distinctBy("title");
  }

  CindelPropertyQuery<TodoModel, String> titleProperty() {
    return property<String>("title");
  }

  CindelQuery<TodoModel> sortByCompleted({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return sortBy("completed", order: order);
  }

  CindelQuery<TodoModel> sortByCompletedDesc() {
    return sortBy("completed", order: CindelSortOrder.descending);
  }

  CindelQuery<TodoModel> thenByCompleted({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return thenBy("completed", order: order);
  }

  CindelQuery<TodoModel> thenByCompletedDesc() {
    return thenBy("completed", order: CindelSortOrder.descending);
  }

  CindelQuery<TodoModel> distinctByCompleted() {
    return distinctBy("completed");
  }

  CindelPropertyQuery<TodoModel, bool> completedProperty() {
    return property<bool>("completed");
  }

  CindelQuery<TodoModel> sortByCreatedAtMicros({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return sortBy("createdAtMicros", order: order);
  }

  CindelQuery<TodoModel> sortByCreatedAtMicrosDesc() {
    return sortBy("createdAtMicros", order: CindelSortOrder.descending);
  }

  CindelQuery<TodoModel> thenByCreatedAtMicros({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return thenBy("createdAtMicros", order: order);
  }

  CindelQuery<TodoModel> thenByCreatedAtMicrosDesc() {
    return thenBy("createdAtMicros", order: CindelSortOrder.descending);
  }

  CindelQuery<TodoModel> distinctByCreatedAtMicros() {
    return distinctBy("createdAtMicros");
  }

  CindelPropertyQuery<TodoModel, int> createdAtMicrosProperty() {
    return property<int>("createdAtMicros");
  }
}

final class TodoModelQueryWhere {
  const TodoModelQueryWhere(this._collection);

  final CindelTypedCollection<TodoModel> _collection;

  CindelQuery<TodoModel> titleEqualTo(String value) {
    return CindelQuery.equal(
      database: _collection.database,
      schema: TodoModelSchema,
      field: "title",
      value: value,
    );
  }

  CindelQuery<TodoModel> titleStartsWith(String prefix) {
    return CindelQuery.stringStartsWith(
      database: _collection.database,
      schema: TodoModelSchema,
      field: "title",
      prefix: prefix,
    );
  }

  CindelQuery<TodoModel> titleBetween(String? lower, String? upper) {
    return CindelQuery.range(
      database: _collection.database,
      schema: TodoModelSchema,
      field: "title",
      lower: lower,
      upper: upper,
    );
  }
}

final class TodoModelQueryFilter {
  const TodoModelQueryFilter(this._query);

  final CindelQuery<TodoModel> _query;

  CindelQuery<TodoModel> idEqualTo(int value) {
    return _query.whereMatches(CindelFilter.field("id").equalTo(value));
  }

  CindelQuery<TodoModel> idGreaterThan(int value) {
    return _query.whereMatches(CindelFilter.field("id").greaterThan(value));
  }

  CindelQuery<TodoModel> idGreaterThanOrEqualTo(int value) {
    return _query.whereMatches(
      CindelFilter.field("id").greaterThanOrEqualTo(value),
    );
  }

  CindelQuery<TodoModel> idLessThan(int value) {
    return _query.whereMatches(CindelFilter.field("id").lessThan(value));
  }

  CindelQuery<TodoModel> idLessThanOrEqualTo(int value) {
    return _query.whereMatches(
      CindelFilter.field("id").lessThanOrEqualTo(value),
    );
  }

  CindelQuery<TodoModel> idBetween(int? lower, int? upper) {
    return _query.whereMatches(CindelFilter.field("id").between(lower, upper));
  }

  CindelQuery<TodoModel> titleEqualTo(String value) {
    return _query.whereMatches(CindelFilter.field("title").equalTo(value));
  }

  CindelQuery<TodoModel> titleContains(String value) {
    return _query.whereMatches(CindelFilter.field("title").contains(value));
  }

  CindelQuery<TodoModel> titleStartsWith(String value) {
    return _query.whereMatches(CindelFilter.field("title").startsWith(value));
  }

  CindelQuery<TodoModel> titleEndsWith(String value) {
    return _query.whereMatches(CindelFilter.field("title").endsWith(value));
  }

  CindelQuery<TodoModel> completedEqualTo(bool value) {
    return _query.whereMatches(CindelFilter.field("completed").equalTo(value));
  }

  CindelQuery<TodoModel> createdAtMicrosEqualTo(int value) {
    return _query.whereMatches(
      CindelFilter.field("createdAtMicros").equalTo(value),
    );
  }

  CindelQuery<TodoModel> createdAtMicrosGreaterThan(int value) {
    return _query.whereMatches(
      CindelFilter.field("createdAtMicros").greaterThan(value),
    );
  }

  CindelQuery<TodoModel> createdAtMicrosGreaterThanOrEqualTo(int value) {
    return _query.whereMatches(
      CindelFilter.field("createdAtMicros").greaterThanOrEqualTo(value),
    );
  }

  CindelQuery<TodoModel> createdAtMicrosLessThan(int value) {
    return _query.whereMatches(
      CindelFilter.field("createdAtMicros").lessThan(value),
    );
  }

  CindelQuery<TodoModel> createdAtMicrosLessThanOrEqualTo(int value) {
    return _query.whereMatches(
      CindelFilter.field("createdAtMicros").lessThanOrEqualTo(value),
    );
  }

  CindelQuery<TodoModel> createdAtMicrosBetween(int? lower, int? upper) {
    return _query.whereMatches(
      CindelFilter.field("createdAtMicros").between(lower, upper),
    );
  }
}

Map<String, Object?> _$TodoModelToCindelDocument(TodoModel object) {
  return <String, Object?>{
    "id": object.id,
    "title": object.title,
    "completed": object.completed,
    "createdAtMicros": object.createdAtMicros,
  };
}

TodoModel _$TodoModelFromCindelDocument(Map<String, Object?> document) {
  final object = TodoModel();
  object.id = document["id"] as int;
  object.title = document["title"] as String;
  object.completed = document["completed"] as bool;
  object.createdAtMicros = document["createdAtMicros"] as int;
  return object;
}

void _$TodoModelSetCindelId(TodoModel object, int id) {
  object.id = id;
}
