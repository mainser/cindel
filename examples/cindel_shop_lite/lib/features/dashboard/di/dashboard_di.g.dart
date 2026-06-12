// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'dashboard_di.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Dashboard data source that derives metrics from the shared catalog database.

@ProviderFor(dashboardCatalogDataSource)
final dashboardCatalogDataSourceProvider =
    DashboardCatalogDataSourceProvider._();

/// Dashboard data source that derives metrics from the shared catalog database.

final class DashboardCatalogDataSourceProvider
    extends
        $FunctionalProvider<
          DashboardCatalogDataSource,
          DashboardCatalogDataSource,
          DashboardCatalogDataSource
        >
    with $Provider<DashboardCatalogDataSource> {
  /// Dashboard data source that derives metrics from the shared catalog database.
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

/// Repository boundary for dashboard metrics.

@ProviderFor(dashboardRepository)
final dashboardRepositoryProvider = DashboardRepositoryProvider._();

/// Repository boundary for dashboard metrics.

final class DashboardRepositoryProvider
    extends
        $FunctionalProvider<
          DashboardRepository,
          DashboardRepository,
          DashboardRepository
        >
    with $Provider<DashboardRepository> {
  /// Repository boundary for dashboard metrics.
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

/// Use case for reading the current dashboard inventory snapshot.

@ProviderFor(readDashboardMetricsUseCase)
final readDashboardMetricsUseCaseProvider =
    ReadDashboardMetricsUseCaseProvider._();

/// Use case for reading the current dashboard inventory snapshot.

final class ReadDashboardMetricsUseCaseProvider
    extends
        $FunctionalProvider<
          ReadDashboardMetrics,
          ReadDashboardMetrics,
          ReadDashboardMetrics
        >
    with $Provider<ReadDashboardMetrics> {
  /// Use case for reading the current dashboard inventory snapshot.
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
