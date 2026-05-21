import 'package:cindel/cindel.dart';
import 'package:cindel_todo/features/todos/data/datasources/todos_local_data_source.dart';
import 'package:cindel_todo/features/todos/data/models/todo_model.dart';
import 'package:cindel_todo/features/todos/data/repositories/cindel_todo_repository.dart';
import 'package:cindel_todo/features/todos/di/todos_di.dart';
import 'package:cindel_todo/features/todos/domain/entities/todo.dart';
import 'package:cindel_todo/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TodoListPage', () {
    // Scenario: A user adds, completes, and deletes a todo from the main list.
    // Covers:
    // - Todo editor submission through [TodoMutationController].
    // - Watcher-driven list updates after save and delete operations.
    // - Checkbox state after toggling an item.
    // Expected: The list reflects add, toggle, and delete actions.
    testWidgets('adds, toggles, and deletes todos.', (tester) async {
      // Arrange.
      final database = await _openTodoDatabase();
      addTearDown(database.close);
      await tester.pumpWidget(_buildApp(database));
      await tester.pumpAndSettle();

      // Act: add a todo.
      await tester.enterText(
        find.widgetWithText(TextField, 'New todo'),
        'Ship Stage 01',
      );
      await tester.tap(find.byTooltip('Add todo'));
      await tester.pumpAndSettle();

      // Assert: the new todo appears in the live list.
      expect(find.widgetWithText(ListTile, 'Ship Stage 01'), findsOneWidget);

      // Act: toggle the todo.
      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();

      // Assert: the checkbox reflects the completed state.
      final checkbox = tester.widget<Checkbox>(find.byType(Checkbox));
      expect(checkbox.value, isTrue);

      // Act: delete the todo.
      await tester.tap(find.byTooltip('Delete todo'));
      await tester.pumpAndSettle();

      // Assert: the list returns to its empty state.
      expect(find.widgetWithText(ListTile, 'Ship Stage 01'), findsNothing);
      expect(
        find.text('Add a todo to see Cindel persist it and stream it back.'),
        findsOneWidget,
      );
    });

    // Scenario: A user searches indexed title fields and clears the search.
    // Covers:
    // - Exact title search filtering the visible list.
    // - Token-prefix title search filtering the visible list.
    // - Clear search restoring the live collection.
    // Expected: The main list switches between search results and all todos.
    testWidgets(
      'filters the visible list by exact title and word prefix searches.',
      (tester) async {
        // Arrange.
        final database = await _openTodoDatabase(
          seed: [
            _todo(id: 1, title: 'Alpha release'),
            _todo(id: 2, title: 'Alpine build'),
            _todo(id: 3, title: 'Beta docs'),
          ],
        );
        addTearDown(database.close);
        await tester.pumpWidget(_buildApp(database));
        await tester.pumpAndSettle();

        // Assert: the live collection initially shows every todo.
        expect(find.text('Live collection'), findsOneWidget);
        expect(find.widgetWithText(ListTile, 'Alpha release'), findsOneWidget);
        expect(find.widgetWithText(ListTile, 'Alpine build'), findsOneWidget);
        expect(find.widgetWithText(ListTile, 'Beta docs'), findsOneWidget);

        // Act: run an exact title search.
        await tester.enterText(
          find.widgetWithText(TextField, 'Indexed title or word search'),
          'Alpha release',
        );
        await tester.tap(find.byTooltip('Search exact title'));
        await tester.pumpAndSettle();

        // Assert: only the exact match is visible in the main list.
        expect(find.text('Exact matches'), findsOneWidget);
        expect(find.widgetWithText(ListTile, 'Alpha release'), findsOneWidget);
        expect(find.widgetWithText(ListTile, 'Alpine build'), findsNothing);
        expect(find.widgetWithText(ListTile, 'Beta docs'), findsNothing);

        // Act: run a token-prefix title search.
        await tester.enterText(
          find.widgetWithText(TextField, 'Indexed title or word search'),
          'rel',
        );
        await tester.tap(find.byTooltip('Search title prefix'));
        await tester.pumpAndSettle();

        // Assert: token-prefix matches are visible and non-matches stay hidden.
        expect(find.text('Prefix matches'), findsOneWidget);
        expect(find.widgetWithText(ListTile, 'Alpha release'), findsOneWidget);
        expect(find.widgetWithText(ListTile, 'Alpine build'), findsNothing);
        expect(find.widgetWithText(ListTile, 'Beta docs'), findsNothing);

        // Act: clear the search.
        await tester.tap(find.byTooltip('Clear search'));
        await tester.pumpAndSettle();

        // Assert: the full live collection is visible again.
        expect(find.text('Live collection'), findsOneWidget);
        expect(find.widgetWithText(ListTile, 'Alpha release'), findsOneWidget);
        expect(find.widgetWithText(ListTile, 'Alpine build'), findsOneWidget);
        expect(find.widgetWithText(ListTile, 'Beta docs'), findsOneWidget);
      },
    );
  });
}

Future<CindelDatabase> _openTodoDatabase({
  Iterable<Todo> seed = const [],
}) async {
  final database = await Cindel.openInMemory(schemas: [TodoModelSchema]);
  for (final todo in seed) {
    await database.todos.put(TodoModel.fromDomain(todo));
  }
  return database;
}

Widget _buildApp(CindelDatabase database) {
  final repository = CindelTodoRepository(
    TodosLocalDataSource(Future.value(database)),
  );
  return ProviderScope(
    overrides: [todoRepositoryProvider.overrideWithValue(repository)],
    child: const CindelTodoApp(),
  );
}

Todo _todo({required int id, required String title, bool completed = false}) {
  return Todo(
    id: id,
    title: title,
    completed: completed,
    createdAt: DateTime.fromMicrosecondsSinceEpoch(id),
  );
}
