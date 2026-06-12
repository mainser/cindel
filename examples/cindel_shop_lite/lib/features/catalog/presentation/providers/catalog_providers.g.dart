// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'catalog_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Runs catalog startup work that should happen once when the app launches.
///
/// The seed is guarded by the data source, so watching this provider from the
/// app shell does not duplicate demo products.

@ProviderFor(catalogStartup)
final catalogStartupProvider = CatalogStartupProvider._();

/// Runs catalog startup work that should happen once when the app launches.
///
/// The seed is guarded by the data source, so watching this provider from the
/// app shell does not duplicate demo products.

final class CatalogStartupProvider
    extends $FunctionalProvider<AsyncValue<void>, void, FutureOr<void>>
    with $FutureModifier<void>, $FutureProvider<void> {
  /// Runs catalog startup work that should happen once when the app launches.
  ///
  /// The seed is guarded by the data source, so watching this provider from the
  /// app shell does not duplicate demo products.
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

String _$catalogStartupHash() => r'5b4c0dc744edc0b66efb58dac6aecbb5dd93a3c0';

/// Loads and appends catalog pages in response to scroll position.

@ProviderFor(CatalogProductsController)
final catalogProductsControllerProvider = CatalogProductsControllerProvider._();

/// Loads and appends catalog pages in response to scroll position.
final class CatalogProductsControllerProvider
    extends
        $AsyncNotifierProvider<CatalogProductsController, CatalogProductsPage> {
  /// Loads and appends catalog pages in response to scroll position.
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
    r'7fdc309aa8f0b699c54f18fde59bd473ffa77342';

/// Loads and appends catalog pages in response to scroll position.

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

/// Product count used by catalog chrome and lightweight status surfaces.

@ProviderFor(catalogProductCount)
final catalogProductCountProvider = CatalogProductCountProvider._();

/// Product count used by catalog chrome and lightweight status surfaces.

final class CatalogProductCountProvider
    extends $FunctionalProvider<AsyncValue<int>, int, FutureOr<int>>
    with $FutureModifier<int>, $FutureProvider<int> {
  /// Product count used by catalog chrome and lightweight status surfaces.
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
    r'7696b55d7ff7dd02d78b1382ae9c47253eed06cb';

/// Stores the active catalog query selected by search and filter controls.

@ProviderFor(CatalogQueryController)
final catalogQueryControllerProvider = CatalogQueryControllerProvider._();

/// Stores the active catalog query selected by search and filter controls.
final class CatalogQueryControllerProvider
    extends $NotifierProvider<CatalogQueryController, CatalogQuery> {
  /// Stores the active catalog query selected by search and filter controls.
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

/// Stores the active catalog query selected by search and filter controls.

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
