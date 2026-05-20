import '../entities/todo.dart';

abstract interface class TodoRepository {
  Stream<List<Todo>> watchTodos();

  Future<void> save(Todo todo);

  Future<void> delete(int id);

  Future<List<Todo>> searchByExactTitle(String title);

  Future<List<Todo>> searchByTitlePrefix(String prefix);

  Future<int> readSchemaVersion();
}
