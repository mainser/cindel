import '../entities/todo.dart';
import '../repositories/todo_repository.dart';

final class WatchTodos {
  const WatchTodos(this._repository);

  final TodoRepository _repository;

  Stream<List<Todo>> call() {
    return _repository.watchTodos();
  }
}
