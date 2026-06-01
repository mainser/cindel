import 'package:flutter/material.dart';

/// Enum for different types of snack messages.
enum SnackType { success, error, warning, info }

/// Class to define the style for each type of snack message.
class SnackStyle {
  /// Constructor for SnackStyle.
  ///
  /// Takes a [Widget] icon and a [Color] bgColor as parameters.
  SnackStyle({required this.bgColor, required this.textColor});

  /// Background color for the snack message.
  final Color bgColor;

  /// Background color for text.
  final Color textColor;
}

/// Class for creating snack messages.
///
/// It provides a way to show snack messages with different types.
class SnackMessage {
  /// Private constructor for SnackMessage.
  SnackMessage._(this.context);

  /// Factory constructor for SnackMessage.
  ///
  /// Takes a [BuildContext] context as parameter.
  factory SnackMessage.of(BuildContext context) => SnackMessage._(context);

  /// The build context in which the snack message will be shown.
  final BuildContext context;

  /// Method to show a success snack message.
  ///
  /// Takes a [String] message and an optional [Duration] duration as parameters
  void success({required String message, Duration? duration}) {
    return _showSnackBar(message, SnackType.success, duration);
  }

  /// Method to show an error snack message.
  ///
  /// Takes a [String] message and an optional [Duration] duration as parameters
  void error({required String message, Duration? duration}) {
    return _showSnackBar(message, SnackType.error, duration);
  }

  /// Method to show a warning snack message.
  ///
  /// Takes a [String] message and an optional [Duration] duration as parameters
  void warning({required String message, Duration? duration}) {
    return _showSnackBar(message, SnackType.warning, duration);
  }

  /// Method to show an info snack message.
  ///
  /// Takes a [String] message and an optional [Duration] duration as parameters
  void info({required String message, Duration? duration}) {
    return _showSnackBar(message, SnackType.info, duration);
  }

  /// Private method to show a snack bar.
  ///
  /// Takes a [String] message, a [SnackType] type, and an optional [Duration]
  /// duration as parameters.
  void _showSnackBar(String message, SnackType type, Duration? duration) {
    final theme = Theme.of(context);
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    // Snack styles
    final snackStyles = <SnackType, SnackStyle>{
      // SUCCESS
      SnackType.success: SnackStyle(
        bgColor: theme.colorScheme.primary,
        textColor: theme.colorScheme.onPrimary,
      ),

      // ERROR
      SnackType.error: SnackStyle(
        bgColor: theme.colorScheme.error,
        textColor: theme.colorScheme.onError,
      ),

      // WARNING
      SnackType.warning: SnackStyle(
        bgColor: theme.colorScheme.secondary,
        textColor: theme.colorScheme.onSecondary,
      ),

      // INFO
      SnackType.info: SnackStyle(
        bgColor: theme.colorScheme.inverseSurface,
        textColor: theme.colorScheme.onInverseSurface,
      ),
    };

    // Get the snack style for the type of snack message
    final snackTypeStyle = snackStyles[type];

    // Create the snack bar with the message and the snack style
    final snackBar = SnackBar(
      elevation: 4,
      showCloseIcon: true,
      behavior: SnackBarBehavior.floating,
      backgroundColor: snackTypeStyle?.bgColor,
      duration: duration ?? const Duration(seconds: 3),
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      content: Text(
        message,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: snackTypeStyle?.textColor,
        ),
      ),
    );

    // Show the snack bar
    scaffoldMessenger
      ..clearSnackBars()
      ..showSnackBar(snackBar);
  }
}
