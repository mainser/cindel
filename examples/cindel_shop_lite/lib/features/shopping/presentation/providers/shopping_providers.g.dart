// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'shopping_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// In-memory cart state shared across tabs.
///
/// The provider is kept alive because products are added from the catalog tab
/// before the shopping page may be mounted.

@ProviderFor(ShoppingCartController)
final shoppingCartControllerProvider = ShoppingCartControllerProvider._();

/// In-memory cart state shared across tabs.
///
/// The provider is kept alive because products are added from the catalog tab
/// before the shopping page may be mounted.
final class ShoppingCartControllerProvider
    extends $NotifierProvider<ShoppingCartController, ShoppingCart> {
  /// In-memory cart state shared across tabs.
  ///
  /// The provider is kept alive because products are added from the catalog tab
  /// before the shopping page may be mounted.
  ShoppingCartControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'shoppingCartControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$shoppingCartControllerHash();

  @$internal
  @override
  ShoppingCartController create() => ShoppingCartController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ShoppingCart value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ShoppingCart>(value),
    );
  }
}

String _$shoppingCartControllerHash() =>
    r'0a052b3848707e49592bb3fbd380255b0621c54f';

/// In-memory cart state shared across tabs.
///
/// The provider is kept alive because products are added from the catalog tab
/// before the shopping page may be mounted.

abstract class _$ShoppingCartController extends $Notifier<ShoppingCart> {
  ShoppingCart build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<ShoppingCart, ShoppingCart>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<ShoppingCart, ShoppingCart>,
              ShoppingCart,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}

/// Executes the simulated checkout and refreshes Cindel-backed UI state.

@ProviderFor(CheckoutController)
final checkoutControllerProvider = CheckoutControllerProvider._();

/// Executes the simulated checkout and refreshes Cindel-backed UI state.
final class CheckoutControllerProvider
    extends $AsyncNotifierProvider<CheckoutController, void> {
  /// Executes the simulated checkout and refreshes Cindel-backed UI state.
  CheckoutControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'checkoutControllerProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$checkoutControllerHash();

  @$internal
  @override
  CheckoutController create() => CheckoutController();
}

String _$checkoutControllerHash() =>
    r'68d580a2662b36c4db498989402bfef91b58f036';

/// Executes the simulated checkout and refreshes Cindel-backed UI state.

abstract class _$CheckoutController extends $AsyncNotifier<void> {
  FutureOr<void> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<AsyncValue<void>, void>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<void>, void>,
              AsyncValue<void>,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
