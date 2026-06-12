// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'catalog_di.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Opens the local Cindel database used by the demo catalog.
///
/// The app registers only [ProductSchema] today, so catalog, dashboard, and
/// checkout all operate over the same typed products collection.

@ProviderFor(catalogDatabase)
final catalogDatabaseProvider = CatalogDatabaseProvider._();

/// Opens the local Cindel database used by the demo catalog.
///
/// The app registers only [ProductSchema] today, so catalog, dashboard, and
/// checkout all operate over the same typed products collection.

final class CatalogDatabaseProvider
    extends
        $FunctionalProvider<
          AsyncValue<CindelDatabase>,
          CindelDatabase,
          FutureOr<CindelDatabase>
        >
    with $FutureModifier<CindelDatabase>, $FutureProvider<CindelDatabase> {
  /// Opens the local Cindel database used by the demo catalog.
  ///
  /// The app registers only [ProductSchema] today, so catalog, dashboard, and
  /// checkout all operate over the same typed products collection.
  CatalogDatabaseProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'catalogDatabaseProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$catalogDatabaseHash();

  @$internal
  @override
  $FutureProviderElement<CindelDatabase> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<CindelDatabase> create(Ref ref) {
    return catalogDatabase(ref);
  }
}

String _$catalogDatabaseHash() => r'22eebb589cfc6c15a6d315a971f199b73958b4e9';

/// Provides the catalog data source backed by the shared Cindel database.

@ProviderFor(catalogLocalDataSource)
final catalogLocalDataSourceProvider = CatalogLocalDataSourceProvider._();

/// Provides the catalog data source backed by the shared Cindel database.

final class CatalogLocalDataSourceProvider
    extends
        $FunctionalProvider<
          CatalogLocalDataSource,
          CatalogLocalDataSource,
          CatalogLocalDataSource
        >
    with $Provider<CatalogLocalDataSource> {
  /// Provides the catalog data source backed by the shared Cindel database.
  CatalogLocalDataSourceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'catalogLocalDataSourceProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$catalogLocalDataSourceHash();

  @$internal
  @override
  $ProviderElement<CatalogLocalDataSource> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  CatalogLocalDataSource create(Ref ref) {
    return catalogLocalDataSource(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(CatalogLocalDataSource value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<CatalogLocalDataSource>(value),
    );
  }
}

String _$catalogLocalDataSourceHash() =>
    r'e5f5c2fa6ba6720ee4996df98628199489dc8fbe';

/// Provides the catalog repository used by catalog-facing use cases.

@ProviderFor(catalogRepository)
final catalogRepositoryProvider = CatalogRepositoryProvider._();

/// Provides the catalog repository used by catalog-facing use cases.

final class CatalogRepositoryProvider
    extends
        $FunctionalProvider<
          CatalogRepository,
          CatalogRepository,
          CatalogRepository
        >
    with $Provider<CatalogRepository> {
  /// Provides the catalog repository used by catalog-facing use cases.
  CatalogRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'catalogRepositoryProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$catalogRepositoryHash();

  @$internal
  @override
  $ProviderElement<CatalogRepository> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  CatalogRepository create(Ref ref) {
    return catalogRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(CatalogRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<CatalogRepository>(value),
    );
  }
}

String _$catalogRepositoryHash() => r'beaac6b7bd25bde352a8260b2c60703c4bc6a2d0';

/// Use case that inserts deterministic demo products when the database is new.

@ProviderFor(ensureCatalogSeededUseCase)
final ensureCatalogSeededUseCaseProvider =
    EnsureCatalogSeededUseCaseProvider._();

/// Use case that inserts deterministic demo products when the database is new.

final class EnsureCatalogSeededUseCaseProvider
    extends
        $FunctionalProvider<
          EnsureCatalogSeeded,
          EnsureCatalogSeeded,
          EnsureCatalogSeeded
        >
    with $Provider<EnsureCatalogSeeded> {
  /// Use case that inserts deterministic demo products when the database is new.
  EnsureCatalogSeededUseCaseProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'ensureCatalogSeededUseCaseProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$ensureCatalogSeededUseCaseHash();

  @$internal
  @override
  $ProviderElement<EnsureCatalogSeeded> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  EnsureCatalogSeeded create(Ref ref) {
    return ensureCatalogSeededUseCase(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(EnsureCatalogSeeded value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<EnsureCatalogSeeded>(value),
    );
  }
}

String _$ensureCatalogSeededUseCaseHash() =>
    r'eb602e893cb2202163f7d9f29e090dbb3cb8aa59';

/// Use case for paginated catalog reads.

@ProviderFor(readCatalogProductsPageUseCase)
final readCatalogProductsPageUseCaseProvider =
    ReadCatalogProductsPageUseCaseProvider._();

/// Use case for paginated catalog reads.

final class ReadCatalogProductsPageUseCaseProvider
    extends
        $FunctionalProvider<
          ReadCatalogProductsPage,
          ReadCatalogProductsPage,
          ReadCatalogProductsPage
        >
    with $Provider<ReadCatalogProductsPage> {
  /// Use case for paginated catalog reads.
  ReadCatalogProductsPageUseCaseProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'readCatalogProductsPageUseCaseProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$readCatalogProductsPageUseCaseHash();

  @$internal
  @override
  $ProviderElement<ReadCatalogProductsPage> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  ReadCatalogProductsPage create(Ref ref) {
    return readCatalogProductsPageUseCase(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ReadCatalogProductsPage value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ReadCatalogProductsPage>(value),
    );
  }
}

String _$readCatalogProductsPageUseCaseHash() =>
    r'18d435d7f5c395d9c318810e552a53a01978bd0f';

/// Use case for lightweight catalog counts used by UI badges and startup.

@ProviderFor(countCatalogProductsUseCase)
final countCatalogProductsUseCaseProvider =
    CountCatalogProductsUseCaseProvider._();

/// Use case for lightweight catalog counts used by UI badges and startup.

final class CountCatalogProductsUseCaseProvider
    extends
        $FunctionalProvider<
          CountCatalogProducts,
          CountCatalogProducts,
          CountCatalogProducts
        >
    with $Provider<CountCatalogProducts> {
  /// Use case for lightweight catalog counts used by UI badges and startup.
  CountCatalogProductsUseCaseProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'countCatalogProductsUseCaseProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$countCatalogProductsUseCaseHash();

  @$internal
  @override
  $ProviderElement<CountCatalogProducts> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  CountCatalogProducts create(Ref ref) {
    return countCatalogProductsUseCase(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(CountCatalogProducts value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<CountCatalogProducts>(value),
    );
  }
}

String _$countCatalogProductsUseCaseHash() =>
    r'e9095c474806fa98202cf2d200039bcf3e8df401';
