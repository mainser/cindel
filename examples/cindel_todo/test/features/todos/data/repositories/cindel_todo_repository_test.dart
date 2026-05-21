import 'package:cindel/cindel.dart';
import 'package:cindel_todo/features/todos/data/datasources/todos_local_data_source.dart';
import 'package:cindel_todo/features/todos/data/models/todo_model.dart';
import 'package:cindel_todo/features/todos/data/repositories/cindel_todo_repository.dart';
import 'package:cindel_todo/features/todos/domain/entities/todo.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CindelTodoRepository', () {
    // Scenario: The repository saves todos and streams the collection.
    // Covers:
    // - [CindelTodoRepository.save] mapping domain values to generated models.
    // - [TodosLocalDataSource.watchTodos] reading typed collection snapshots.
    // - In-memory Cindel watcher updates after committed writes.
    // Expected: Watchers emit an empty list and then saved todos sorted newest first.
    test('saves and watches todos through Cindel in memory.', () async {
      // Arrange.
      final database = await _openDatabase();
      addTearDown(database.close);
      final repository = _repository(database);
      final events = <List<Todo>>[];
      final subscription = repository.watchTodos().listen(events.add);
      addTearDown(subscription.cancel);
      final first = _todo(id: 1, title: 'First');
      final second = _todo(id: 2, title: 'Second');

      // Act.
      await _waitUntil(() => events.length == 1);
      await repository.save(first);
      await _waitUntil(() => events.any((todos) => todos.length == 1));
      await repository.save(second);
      await _waitUntil(() => events.any((todos) => todos.length == 2));

      // Assert.
      expect(events.first, isEmpty);
      final latest = events.lastWhere((todos) => todos.length == 2);
      expect(latest.map((todo) => todo.title), ['Second', 'First']);
    });

    // Scenario: The repository searches the indexed title field.
    // Covers:
    // - Exact title query through Cindel's indexed equality path.
    // - Token-prefix title query through Cindel's word index path.
    // - Domain mapping after query results.
    // Expected: Exact and prefix searches return only matching todos.
    test(
      'searches exact titles and word prefixes through indexed queries.',
      () async {
        // Arrange.
        final database = await _openDatabase(
          seed: [
            _todo(id: 1, title: 'Alpha release'),
            _todo(id: 2, title: 'Alpine build'),
            _todo(id: 3, title: 'Beta docs'),
          ],
        );
        addTearDown(database.close);
        final repository = _repository(database);

        // Act.
        final exactMatches = await repository.searchByExactTitle(
          'Alpha release',
        );
        final prefixMatches = await repository.searchByTitlePrefix('rel');

        // Assert.
        expect(exactMatches.map((todo) => todo.title), ['Alpha release']);
        expect(prefixMatches.map((todo) => todo.title), ['Alpha release']);
      },
    );

    // Scenario: A todo is updated and then deleted.
    // Covers:
    // - Repository update path for an existing Cindel id.
    // - Repository delete path removing the typed collection object.
    // - Query index cleanup after delete.
    // Expected: Updated state is visible and deleted todos disappear from search.
    test('updates and deletes todos through Cindel in memory.', () async {
      // Arrange.
      final database = await _openDatabase(
        seed: [_todo(id: 1, title: 'Draft', completed: false)],
      );
      addTearDown(database.close);
      final repository = _repository(database);

      // Act.
      await repository.save(_todo(id: 1, title: 'Draft', completed: true));
      final updatedMatches = await repository.searchByExactTitle('Draft');
      await repository.delete(1);
      final deletedMatches = await repository.searchByExactTitle('Draft');

      // Assert.
      expect(updatedMatches.single.completed, isTrue);
      expect(deletedMatches, isEmpty);
    });

    // Scenario: The repository reads schema metadata from the in-memory database.
    // Covers:
    // - [Cindel.openInMemory] schema registration for the Todo model.
    // - [CindelTodoRepository.readSchemaVersion] data source pass-through.
    // Expected: The Todo collection starts at schema version 1.
    test('reads the registered Todo schema version.', () async {
      // Arrange.
      final database = await _openDatabase();
      addTearDown(database.close);
      final repository = _repository(database);

      // Act.
      final version = await repository.readSchemaVersion();

      // Assert.
      expect(version, 1);
    });
  });
}

Future<CindelDatabase> _openDatabase({Iterable<Todo> seed = const []}) async {
  final database = await Cindel.openInMemory(schemas: [TodoModelSchema]);
  for (final todo in seed) {
    await database.todos.put(TodoModel.fromDomain(todo));
  }
  return database;
}

CindelTodoRepository _repository(CindelDatabase database) {
  return CindelTodoRepository(TodosLocalDataSource(Future.value(database)));
}

Todo _todo({required int id, required String title, bool completed = false}) {
  return Todo(
    id: id,
    title: title,
    completed: completed,
    createdAt: DateTime.fromMicrosecondsSinceEpoch(id),
  );
}

Future<void> _waitUntil(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 2),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TestFailure('Timed out waiting for repository event.');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}
