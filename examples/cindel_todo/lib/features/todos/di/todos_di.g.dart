// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'todos_di.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(todoDatabase)
final todoDatabaseProvider = TodoDatabaseProvider._();

final class TodoDatabaseProvider
    extends
        $FunctionalProvider<
          AsyncValue<CindelDatabase>,
          CindelDatabase,
          FutureOr<CindelDatabase>
        >
    with $FutureModifier<CindelDatabase>, $FutureProvider<CindelDatabase> {
  TodoDatabaseProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'todoDatabaseProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$todoDatabaseHash();

  @$internal
  @override
  $FutureProviderElement<CindelDatabase> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<CindelDatabase> create(Ref ref) {
    return todoDatabase(ref);
  }
}

String _$todoDatabaseHash() => r'09bed84a6457407593f3276c907d28c82c10ee4b';

@ProviderFor(todosLocalDataSource)
final todosLocalDataSourceProvider = TodosLocalDataSourceProvider._();

final class TodosLocalDataSourceProvider
    extends
        $FunctionalProvider<
          TodosLocalDataSource,
          TodosLocalDataSource,
          TodosLocalDataSource
        >
    with $Provider<TodosLocalDataSource> {
  TodosLocalDataSourceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'todosLocalDataSourceProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$todosLocalDataSourceHash();

  @$internal
  @override
  $ProviderElement<TodosLocalDataSource> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  TodosLocalDataSource create(Ref ref) {
    return todosLocalDataSource(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(TodosLocalDataSource value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<TodosLocalDataSource>(value),
    );
  }
}

String _$todosLocalDataSourceHash() =>
    r'a10c138bf9157c82f068a2d44ff937098848c4fd';

@ProviderFor(todoRepository)
final todoRepositoryProvider = TodoRepositoryProvider._();

final class TodoRepositoryProvider
    extends $FunctionalProvider<TodoRepository, TodoRepository, TodoRepository>
    with $Provider<TodoRepository> {
  TodoRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'todoRepositoryProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$todoRepositoryHash();

  @$internal
  @override
  $ProviderElement<TodoRepository> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  TodoRepository create(Ref ref) {
    return todoRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(TodoRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<TodoRepository>(value),
    );
  }
}

String _$todoRepositoryHash() => r'be34018d2272a10f46a294b27f83ea0eb9c3cbed';

@ProviderFor(addTodoUseCase)
final addTodoUseCaseProvider = AddTodoUseCaseProvider._();

final class AddTodoUseCaseProvider
    extends $FunctionalProvider<AddTodo, AddTodo, AddTodo>
    with $Provider<AddTodo> {
  AddTodoUseCaseProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'addTodoUseCaseProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$addTodoUseCaseHash();

  @$internal
  @override
  $ProviderElement<AddTodo> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  AddTodo create(Ref ref) {
    return addTodoUseCase(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AddTodo value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AddTodo>(value),
    );
  }
}

String _$addTodoUseCaseHash() => r'25a1ed4b76a87ec4b6bc4f3f734889a802c7a894';

@ProviderFor(deleteTodoUseCase)
final deleteTodoUseCaseProvider = DeleteTodoUseCaseProvider._();

final class DeleteTodoUseCaseProvider
    extends $FunctionalProvider<DeleteTodo, DeleteTodo, DeleteTodo>
    with $Provider<DeleteTodo> {
  DeleteTodoUseCaseProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'deleteTodoUseCaseProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$deleteTodoUseCaseHash();

  @$internal
  @override
  $ProviderElement<DeleteTodo> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  DeleteTodo create(Ref ref) {
    return deleteTodoUseCase(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(DeleteTodo value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<DeleteTodo>(value),
    );
  }
}

String _$deleteTodoUseCaseHash() => r'b1aec94e4f5fb418ccc7951a0b76583af60386e2';

@ProviderFor(toggleTodoUseCase)
final toggleTodoUseCaseProvider = ToggleTodoUseCaseProvider._();

final class ToggleTodoUseCaseProvider
    extends $FunctionalProvider<ToggleTodo, ToggleTodo, ToggleTodo>
    with $Provider<ToggleTodo> {
  ToggleTodoUseCaseProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'toggleTodoUseCaseProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$toggleTodoUseCaseHash();

  @$internal
  @override
  $ProviderElement<ToggleTodo> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  ToggleTodo create(Ref ref) {
    return toggleTodoUseCase(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ToggleTodo value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ToggleTodo>(value),
    );
  }
}

String _$toggleTodoUseCaseHash() => r'9cb386e2e4bf2a598a3118dfac2ca1255037fb27';

@ProviderFor(watchTodosUseCase)
final watchTodosUseCaseProvider = WatchTodosUseCaseProvider._();

final class WatchTodosUseCaseProvider
    extends $FunctionalProvider<WatchTodos, WatchTodos, WatchTodos>
    with $Provider<WatchTodos> {
  WatchTodosUseCaseProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'watchTodosUseCaseProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$watchTodosUseCaseHash();

  @$internal
  @override
  $ProviderElement<WatchTodos> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  WatchTodos create(Ref ref) {
    return watchTodosUseCase(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(WatchTodos value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<WatchTodos>(value),
    );
  }
}

String _$watchTodosUseCaseHash() => r'f36f8c49b2c73a0203ed3a661316c0b96b763363';

@ProviderFor(searchTodosByTitleUseCase)
final searchTodosByTitleUseCaseProvider = SearchTodosByTitleUseCaseProvider._();

final class SearchTodosByTitleUseCaseProvider
    extends
        $FunctionalProvider<
          SearchTodosByTitle,
          SearchTodosByTitle,
          SearchTodosByTitle
        >
    with $Provider<SearchTodosByTitle> {
  SearchTodosByTitleUseCaseProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'searchTodosByTitleUseCaseProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$searchTodosByTitleUseCaseHash();

  @$internal
  @override
  $ProviderElement<SearchTodosByTitle> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  SearchTodosByTitle create(Ref ref) {
    return searchTodosByTitleUseCase(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SearchTodosByTitle value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SearchTodosByTitle>(value),
    );
  }
}

String _$searchTodosByTitleUseCaseHash() =>
    r'8052107895100a8f5233c123e7a33ddb352039d3';

@ProviderFor(searchTodosByTitlePrefixUseCase)
final searchTodosByTitlePrefixUseCaseProvider =
    SearchTodosByTitlePrefixUseCaseProvider._();

final class SearchTodosByTitlePrefixUseCaseProvider
    extends
        $FunctionalProvider<
          SearchTodosByTitlePrefix,
          SearchTodosByTitlePrefix,
          SearchTodosByTitlePrefix
        >
    with $Provider<SearchTodosByTitlePrefix> {
  SearchTodosByTitlePrefixUseCaseProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'searchTodosByTitlePrefixUseCaseProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$searchTodosByTitlePrefixUseCaseHash();

  @$internal
  @override
  $ProviderElement<SearchTodosByTitlePrefix> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  SearchTodosByTitlePrefix create(Ref ref) {
    return searchTodosByTitlePrefixUseCase(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SearchTodosByTitlePrefix value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SearchTodosByTitlePrefix>(value),
    );
  }
}

String _$searchTodosByTitlePrefixUseCaseHash() =>
    r'15e2b9abfe09ee9a2d151ad875cf2919babc82a0';

@ProviderFor(readTodoSchemaVersionUseCase)
final readTodoSchemaVersionUseCaseProvider =
    ReadTodoSchemaVersionUseCaseProvider._();

final class ReadTodoSchemaVersionUseCaseProvider
    extends
        $FunctionalProvider<
          ReadTodoSchemaVersion,
          ReadTodoSchemaVersion,
          ReadTodoSchemaVersion
        >
    with $Provider<ReadTodoSchemaVersion> {
  ReadTodoSchemaVersionUseCaseProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'readTodoSchemaVersionUseCaseProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$readTodoSchemaVersionUseCaseHash();

  @$internal
  @override
  $ProviderElement<ReadTodoSchemaVersion> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  ReadTodoSchemaVersion create(Ref ref) {
    return readTodoSchemaVersionUseCase(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ReadTodoSchemaVersion value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ReadTodoSchemaVersion>(value),
    );
  }
}

String _$readTodoSchemaVersionUseCaseHash() =>
    r'bbf62f923f2740a700a50288a888c0246ca71ce5';
