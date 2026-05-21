import 'package:cindel/cindel.dart';

import '../models/todo_model.dart';

final class TodosLocalDataSource {
  const TodosLocalDataSource(this._database);

  final Future<CindelDatabase> _database;

  Future<void> save(TodoModel todo) async {
    final database = await _database;
    await database.todos.put(todo);
  }

  Future<void> delete(int id) async {
    final database = await _database;
    await database.todos.delete(id);
  }

  Stream<List<TodoModel>> watchTodos() async* {
    final database = await _database;
    yield* database.todos.watchCollection().map(_sortModels);
  }

  Future<List<TodoModel>> searchByExactTitle(String title) async {
    final database = await _database;
    final todos = await database.todos.where().titleEqualTo(title).findAll();
    return _sortModels(todos);
  }

  Future<List<TodoModel>> searchByTitlePrefix(String prefix) async {
    final database = await _database;
    final todos = await database.todos
        .where()
        .titleWordsStartsWith(prefix)
        .findAll();
    return _sortModels(todos);
  }

  Future<int> readSchemaVersion() async {
    final database = await _database;
    return await database.schemaVersion('todos') ?? 0;
  }
}

List<TodoModel> _sortModels(Iterable<TodoModel> models) {
  final sortedModels = models.toList(growable: false);
  return sortedModels..sort(
    (left, right) => right.createdAtMicros.compareTo(left.createdAtMicros),
  );
}
