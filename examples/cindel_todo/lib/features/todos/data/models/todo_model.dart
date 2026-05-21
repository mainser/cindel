import 'package:cindel/cindel.dart';

import '../../domain/entities/todo.dart';

part 'todo_model.g.dart';

@Collection(name: 'todos')
class TodoModel {
  TodoModel();

  Id id = autoIncrement;

  @index
  late String title;

  @Index(type: CindelIndexType.words, caseSensitive: false)
  late String titleWords;

  late bool completed;

  late int createdAtMicros;

  Todo toDomain() {
    return Todo(
      id: id,
      title: title,
      completed: completed,
      createdAt: DateTime.fromMicrosecondsSinceEpoch(createdAtMicros),
    );
  }

  static TodoModel fromDomain(Todo todo) {
    return TodoModel()
      ..id = todo.id
      ..title = todo.title
      ..titleWords = todo.title
      ..completed = todo.completed
      ..createdAtMicros = todo.createdAt.microsecondsSinceEpoch;
  }
}
