// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'dashboard_di.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(dashboardCatalogDataSource)
final dashboardCatalogDataSourceProvider =
    DashboardCatalogDataSourceProvider._();

final class DashboardCatalogDataSourceProvider
    extends
        $FunctionalProvider<
          DashboardCatalogDataSource,
          DashboardCatalogDataSource,
          DashboardCatalogDataSource
        >
    with $Provider<DashboardCatalogDataSource> {
  DashboardCatalogDataSourceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'dashboardCatalogDataSourceProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$dashboardCatalogDataSourceHash();

  @$internal
  @override
  $ProviderElement<DashboardCatalogDataSource> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  DashboardCatalogDataSource create(Ref ref) {
    return dashboardCatalogDataSource(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(DashboardCatalogDataSource value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<DashboardCatalogDataSource>(value),
    );
  }
}

String _$dashboardCatalogDataSourceHash() =>
    r'105cdb306ef19dc1bef894fe620c708b584e51d1';

@ProviderFor(dashboardRepository)
final dashboardRepositoryProvider = DashboardRepositoryProvider._();

final class DashboardRepositoryProvider
    extends
        $FunctionalProvider<
          DashboardRepository,
          DashboardRepository,
          DashboardRepository
        >
    with $Provider<DashboardRepository> {
  DashboardRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'dashboardRepositoryProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$dashboardRepositoryHash();

  @$internal
  @override
  $ProviderElement<DashboardRepository> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  DashboardRepository create(Ref ref) {
    return dashboardRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(DashboardRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<DashboardRepository>(value),
    );
  }
}

String _$dashboardRepositoryHash() =>
    r'6aca2b6c24e058ba03ecf2748446dafea7036ec6';

@ProviderFor(readDashboardMetricsUseCase)
final readDashboardMetricsUseCaseProvider =
    ReadDashboardMetricsUseCaseProvider._();

final class ReadDashboardMetricsUseCaseProvider
    extends
        $FunctionalProvider<
          ReadDashboardMetrics,
          ReadDashboardMetrics,
          ReadDashboardMetrics
        >
    with $Provider<ReadDashboardMetrics> {
  ReadDashboardMetricsUseCaseProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'readDashboardMetricsUseCaseProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$readDashboardMetricsUseCaseHash();

  @$internal
  @override
  $ProviderElement<ReadDashboardMetrics> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  ReadDashboardMetrics create(Ref ref) {
    return readDashboardMetricsUseCase(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ReadDashboardMetrics value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ReadDashboardMetrics>(value),
    );
  }
}

String _$readDashboardMetricsUseCaseHash() =>
    r'09ad5d06a093e00d675bf70e04a67aba3ff713d7';
