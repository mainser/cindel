import 'package:cindel_shop_lite/app/app.dart';
import 'package:cindel_shop_lite/features/catalog/view/catalog_view.dart';
import 'package:cindel_shop_lite/features/dashboard/view/dashboard_view.dart';
import 'package:cindel_shop_lite/features/shopping/view/shopping_view.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'app_router.g.dart';

/// This file contains the app router, which is used to navigate between
/// different screens in the app.
abstract class AppRoutes {
  static const String catalog = '/catalog';
  static const String dashboard = '/dashboard';
  static const String shopping = '/shopping';
}

/// This file contains the app router, which is used to navigate between
/// different screens in the app.
@Riverpod(keepAlive: true)
GoRouter appRouter(Ref ref) {
  return GoRouter(
    debugLogDiagnostics: true,
    initialLocation: AppRoutes.dashboard,
    routes: [
      // Shell
      ShellRoute(
        builder: (context, state, child) => ShellView(child: child),
        routes: [
          GoRoute(
            path: AppRoutes.catalog,
            pageBuilder: (context, state) =>
                _shellPage(state, const CatalogView()),
          ),
          GoRoute(
            path: AppRoutes.shopping,
            pageBuilder: (context, state) =>
                _shellPage(state, const ShoppingView()),
          ),
          GoRoute(
            path: AppRoutes.dashboard,
            pageBuilder: (context, state) =>
                _shellPage(state, const DashboardView()),
          ),
        ],
      ),
    ],
  );
}

Page<void> _shellPage(GoRouterState state, Widget child) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    reverseTransitionDuration: const Duration(milliseconds: 200),
    transitionsBuilder: (_, animation, _, child) {
      final offset = Tween<Offset>(
        begin: const Offset(0.04, 0),
        end: Offset.zero,
      ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOut));

      return SlideTransition(position: offset, child: child);
    },
  );
}
