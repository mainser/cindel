import 'package:cindel_shop_lite/app/app.dart';
import 'package:cindel_shop_lite/features/catalog/presentation/pages/catalog_page.dart';
import 'package:cindel_shop_lite/features/dashboard/presentation/page/dashboard_page.dart';
import 'package:cindel_shop_lite/features/shopping/presentation/page/shopping_page.dart';
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
    requestFocus: false,
    initialLocation: AppRoutes.dashboard,
    routes: [
      // Shell
      ShellRoute(
        builder: (context, state, child) => ShellPage(child: child),
        routes: [
          GoRoute(
            path: AppRoutes.catalog,
            pageBuilder: (context, state) =>
                _shellPage(state, const CatalogPage()),
          ),
          GoRoute(
            path: AppRoutes.shopping,
            pageBuilder: (context, state) =>
                _shellPage(state, const ShoppingPage()),
          ),
          GoRoute(
            path: AppRoutes.dashboard,
            pageBuilder: (context, state) =>
                _shellPage(state, const DashboardPage()),
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
