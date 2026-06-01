// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'shopping_di.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(shoppingLocalDataSource)
final shoppingLocalDataSourceProvider = ShoppingLocalDataSourceProvider._();

final class ShoppingLocalDataSourceProvider
    extends
        $FunctionalProvider<
          ShoppingLocalDataSource,
          ShoppingLocalDataSource,
          ShoppingLocalDataSource
        >
    with $Provider<ShoppingLocalDataSource> {
  ShoppingLocalDataSourceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'shoppingLocalDataSourceProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$shoppingLocalDataSourceHash();

  @$internal
  @override
  $ProviderElement<ShoppingLocalDataSource> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  ShoppingLocalDataSource create(Ref ref) {
    return shoppingLocalDataSource(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ShoppingLocalDataSource value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ShoppingLocalDataSource>(value),
    );
  }
}

String _$shoppingLocalDataSourceHash() =>
    r'4e8cd520a0dfe70f7126716d2f59ee40958717ec';

@ProviderFor(shoppingRepository)
final shoppingRepositoryProvider = ShoppingRepositoryProvider._();

final class ShoppingRepositoryProvider
    extends
        $FunctionalProvider<
          ShoppingRepository,
          ShoppingRepository,
          ShoppingRepository
        >
    with $Provider<ShoppingRepository> {
  ShoppingRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'shoppingRepositoryProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$shoppingRepositoryHash();

  @$internal
  @override
  $ProviderElement<ShoppingRepository> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  ShoppingRepository create(Ref ref) {
    return shoppingRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ShoppingRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ShoppingRepository>(value),
    );
  }
}

String _$shoppingRepositoryHash() =>
    r'00508858c4ec58da216dde711b56aac0653adf5c';

@ProviderFor(checkoutCartUseCase)
final checkoutCartUseCaseProvider = CheckoutCartUseCaseProvider._();

final class CheckoutCartUseCaseProvider
    extends $FunctionalProvider<CheckoutCart, CheckoutCart, CheckoutCart>
    with $Provider<CheckoutCart> {
  CheckoutCartUseCaseProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'checkoutCartUseCaseProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$checkoutCartUseCaseHash();

  @$internal
  @override
  $ProviderElement<CheckoutCart> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  CheckoutCart create(Ref ref) {
    return checkoutCartUseCase(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(CheckoutCart value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<CheckoutCart>(value),
    );
  }
}

String _$checkoutCartUseCaseHash() =>
    r'ddbaffebd1b9a781696f21101c64a79e42e08c03';
