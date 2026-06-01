import 'package:adaptive_theme/adaptive_theme.dart';
import 'package:cindel_shop_lite/core/router/app_router.dart';
import 'package:cindel_shop_lite/core/theme/app_theme.dart';
import 'package:cindel_shop_lite/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// This file contains the main app view, which is used to set up the app's
/// theme and router.
class AppView extends ConsumerWidget {
  const AppView({this.themeMode, super.key});

  /// The [themeMode] is used to set the initial theme mode of the app.
  final AdaptiveThemeMode? themeMode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    /// The [AdaptiveTheme] widget is used to set up the app's theme and allow
    /// the user to switch between light and dark mode.
    ///
    /// The [builder] property is used to build the app's main widget, which is
    /// a [MaterialApp.router] widget that uses the app's router to navigate
    /// between different screens in the app.
    return AdaptiveTheme(
      light: AppTheme.lightTheme,
      dark: AppTheme.darkTheme,
      initial: AdaptiveThemeMode.dark,
      debugShowFloatingThemeButton: true,
      builder: (light, dark) => MaterialApp.router(
        theme: light,
        darkTheme: dark,
        debugShowCheckedModeBanner: false,
        routerConfig: ref.watch(appRouterProvider),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
      ),
    );
  }
}
