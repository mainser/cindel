import '../entities/todo.dart';
import '../repositories/todo_repository.dart';

final class ToggleTodo {
  const ToggleTodo(this._repository);

  final TodoRepository _repository;

  Future<void> call(Todo todo) {
    return _repository.save(todo.copyWith(completed: !todo.completed));
  }
}
