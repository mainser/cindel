// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'shopping_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(ShoppingCartController)
final shoppingCartControllerProvider = ShoppingCartControllerProvider._();

final class ShoppingCartControllerProvider
    extends $NotifierProvider<ShoppingCartController, ShoppingCart> {
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

@ProviderFor(CheckoutController)
final checkoutControllerProvider = CheckoutControllerProvider._();

final class CheckoutControllerProvider
    extends $AsyncNotifierProvider<CheckoutController, void> {
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
