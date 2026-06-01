import 'package:cindel_shop_lite/core/theme/app_colors.dart';
import 'package:cindel_shop_lite/core/theme/app_text_style.dart';
import 'package:flutter/material.dart';

/// The [AppTheme] class defines the overall theme for the application,
/// including both light and dark themes.
///
/// It uses the [AppColors] class to define the color schemes for light and
/// dark themes, and the [AppTextStyle] class to define the text styles for both
/// themes.
abstract class AppTheme {
  /// The [lightTheme] getter returns the light theme by calling the private
  /// `_buildTheme` method with the light color scheme.
  static ThemeData get lightTheme => _buildTheme(AppColors.lightScheme);

  /// The [darkTheme] getter returns the dark theme by calling the private
  /// `_buildTheme` method with the dark color scheme.
  static ThemeData get darkTheme => _buildTheme(AppColors.darkScheme);

  /// The `_buildTheme` method takes a [ColorScheme] as an argument and returns
  /// a [ThemeData] object configured with the provided color scheme and text
  /// theme.
  static ThemeData _buildTheme(ColorScheme colorScheme) => ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    brightness: colorScheme.brightness,
    textTheme: AppTextStyle.defaultTextTheme(colorScheme),
  );
}
