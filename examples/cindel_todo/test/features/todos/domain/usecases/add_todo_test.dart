import 'package:cindel_todo/features/todos/domain/entities/todo.dart';
import 'package:cindel_todo/features/todos/domain/failures/todo_failure.dart';
import 'package:cindel_todo/features/todos/domain/repositories/todo_repository.dart';
import 'package:cindel_todo/features/todos/domain/usecases/add_todo.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AddTodo', () {
    // Scenario: A user submits a title with surrounding whitespace.
    // Covers:
    // - Business title normalization before persistence.
    // - New todo defaults for completed state.
    // Expected: The repository receives one normalized incomplete todo.
    test('saves a normalized todo.', () async {
      // Arrange.
      final repository = _FakeTodoRepository();
      final useCase = AddTodo(repository);

      // Act.
      await useCase('  Ship the example  ');

      // Assert.
      expect(repository.savedTodos, hasLength(1));
      expect(repository.savedTodos.single.title, 'Ship the example');
      expect(repository.savedTodos.single.completed, isFalse);
    });

    // Scenario: A user submits an empty title.
    // Covers:
    // - Validation before repository calls.
    // - Typed feature failures as the domain contract.
    // Expected: The usecase throws [TodoValidationFailure].
    test('rejects empty titles.', () async {
      // Arrange.
      final repository = _FakeTodoRepository();
      final useCase = AddTodo(repository);

      // Act.
      void result() => useCase('   ');

      // Assert.
      expect(result, throwsA(isA<TodoValidationFailure>()));
      expect(repository.savedTodos, isEmpty);
    });
  });
}

final class _FakeTodoRepository implements TodoRepository {
  final savedTodos = <Todo>[];

  @override
  Future<void> delete(int id) async {}

  @override
  Future<int> readSchemaVersion() async => 1;

  @override
  Future<void> save(Todo todo) async {
    savedTodos.add(todo);
  }

  @override
  Future<List<Todo>> searchByExactTitle(String title) async => const [];

  @override
  Future<List<Todo>> searchByTitlePrefix(String prefix) async => const [];

  @override
  Stream<List<Todo>> watchTodos() {
    return const Stream.empty();
  }
}
