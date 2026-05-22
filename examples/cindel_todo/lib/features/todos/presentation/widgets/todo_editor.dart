import 'package:flutter/material.dart';

final class TodoEditor extends StatelessWidget {
  const TodoEditor({
    required this.controller,
    required this.isSaving,
    required this.onSubmit,
    super.key,
  });

  final TextEditingController controller;
  final bool isSaving;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            decoration: const InputDecoration(
              labelText: 'New todo',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.edit_outlined),
            ),
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => onSubmit(),
          ),
        ),
        const SizedBox(width: 12),
        IconButton.filled(
          tooltip: 'Add todo',
          onPressed: isSaving ? null : onSubmit,
          icon: isSaving
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.add),
        ),
      ],
    );
  }
}
