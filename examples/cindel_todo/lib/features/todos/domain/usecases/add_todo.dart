import 'package:cindel/cindel.dart';

import '../entities/todo.dart';
import '../failures/todo_failure.dart';
import '../repositories/todo_repository.dart';

final class AddTodo {
  const AddTodo(this._repository);

  final TodoRepository _repository;

  Future<void> call(String rawTitle) {
    final title = rawTitle.trim();
    if (title.isEmpty) {
      throw const TodoValidationFailure.emptyTitle();
    }

    final now = DateTime.now();
    return _repository.save(
      Todo(id: autoIncrement, title: title, completed: false, createdAt: now),
    );
  }
}
