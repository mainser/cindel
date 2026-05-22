import '../entities/todo.dart';
import '../repositories/todo_repository.dart';

final class SearchTodosByTitlePrefix {
  const SearchTodosByTitlePrefix(this._repository);

  final TodoRepository _repository;

  Future<List<Todo>> call(String rawPrefix) {
    final prefix = rawPrefix.trim();
    if (prefix.isEmpty) {
      return Future.value(const []);
    }
    return _repository.searchByTitlePrefix(prefix);
  }
}
