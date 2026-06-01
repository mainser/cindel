import 'package:flutter/material.dart';

/// Defines the color scheme for the application, including both light and dark
/// themes.
abstract class AppColors {
  /// The seed color used to generate the color schemes for both light and dark
  /// themes.
  static ColorScheme lightScheme = ColorScheme.fromSeed(
    seedColor: seedColor,
  );

  /// The seed color used to generate the color schemes for both light and dark
  /// themes.
  static ColorScheme darkScheme = ColorScheme.fromSeed(
    seedColor: seedColor,
    brightness: Brightness.dark,
  );

  /// The seed color used to generate the color schemes for both light and dark
  /// themes.
  static const Color seedColor = Color(0xFF167C80);
}
