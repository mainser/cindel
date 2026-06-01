// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'catalog_di.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(catalogDatabase)
final catalogDatabaseProvider = CatalogDatabaseProvider._();

final class CatalogDatabaseProvider
    extends
        $FunctionalProvider<
          AsyncValue<CindelDatabase>,
          CindelDatabase,
          FutureOr<CindelDatabase>
        >
    with $FutureModifier<CindelDatabase>, $FutureProvider<CindelDatabase> {
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

String _$catalogDatabaseHash() => r'f187e6859a6632ed7786abf975d4945dd56b69db';

@ProviderFor(catalogLocalDataSource)
final catalogLocalDataSourceProvider = CatalogLocalDataSourceProvider._();

final class CatalogLocalDataSourceProvider
    extends
        $FunctionalProvider<
          CatalogLocalDataSource,
          CatalogLocalDataSource,
          CatalogLocalDataSource
        >
    with $Provider<CatalogLocalDataSource> {
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

@ProviderFor(catalogRepository)
final catalogRepositoryProvider = CatalogRepositoryProvider._();

final class CatalogRepositoryProvider
    extends
        $FunctionalProvider<
          CatalogRepository,
          CatalogRepository,
          CatalogRepository
        >
    with $Provider<CatalogRepository> {
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

@ProviderFor(ensureCatalogSeededUseCase)
final ensureCatalogSeededUseCaseProvider =
    EnsureCatalogSeededUseCaseProvider._();

final class EnsureCatalogSeededUseCaseProvider
    extends
        $FunctionalProvider<
          EnsureCatalogSeeded,
          EnsureCatalogSeeded,
          EnsureCatalogSeeded
        >
    with $Provider<EnsureCatalogSeeded> {
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

@ProviderFor(readCatalogProductsPageUseCase)
final readCatalogProductsPageUseCaseProvider =
    ReadCatalogProductsPageUseCaseProvider._();

final class ReadCatalogProductsPageUseCaseProvider
    extends
        $FunctionalProvider<
          ReadCatalogProductsPage,
          ReadCatalogProductsPage,
          ReadCatalogProductsPage
        >
    with $Provider<ReadCatalogProductsPage> {
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

@ProviderFor(countCatalogProductsUseCase)
final countCatalogProductsUseCaseProvider =
    CountCatalogProductsUseCaseProvider._();

final class CountCatalogProductsUseCaseProvider
    extends
        $FunctionalProvider<
          CountCatalogProducts,
          CountCatalogProducts,
          CountCatalogProducts
        >
    with $Provider<CountCatalogProducts> {
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
