import 'dart:async';

import 'package:adaptive_theme/adaptive_theme.dart';
import 'package:flutter/material.dart' show MaterialApp;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Initializes the app by setting up necessary configurations and then runs the
/// app.
///
/// The [builder] function is called with the saved theme mode (if any) and is
/// expected to return the root widget of the app, typically a [MaterialApp].
Future<void> bootstrap(
  FutureOr<Widget> Function(AdaptiveThemeMode? themeMode) builder,
) async {
  /// Ensures that the Flutter framework is initialized before running the app.
  WidgetsFlutterBinding.ensureInitialized();

  /// Retrieves the saved theme mode from persistent storage using the
  /// AdaptiveTheme package. This allows the app to start with the user's
  /// preferred theme mode (light, dark, or system) if it was previously saved.
  final themeSaved = await AdaptiveTheme.getThemeMode();

  /// Runs the app by calling the provided [builder] function with the saved
  /// theme mode. The [ProviderScope] widget is used to provide a scope for
  /// Riverpod providers, allowing them to be accessed throughout the app.
  runApp(ProviderScope(child: await builder(themeSaved)));
}
