import '../../domain/entities/todo.dart';
import '../../domain/failures/todo_failure.dart';
import '../../domain/repositories/todo_repository.dart';
import '../datasources/todos_local_data_source.dart';
import '../models/todo_model.dart';

final class CindelTodoRepository implements TodoRepository {
  const CindelTodoRepository(this._dataSource);

  final TodosLocalDataSource _dataSource;

  @override
  Stream<List<Todo>> watchTodos() {
    return _dataSource.watchTodos().map(_toDomainList).handleError((error) {
      throw TodoStorageFailure.from(error);
    });
  }

  @override
  Future<void> save(Todo todo) async {
    try {
      await _dataSource.save(TodoModel.fromDomain(todo));
    } catch (error) {
      throw TodoStorageFailure.from(error);
    }
  }

  @override
  Future<void> delete(int id) async {
    try {
      await _dataSource.delete(id);
    } catch (error) {
      throw TodoStorageFailure.from(error);
    }
  }

  @override
  Future<List<Todo>> searchByExactTitle(String title) async {
    try {
      return _toDomainList(await _dataSource.searchByExactTitle(title));
    } catch (error) {
      throw TodoStorageFailure.from(error);
    }
  }

  @override
  Future<List<Todo>> searchByTitlePrefix(String prefix) async {
    try {
      return _toDomainList(await _dataSource.searchByTitlePrefix(prefix));
    } catch (error) {
      throw TodoStorageFailure.from(error);
    }
  }

  @override
  Future<int> readSchemaVersion() async {
    try {
      return _dataSource.readSchemaVersion();
    } catch (error) {
      throw TodoStorageFailure.from(error);
    }
  }
}

List<Todo> _toDomainList(List<TodoModel> models) {
  return models.map((model) => model.toDomain()).toList(growable: false);
}
