import 'package:cindel_shop_lite/core/router/app_router.dart';
import 'package:cindel_shop_lite/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class ShellPage extends StatelessWidget {
  const ShellPage({required this.child, super.key});

  final Widget child;

  static const List<String> _tabs = [
    AppRoutes.dashboard,
    AppRoutes.catalog,
    AppRoutes.shopping,
  ];

  int _currentIndex(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    final index = _tabs.indexWhere(
      (route) => location == route || location.startsWith('$route/'),
    );

    return index == -1 ? 0 : index;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colorScheme = Theme.of(context).colorScheme;
    final index = _currentIndex(context);

    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        height: 72,
        backgroundColor: colorScheme.surface,
        indicatorColor: colorScheme.primaryContainer,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        onDestinationSelected: (i) {
          if (i != index) {
            context.go(_tabs[i]);
          }
        },
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.dashboard_outlined),
            selectedIcon: const Icon(Icons.dashboard),
            label: l10n.dashboard,
          ),
          NavigationDestination(
            icon: const Icon(Icons.inventory_2_outlined),
            selectedIcon: const Icon(Icons.inventory_2),
            label: l10n.catalog,
          ),
          NavigationDestination(
            icon: const Icon(Icons.shopping_cart_outlined),
            selectedIcon: const Icon(Icons.shopping_cart),
            label: l10n.shopping,
          ),
        ],
      ),
    );
  }
}
