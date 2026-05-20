import '../repositories/todo_repository.dart';

final class DeleteTodo {
  const DeleteTodo(this._repository);

  final TodoRepository _repository;

  Future<void> call(int id) {
    return _repository.delete(id);
  }
}
