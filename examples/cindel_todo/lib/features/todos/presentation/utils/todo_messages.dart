import '../../domain/failures/todo_failure.dart';

String todoErrorMessage(Object error) {
  if (error is TodoFailure) {
    return error.message;
  }
  return 'Something went wrong: $error';
}
