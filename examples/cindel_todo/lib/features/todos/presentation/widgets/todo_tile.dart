import 'package:flutter/material.dart';

import '../../domain/entities/todo.dart';

final class TodoTile extends StatelessWidget {
  const TodoTile({
    required this.todo,
    required this.onToggle,
    required this.onDelete,
    super.key,
  });

  final Todo todo;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
      leading: Checkbox(value: todo.completed, onChanged: (_) => onToggle()),
      title: Text(
        todo.title,
        style: todo.completed
            ? textTheme.titleMedium?.copyWith(
                decoration: TextDecoration.lineThrough,
              )
            : textTheme.titleMedium,
      ),
      subtitle: Text('Stored with id ${todo.id}'),
      trailing: IconButton(
        tooltip: 'Delete todo',
        onPressed: onDelete,
        icon: const Icon(Icons.delete_outline),
      ),
    );
  }
}
