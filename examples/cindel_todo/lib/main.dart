import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'features/todos/presentation/pages/todo_list_page.dart';

void main() {
  runApp(const ProviderScope(child: CindelTodoApp()));
}

class CindelTodoApp extends StatelessWidget {
  const CindelTodoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cindel Todo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF167C80)),
        useMaterial3: true,
      ),
      home: const TodoListPage(),
    );
  }
}
