import 'package:cindel/cindel.dart';

import '../models/todo_model.dart';

final class TodosLocalDataSource {
  const TodosLocalDataSource(this._database);

  final Future<CindelDatabase> _database;

  Future<void> save(TodoModel todo) async {
    final database = await _database;
    await database.put('todos', todo.id, TodoModelSchema.toDocument(todo));
  }

  Future<void> delete(int id) async {
    final database = await _database;
    await database.delete('todos', id);
  }

  Stream<List<TodoModel>> watchTodos() async* {
    final database = await _database;
    yield* database.watchCollection('todos').map(_modelsFromDocuments);
  }

  Future<List<TodoModel>> searchByExactTitle(String title) async {
    final database = await _database;
    final documents = await database.queryEqual('todos', 'title', title);
    return _modelsFromDocuments(documents);
  }

  Future<List<TodoModel>> searchByTitlePrefix(String prefix) async {
    final database = await _database;
    final upperBound = _inclusivePrefixUpperBound(prefix);
    final documents = await database.queryRange(
      'todos',
      'title',
      lower: prefix,
      upper: upperBound,
    );
    return _modelsFromDocuments(
      documents.where((document) {
        final title = document['title'];
        return title is String && title.startsWith(prefix);
      }),
    );
  }

  Future<int> readSchemaVersion() async {
    final database = await _database;
    return await database.schemaVersion('todos') ?? 0;
  }
}

List<TodoModel> _modelsFromDocuments(Iterable<CindelDocument> documents) {
  final models = documents
      .map(TodoModelSchema.fromDocument)
      .toList(growable: false);
  return models..sort(
    (left, right) => right.createdAtMicros.compareTo(left.createdAtMicros),
  );
}

String _inclusivePrefixUpperBound(String prefix) {
  if (prefix.isEmpty) {
    return prefix;
  }
  final lastCodeUnit = prefix.codeUnitAt(prefix.length - 1);
  final nextCodeUnit = lastCodeUnit + 1;
  return '${prefix.substring(0, prefix.length - 1)}${String.fromCharCode(nextCodeUnit)}';
}
