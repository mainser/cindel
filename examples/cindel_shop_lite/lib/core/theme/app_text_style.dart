import 'package:flutter/material.dart';

/// The [AppTextStyle] class provides a set of predefined text styles for the
/// application.
///
/// Each text style is defined as a static method that takes a [ColorScheme] and
/// returns a [TextStyle] with the appropriate properties (font size, height,
/// weight, letter spacing, and color). The `defaultTextTheme` method aggregates
/// all the individual text styles into a [TextTheme] that can be used
/// throughout the application for consistent typography.
class AppTextStyle {
  ///
  /// The **2021** spec has fifteen text styles:
  ///
  /// | NAME           | SIZE |  HEIGHT |  WEIGHT |  SPACING |             |
  /// |----------------|------|---------|---------|----------|-------------|
  /// | displayLarge   | 57.0 |   64.0  | regular | -0.25    |             |
  /// | displayMedium  | 45.0 |   52.0  | regular |  0.0     |             |
  /// | displaySmall   | 36.0 |   44.0  | regular |  0.0     |             |
  /// | headlineLarge  | 32.0 |   40.0  | regular |  0.0     |             |
  /// | headlineMedium | 28.0 |   36.0  | regular |  0.0     |             |
  /// | headlineSmall  | 24.0 |   32.0  | regular |  0.0     |             |
  /// | titleLarge     | 22.0 |   28.0  | regular |  0.0     |             |
  /// | titleMedium    | 16.0 |   24.0  | medium  |  0.15    |             |
  /// | titleSmall     | 14.0 |   20.0  | medium  |  0.1     |             |
  /// | bodyLarge      | 16.0 |   24.0  | regular |  0.5     |             |
  /// | bodyMedium     | 14.0 |   20.0  | regular |  0.25    |             |
  /// | bodySmall      | 12.0 |   16.0  | regular |  0.4     |             |
  /// | labelLarge     | 14.0 |   20.0  | medium  |  0.1     |             |
  /// | labelMedium    | 12.0 |   16.0  | medium  |  0.5     |             |
  /// | labelSmall     | 11.0 |   16.0  | medium  |  0.5     |             |
  ///
  /// ...where "regular" is `FontWeight.w400` and "medium" is `FontWeight.w500`.

  // ── Default Text Theme ────────────────────────────────────────────────────
  static TextTheme defaultTextTheme(ColorScheme colorScheme) => TextTheme(
    displayLarge: _displayLarge(colorScheme),
    displayMedium: _displayMedium(colorScheme),
    displaySmall: _displaySmall(colorScheme),
    headlineLarge: _headlineLarge(colorScheme),
    headlineMedium: _headlineMedium(colorScheme),
    headlineSmall: _headlineSmall(colorScheme),
    titleLarge: _titleLarge(colorScheme),
    titleMedium: _titleMedium(colorScheme),
    titleSmall: _titleSmall(colorScheme),
    bodyLarge: _bodyLarge(colorScheme),
    bodyMedium: _bodyMedium(colorScheme),
    bodySmall: _bodySmall(colorScheme),
    labelLarge: _labelLarge(colorScheme),
    labelMedium: _labelMedium(colorScheme),
    labelSmall: _labelSmall(colorScheme),
  );

  static TextStyle _displayLarge(ColorScheme colorScheme) => TextStyle(
    fontSize: 57,
    height: 64 / 57,
    fontWeight: FontWeight.w400,
    letterSpacing: -0.25,
    color: colorScheme.onSurface,
  );

  static TextStyle _displayMedium(ColorScheme colorScheme) => TextStyle(
    fontSize: 45,
    height: 52 / 45,
    fontWeight: FontWeight.w400,
    letterSpacing: 0,
    color: colorScheme.onSurface,
  );

  static TextStyle _displaySmall(ColorScheme colorScheme) => TextStyle(
    fontSize: 36,
    height: 44 / 36,
    fontWeight: FontWeight.w400,
    letterSpacing: 0,
    color: colorScheme.onSurface,
  );

  static TextStyle _headlineLarge(ColorScheme colorScheme) => TextStyle(
    fontSize: 32,
    height: 40 / 32,
    fontWeight: FontWeight.w400,
    letterSpacing: 0,
    color: colorScheme.onSurface,
  );

  static TextStyle _headlineMedium(ColorScheme colorScheme) => TextStyle(
    fontSize: 28,
    height: 36 / 28,
    fontWeight: FontWeight.w400,
    letterSpacing: 0,
    color: colorScheme.onSurface,
  );

  static TextStyle _headlineSmall(ColorScheme colorScheme) => TextStyle(
    fontSize: 24,
    height: 32 / 24,
    fontWeight: FontWeight.w400,
    letterSpacing: 0,
    color: colorScheme.onSurface,
  );

  static TextStyle _titleLarge(ColorScheme colorScheme) => TextStyle(
    fontSize: 22,
    height: 28 / 22,
    fontWeight: FontWeight.w400,
    letterSpacing: 0,
    color: colorScheme.onSurface,
  );

  static TextStyle _titleMedium(ColorScheme colorScheme) => TextStyle(
    fontSize: 16,
    height: 24 / 16,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.15,
    color: colorScheme.onSurface,
  );

  static TextStyle _titleSmall(ColorScheme colorScheme) => TextStyle(
    fontSize: 14,
    height: 20 / 14,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.1,
    color: colorScheme.onSurface,
  );

  static TextStyle _bodyLarge(ColorScheme colorScheme) => TextStyle(
    fontSize: 16,
    height: 24 / 16,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.5,
    color: colorScheme.onSurface,
  );

  static TextStyle _bodyMedium(ColorScheme colorScheme) => TextStyle(
    fontSize: 14,
    height: 20 / 14,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.25,
    color: colorScheme.onSurface,
  );

  static TextStyle _bodySmall(ColorScheme colorScheme) => TextStyle(
    fontSize: 12,
    height: 16 / 12,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.4,
    color: colorScheme.onSurface,
  );

  static TextStyle _labelLarge(ColorScheme colorScheme) => TextStyle(
    fontSize: 14,
    height: 20 / 14,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.1,
    color: colorScheme.onSurface,
  );

  static TextStyle _labelMedium(ColorScheme colorScheme) => TextStyle(
    fontSize: 12,
    height: 16 / 12,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.5,
    color: colorScheme.onSurface,
  );

  static TextStyle _labelSmall(ColorScheme colorScheme) => TextStyle(
    fontSize: 11,
    height: 16 / 11,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.5,
    color: colorScheme.onSurface,
  );
}
