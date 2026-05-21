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
