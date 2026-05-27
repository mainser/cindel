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
      binaryType: "int",
      isId: true,
      isIndexed: false,
      isIndexUnique: false,
      indexCaseSensitive: true,
      indexType: CindelIndexType.value,
    ),
    CindelFieldSchema(
      name: "title",
      dartType: "String",
      binaryType: "string",
      isId: false,
      isIndexed: true,
      isIndexUnique: false,
      indexCaseSensitive: true,
      indexType: CindelIndexType.value,
    ),
    CindelFieldSchema(
      name: "titleWords",
      dartType: "String",
      binaryType: "string",
      isId: false,
      isIndexed: true,
      isIndexUnique: false,
      indexCaseSensitive: false,
      indexType: CindelIndexType.words,
    ),
    CindelFieldSchema(
      name: "completed",
      dartType: "bool",
      binaryType: "bool",
      isId: false,
      isIndexed: false,
      isIndexUnique: false,
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
      indexCaseSensitive: true,
      indexType: CindelIndexType.value,
    ),
  ],
  compositeIndexes: <CindelCompositeIndexSchema>[],
  toDocument: _$TodoModelToCindelDocument,
  fromDocument: _$TodoModelFromCindelDocument,
  toBinaryDocument: _$TodoModelToCindelBinaryDocument,
  fromBinaryDocument: _$TodoModelFromCindelBinaryDocument,
  writeNativeDocument: _$TodoModelWriteCindelNativeDocument,
  readNativeDocument: _$TodoModelReadCindelNativeDocument,
  getId: _$TodoModelGetCindelId,
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

  CindelQuery<TodoModel> sortByTitleWords({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return sortBy("titleWords", order: order);
  }

  CindelQuery<TodoModel> sortByTitleWordsDesc() {
    return sortBy("titleWords", order: CindelSortOrder.descending);
  }

  CindelQuery<TodoModel> thenByTitleWords({
    CindelSortOrder order = CindelSortOrder.ascending,
  }) {
    return thenBy("titleWords", order: order);
  }

  CindelQuery<TodoModel> thenByTitleWordsDesc() {
    return thenBy("titleWords", order: CindelSortOrder.descending);
  }

  CindelQuery<TodoModel> distinctByTitleWords() {
    return distinctBy("titleWords");
  }

  CindelPropertyQuery<TodoModel, String> titleWordsProperty() {
    return property<String>("titleWords");
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

  CindelQuery<TodoModel> titleWordsEqualTo(String word) {
    return titleWordsWordEqualTo(word);
  }

  CindelQuery<TodoModel> titleWordsStartsWith(String prefix) {
    return titleWordsWordStartsWith(prefix);
  }

  CindelQuery<TodoModel> titleWordsWordEqualTo(String word) {
    return CindelQuery.wordsContain(
      database: _collection.database,
      schema: TodoModelSchema,
      field: "titleWords",
      word: word,
    );
  }

  CindelQuery<TodoModel> titleWordsWordStartsWith(String prefix) {
    return CindelQuery.wordsStartWith(
      database: _collection.database,
      schema: TodoModelSchema,
      field: "titleWords",
      prefix: prefix,
    );
  }

  CindelQuery<TodoModel> titleWordsWordsContain(String word) {
    return titleWordsWordEqualTo(word);
  }

  CindelQuery<TodoModel> titleWordsWordsStartWith(String prefix) {
    return titleWordsWordStartsWith(prefix);
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

  CindelQuery<TodoModel> titleWordsEqualTo(String value) {
    return _query.whereMatches(CindelFilter.field("titleWords").equalTo(value));
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
    "title": object.title,
    "titleWords": object.titleWords,
    "completed": object.completed,
    "createdAtMicros": object.createdAtMicros,
  };
}

TodoModel _$TodoModelFromCindelDocument(Map<String, Object?> document) {
  final object = TodoModel();
  object.id = document["id"] as int;
  object.title = document["title"] as String;
  object.titleWords = document["titleWords"] as String;
  object.completed = document["completed"] as bool;
  object.createdAtMicros = document["createdAtMicros"] as int;
  return object;
}

CindelBinaryDocumentBytes _$TodoModelToCindelBinaryDocument(TodoModel object) {
  return cindelEncodeSchemaBinaryDocument(
    <Object?>[
      object.completed,
      object.createdAtMicros,
      object.id,
      object.title,
      object.titleWords,
    ],
    const <CindelBinaryFieldType>[
      CindelBinaryFieldType.boolValue,
      CindelBinaryFieldType.intValue,
      CindelBinaryFieldType.intValue,
      CindelBinaryFieldType.stringValue,
      CindelBinaryFieldType.stringValue,
    ],
  );
}

TodoModel _$TodoModelFromCindelBinaryDocument(CindelBinaryDocumentBytes bytes) {
  final reader = CindelSchemaBinaryDocumentReader(bytes, staticSize: 23);
  final Object? field0 = reader.readBool(0, 0);
  final Object? field1 = reader.readInt(1, 1);
  final Object? field2 = reader.readInt(2, 9);
  final Object? field3 = reader.readString(3, 17);
  final Object? field4 = reader.readString(4, 20);
  final object = TodoModel();
  object.id = field2 as int;
  object.title = field3 as String;
  object.titleWords = field4 as String;
  object.completed = field0 as bool;
  object.createdAtMicros = field1 as int;
  return object;
}

void _$TodoModelWriteCindelNativeDocument(
  CindelNativeDocumentWriter writer,
  TodoModel object,
) {
  writer.writeBool(0, object.completed);
  writer.writeInt(1, object.createdAtMicros);
  writer.writeInt(2, object.id);
  writer.writeString(3, object.title);
  writer.writeString(4, object.titleWords);
}

TodoModel _$TodoModelReadCindelNativeDocument(
  CindelNativeDocumentReader reader,
  int documentIndex,
) {
  final object = TodoModel();
  object.id = reader.readInt(documentIndex, 2) as int;
  object.title = reader.readString(documentIndex, 3) as String;
  object.titleWords = reader.readString(documentIndex, 4) as String;
  object.completed = reader.readBool(documentIndex, 0) as bool;
  object.createdAtMicros = reader.readInt(documentIndex, 1) as int;
  return object;
}

int _$TodoModelGetCindelId(TodoModel object) {
  return object.id;
}

void _$TodoModelSetCindelId(TodoModel object, int id) {
  object.id = id;
}
