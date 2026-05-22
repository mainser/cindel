sealed class TodoFailure implements Exception {
  const TodoFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

final class TodoValidationFailure extends TodoFailure {
  const TodoValidationFailure.emptyTitle() : super('Enter a todo title.');
}

final class TodoStorageFailure extends TodoFailure {
  const TodoStorageFailure(super.message);

  factory TodoStorageFailure.from(Object error) {
    if (error is TodoFailure) {
      return TodoStorageFailure(error.message);
    }
    return TodoStorageFailure('Cindel storage operation failed: $error');
  }
}
