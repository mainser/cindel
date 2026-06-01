// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'catalog_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(catalogStartup)
final catalogStartupProvider = CatalogStartupProvider._();

final class CatalogStartupProvider
    extends $FunctionalProvider<AsyncValue<void>, void, FutureOr<void>>
    with $FutureModifier<void>, $FutureProvider<void> {
  CatalogStartupProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'catalogStartupProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$catalogStartupHash();

  @$internal
  @override
  $FutureProviderElement<void> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<void> create(Ref ref) {
    return catalogStartup(ref);
  }
}

String _$catalogStartupHash() => r'67e45c7309dd6fc99d3ce8dc8d9c06f3c4a4e583';

@ProviderFor(catalogProducts)
final catalogProductsProvider = CatalogProductsProvider._();

final class CatalogProductsProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<Product>>,
          List<Product>,
          Stream<List<Product>>
        >
    with $FutureModifier<List<Product>>, $StreamProvider<List<Product>> {
  CatalogProductsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'catalogProductsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$catalogProductsHash();

  @$internal
  @override
  $StreamProviderElement<List<Product>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<List<Product>> create(Ref ref) {
    return catalogProducts(ref);
  }
}

String _$catalogProductsHash() => r'9bb80ad3fddcdea111285e7bc73b6d8efa309a14';

@ProviderFor(catalogProductCount)
final catalogProductCountProvider = CatalogProductCountProvider._();

final class CatalogProductCountProvider
    extends $FunctionalProvider<AsyncValue<int>, int, FutureOr<int>>
    with $FutureModifier<int>, $FutureProvider<int> {
  CatalogProductCountProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'catalogProductCountProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$catalogProductCountHash();

  @$internal
  @override
  $FutureProviderElement<int> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<int> create(Ref ref) {
    return catalogProductCount(ref);
  }
}

String _$catalogProductCountHash() =>
    r'1f24c8135a79486ae48dad124230b18c75ccb166';

@ProviderFor(CatalogQueryController)
final catalogQueryControllerProvider = CatalogQueryControllerProvider._();

final class CatalogQueryControllerProvider
    extends $NotifierProvider<CatalogQueryController, CatalogQuery> {
  CatalogQueryControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'catalogQueryControllerProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$catalogQueryControllerHash();

  @$internal
  @override
  CatalogQueryController create() => CatalogQueryController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(CatalogQuery value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<CatalogQuery>(value),
    );
  }
}

String _$catalogQueryControllerHash() =>
    r'ce99f7d7e8b4b4acb5736fb199f9ef0c3b883b8d';

abstract class _$CatalogQueryController extends $Notifier<CatalogQuery> {
  CatalogQuery build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<CatalogQuery, CatalogQuery>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<CatalogQuery, CatalogQuery>,
              CatalogQuery,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
