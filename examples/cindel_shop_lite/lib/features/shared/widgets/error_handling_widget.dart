import 'package:cindel_shop_lite/features/shared/widgets/snack_messages.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hooks_riverpod/misc.dart';

/// A widget that handles errors from a list of providers by displaying
/// SnackBars.
///
/// This widget listens to changes from the specified list of providers and
/// displays a SnackBar if an error occurs. It is useful for handling
/// asynchronous errors.
///
/// The [ErrorHandlingWidget] takes a [child] widget to render as its main
/// content, and a list of [providers] which are listened to for changes.
/// When a change occurs in any of the providers and the new value is an
/// [AsyncError], a SnackBar is shown displaying the error message.
///
/// Example:
/// ```dart
/// ErrorHandlingWidget(
///   child: MyWidget(),
///   providers: [myProvider1, myProvider2],
/// )
/// ```
class ErrorHandlingWidget<T> extends ConsumerWidget {
  const ErrorHandlingWidget({
    required this.providers,
    required this.child,
    super.key,
  });

  /// The main content widget.
  final Widget child;

  /// The list of providers to listen to for changes.
  final List<ProviderBase<T>> providers;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Iterate through the list of providers
    for (final provider in providers) {
      // Listen to changes from the current provider
      ref.listen(provider, (previous, next) {
        // Check if the next value is an AsyncError
        if (next is AsyncError) {
          // If an error occurs, show a SnackBar with the error message
          SnackMessage.of(context).error(message: next.error.toString());
        }
      });
    }

    // Return the child widget
    return child;
  }
}
