import 'package:flutter/material.dart';

final class TodoSearchPanel extends StatelessWidget {
  const TodoSearchPanel({
    required this.controller,
    required this.isSearching,
    required this.onExactSearch,
    required this.onPrefixSearch,
    required this.onClear,
    super.key,
  });

  final TextEditingController controller;
  final bool isSearching;
  final VoidCallback onExactSearch;
  final VoidCallback onPrefixSearch;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                decoration: const InputDecoration(
                  labelText: 'Indexed title search',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.search),
                ),
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => onExactSearch(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.outlined(
              tooltip: 'Search exact title',
              onPressed: isSearching ? null : onExactSearch,
              icon: const Icon(Icons.pin_outlined),
            ),
            const SizedBox(width: 8),
            IconButton.outlined(
              tooltip: 'Search title prefix',
              onPressed: isSearching ? null : onPrefixSearch,
              icon: const Icon(Icons.manage_search),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Clear search',
              onPressed: isSearching ? null : onClear,
              icon: const Icon(Icons.close),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (isSearching) const LinearProgressIndicator(),
      ],
    );
  }
}
