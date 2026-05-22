import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/todo.dart';
import '../providers/todos_providers.dart';
import '../utils/todo_messages.dart';
import '../widgets/todo_editor.dart';
import '../widgets/todo_search_panel.dart';
import '../widgets/todo_tile.dart';

final class TodoListPage extends ConsumerStatefulWidget {
  const TodoListPage({super.key});

  @override
  ConsumerState<TodoListPage> createState() => _TodoListPageState();
}

final class _TodoListPageState extends ConsumerState<TodoListPage> {
  final _newTodoController = TextEditingController();
  final _searchController = TextEditingController();
  bool _isSearchActive = false;
  String _activeSearchTitle = 'Live collection';

  @override
  void dispose() {
    _newTodoController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(todoMutationControllerProvider, (_, next) {
      next.whenOrNull(
        error: (error, _) => _showSnackBar(todoErrorMessage(error)),
      );
    });
    ref.listen(todoSearchControllerProvider, (_, next) {
      next.whenOrNull(
        error: (error, _) => _showSnackBar(todoErrorMessage(error)),
      );
    });

    final todos = ref.watch(todoListProvider);
    final mutation = ref.watch(todoMutationControllerProvider);
    final search = ref.watch(todoSearchControllerProvider);
    final schemaVersion = ref.watch(todoSchemaVersionProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cindel Todo'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: schemaVersion.when(
                data: (version) => Chip(
                  avatar: const Icon(Icons.storage_outlined, size: 18),
                  label: Text('schema v$version'),
                ),
                loading: () => const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                error: (_, _) => const Chip(label: Text('schema unavailable')),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                TodoEditor(
                  controller: _newTodoController,
                  isSaving: mutation.isLoading,
                  onSubmit: _addTodo,
                ),
                const SizedBox(height: 20),
                TodoSearchPanel(
                  controller: _searchController,
                  isSearching: search.isLoading,
                  onExactSearch: _searchExact,
                  onPrefixSearch: _searchPrefix,
                  onClear: () {
                    _searchController.clear();
                    setState(() {
                      _isSearchActive = false;
                      _activeSearchTitle = 'Live collection';
                    });
                    ref.read(todoSearchControllerProvider.notifier).clear();
                  },
                ),
                const SizedBox(height: 24),
                Text(
                  _activeSearchTitle,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                (_isSearchActive ? search : todos).when(
                  data: (items) => _TodoList(
                    items: items,
                    isSearchActive: _isSearchActive,
                    onToggle: (todo) => ref
                        .read(todoMutationControllerProvider.notifier)
                        .toggle(todo),
                    onDelete: (id) => ref
                        .read(todoMutationControllerProvider.notifier)
                        .delete(id),
                  ),
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (error, _) => Text(todoErrorMessage(error)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _addTodo() {
    final title = _newTodoController.text;
    ref.read(todoMutationControllerProvider.notifier).add(title);
    if (title.trim().isNotEmpty) {
      _newTodoController.clear();
    }
  }

  void _searchExact() {
    final title = _searchController.text.trim();
    setState(() {
      _isSearchActive = title.isNotEmpty;
      _activeSearchTitle = title.isEmpty ? 'Live collection' : 'Exact matches';
    });
    ref.read(todoSearchControllerProvider.notifier).searchExact(title);
  }

  void _searchPrefix() {
    final prefix = _searchController.text.trim();
    setState(() {
      _isSearchActive = prefix.isNotEmpty;
      _activeSearchTitle = prefix.isEmpty
          ? 'Live collection'
          : 'Prefix matches';
    });
    ref.read(todoSearchControllerProvider.notifier).searchPrefix(prefix);
  }

  void _showSnackBar(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

final class _TodoList extends StatelessWidget {
  const _TodoList({
    required this.items,
    required this.isSearchActive,
    required this.onToggle,
    required this.onDelete,
  });

  final List<Todo> items;
  final bool isSearchActive;
  final ValueChanged<Todo> onToggle;
  final ValueChanged<int> onDelete;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return isSearchActive
          ? const _EmptySearchResults()
          : const _EmptyTodoList();
    }

    return Column(
      children: [
        for (final todo in items)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: TodoTile(
              todo: todo,
              onToggle: () => onToggle(todo),
              onDelete: () => onDelete(todo.id),
            ),
          ),
      ],
    );
  }
}

final class _EmptyTodoList extends StatelessWidget {
  const _EmptyTodoList();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: [
          Icon(
            Icons.inbox_outlined,
            size: 48,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 12),
          Text(
            'Add a todo to see Cindel persist it and stream it back.',
            style: Theme.of(context).textTheme.bodyLarge,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

final class _EmptySearchResults extends StatelessWidget {
  const _EmptySearchResults();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: [
          Icon(
            Icons.search_off,
            size: 48,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 12),
          Text(
            'No todos match this title.',
            style: Theme.of(context).textTheme.bodyLarge,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
