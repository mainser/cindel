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

String _$catalogStartupHash() => r'1b7ea2fcbb59d8b4eea795217ba8d9925250c97d';

@ProviderFor(CatalogProductsController)
final catalogProductsControllerProvider = CatalogProductsControllerProvider._();

final class CatalogProductsControllerProvider
    extends
        $AsyncNotifierProvider<CatalogProductsController, CatalogProductsPage> {
  CatalogProductsControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'catalogProductsControllerProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$catalogProductsControllerHash();

  @$internal
  @override
  CatalogProductsController create() => CatalogProductsController();
}

String _$catalogProductsControllerHash() =>
    r'4b135abe627c12ee8d86197d893045bfb96285d9';

abstract class _$CatalogProductsController
    extends $AsyncNotifier<CatalogProductsPage> {
  FutureOr<CatalogProductsPage> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref =
        this.ref as $Ref<AsyncValue<CatalogProductsPage>, CatalogProductsPage>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<CatalogProductsPage>, CatalogProductsPage>,
              AsyncValue<CatalogProductsPage>,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}

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
