import 'dart:io';

import 'package:cindel/cindel.dart';
import 'package:path_provider/path_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../data/datasources/todos_local_data_source.dart';
import '../data/models/todo_model.dart';
import '../data/repositories/cindel_todo_repository.dart';
import '../domain/repositories/todo_repository.dart';
import '../domain/usecases/add_todo.dart';
import '../domain/usecases/delete_todo.dart';
import '../domain/usecases/read_todo_schema_version.dart';
import '../domain/usecases/search_todos_by_title.dart';
import '../domain/usecases/search_todos_by_title_prefix.dart';
import '../domain/usecases/toggle_todo.dart';
import '../domain/usecases/watch_todos.dart';

part 'todos_di.g.dart';

@riverpod
Future<CindelDatabase> todoDatabase(Ref ref) async {
  final supportDirectory = await getApplicationSupportDirectory();
  final databaseDirectory = Directory(
    '${supportDirectory.path}${Platform.pathSeparator}cindel_todo',
  );
  final database = await Cindel.open(
    directory: databaseDirectory.path,
    schemas: [TodoModelSchema],
  );
  ref.onDispose(database.close);
  return database;
}

@riverpod
TodosLocalDataSource todosLocalDataSource(Ref ref) {
  return TodosLocalDataSource(ref.watch(todoDatabaseProvider.future));
}

@riverpod
TodoRepository todoRepository(Ref ref) {
  return CindelTodoRepository(ref.watch(todosLocalDataSourceProvider));
}

@riverpod
AddTodo addTodoUseCase(Ref ref) {
  return AddTodo(ref.watch(todoRepositoryProvider));
}

@riverpod
DeleteTodo deleteTodoUseCase(Ref ref) {
  return DeleteTodo(ref.watch(todoRepositoryProvider));
}

@riverpod
ToggleTodo toggleTodoUseCase(Ref ref) {
  return ToggleTodo(ref.watch(todoRepositoryProvider));
}

@riverpod
WatchTodos watchTodosUseCase(Ref ref) {
  return WatchTodos(ref.watch(todoRepositoryProvider));
}

@riverpod
SearchTodosByTitle searchTodosByTitleUseCase(Ref ref) {
  return SearchTodosByTitle(ref.watch(todoRepositoryProvider));
}

@riverpod
SearchTodosByTitlePrefix searchTodosByTitlePrefixUseCase(Ref ref) {
  return SearchTodosByTitlePrefix(ref.watch(todoRepositoryProvider));
}

@riverpod
ReadTodoSchemaVersion readTodoSchemaVersionUseCase(Ref ref) {
  return ReadTodoSchemaVersion(ref.watch(todoRepositoryProvider));
}
