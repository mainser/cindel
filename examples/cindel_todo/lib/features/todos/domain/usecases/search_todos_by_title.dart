import '../entities/todo.dart';
import '../repositories/todo_repository.dart';

final class SearchTodosByTitle {
  const SearchTodosByTitle(this._repository);

  final TodoRepository _repository;

  Future<List<Todo>> call(String rawTitle) {
    final title = rawTitle.trim();
    if (title.isEmpty) {
      return Future.value(const []);
    }
    return _repository.searchByExactTitle(title);
  }
}
