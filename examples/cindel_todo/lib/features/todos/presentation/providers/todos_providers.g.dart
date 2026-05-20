// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'todos_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(todoList)
final todoListProvider = TodoListProvider._();

final class TodoListProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<Todo>>,
          List<Todo>,
          Stream<List<Todo>>
        >
    with $FutureModifier<List<Todo>>, $StreamProvider<List<Todo>> {
  TodoListProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'todoListProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$todoListHash();

  @$internal
  @override
  $StreamProviderElement<List<Todo>> $createElement($ProviderPointer pointer) =>
      $StreamProviderElement(pointer);

  @override
  Stream<List<Todo>> create(Ref ref) {
    return todoList(ref);
  }
}

String _$todoListHash() => r'b5a7b28d469b5b7ba2906aab5e17fb07f3fc3692';

@ProviderFor(todoSchemaVersion)
final todoSchemaVersionProvider = TodoSchemaVersionProvider._();

final class TodoSchemaVersionProvider
    extends $FunctionalProvider<AsyncValue<int>, int, FutureOr<int>>
    with $FutureModifier<int>, $FutureProvider<int> {
  TodoSchemaVersionProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'todoSchemaVersionProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$todoSchemaVersionHash();

  @$internal
  @override
  $FutureProviderElement<int> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<int> create(Ref ref) {
    return todoSchemaVersion(ref);
  }
}

String _$todoSchemaVersionHash() => r'616226b7ec242b52b3fea6075e7433641dd0a516';

@ProviderFor(TodoMutationController)
final todoMutationControllerProvider = TodoMutationControllerProvider._();

final class TodoMutationControllerProvider
    extends $AsyncNotifierProvider<TodoMutationController, void> {
  TodoMutationControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'todoMutationControllerProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$todoMutationControllerHash();

  @$internal
  @override
  TodoMutationController create() => TodoMutationController();
}

String _$todoMutationControllerHash() =>
    r'e4afe0aca8518dcdaa477b81eab982fb6925d567';

abstract class _$TodoMutationController extends $AsyncNotifier<void> {
  FutureOr<void> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<AsyncValue<void>, void>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<void>, void>,
              AsyncValue<void>,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}

@ProviderFor(TodoSearchController)
final todoSearchControllerProvider = TodoSearchControllerProvider._();

final class TodoSearchControllerProvider
    extends $AsyncNotifierProvider<TodoSearchController, List<Todo>> {
  TodoSearchControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'todoSearchControllerProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$todoSearchControllerHash();

  @$internal
  @override
  TodoSearchController create() => TodoSearchController();
}

String _$todoSearchControllerHash() =>
    r'85ff5015bc27fcf706cf2d798b1a78d24d47b43e';

abstract class _$TodoSearchController extends $AsyncNotifier<List<Todo>> {
  FutureOr<List<Todo>> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<AsyncValue<List<Todo>>, List<Todo>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<List<Todo>>, List<Todo>>,
              AsyncValue<List<Todo>>,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
