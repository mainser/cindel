import 'package:flutter/material.dart';

final class CatalogError extends StatelessWidget {
  const CatalogError({required this.message, super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(size: 48, Icons.error_outline, color: theme.colorScheme.error),
          const SizedBox(height: 12),
          Text(message, style: theme.textTheme.bodyLarge),
        ],
      ),
    );
  }
}
