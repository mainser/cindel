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
    ),
    CindelFieldSchema(
      name: "title",
      dartType: "String",
      isId: false,
      isIndexed: true,
    ),
    CindelFieldSchema(
      name: "completed",
      dartType: "bool",
      isId: false,
      isIndexed: false,
    ),
    CindelFieldSchema(
      name: "createdAtMicros",
      dartType: "int",
      isId: false,
      isIndexed: false,
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
