import '../repositories/todo_repository.dart';

final class ReadTodoSchemaVersion {
  const ReadTodoSchemaVersion(this._repository);

  final TodoRepository _repository;

  Future<int> call() {
    return _repository.readSchemaVersion();
  }
}
