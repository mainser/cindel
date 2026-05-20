import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../di/todos_di.dart';
import '../../domain/entities/todo.dart';

part 'todos_providers.g.dart';

@riverpod
Stream<List<Todo>> todoList(Ref ref) {
  return ref.watch(watchTodosUseCaseProvider).call();
}

@riverpod
Future<int> todoSchemaVersion(Ref ref) {
  return ref.watch(readTodoSchemaVersionUseCaseProvider).call();
}

@riverpod
class TodoMutationController extends _$TodoMutationController {
  @override
  FutureOr<void> build() {}

  Future<void> add(String title) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(addTodoUseCaseProvider).call(title),
    );
  }

  Future<void> toggle(Todo todo) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(toggleTodoUseCaseProvider).call(todo),
    );
  }

  Future<void> delete(int id) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(deleteTodoUseCaseProvider).call(id),
    );
  }
}

@riverpod
class TodoSearchController extends _$TodoSearchController {
  @override
  FutureOr<List<Todo>> build() {
    return const [];
  }

  Future<void> searchExact(String title) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(searchTodosByTitleUseCaseProvider).call(title),
    );
  }

  Future<void> searchPrefix(String prefix) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(searchTodosByTitlePrefixUseCaseProvider).call(prefix),
    );
  }

  void clear() {
    state = const AsyncData([]);
  }
}
