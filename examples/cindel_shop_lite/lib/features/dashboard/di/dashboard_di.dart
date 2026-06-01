import 'package:cindel_shop_lite/features/catalog/di/catalog_di.dart';
import 'package:cindel_shop_lite/features/dashboard/data/datasources/dashboard_catalog_data_source.dart';
import 'package:cindel_shop_lite/features/dashboard/data/repositories/cindel_dashboard_repository.dart';
import 'package:cindel_shop_lite/features/dashboard/domain/repositories/dashboard_repository.dart';
import 'package:cindel_shop_lite/features/dashboard/domain/usecases/read_dashboard_metrics.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'dashboard_di.g.dart';

/// Dashboard data source that derives metrics from the shared catalog database.
@riverpod
DashboardCatalogDataSource dashboardCatalogDataSource(Ref ref) {
  return DashboardCatalogDataSource(ref.watch(catalogDatabaseProvider.future));
}

/// Repository boundary for dashboard metrics.
@riverpod
DashboardRepository dashboardRepository(Ref ref) {
  return CindelDashboardRepository(
    ref.watch(dashboardCatalogDataSourceProvider),
  );
}

/// Use case for reading the current dashboard inventory snapshot.
@riverpod
ReadDashboardMetrics readDashboardMetricsUseCase(Ref ref) {
  return ReadDashboardMetrics(ref.watch(dashboardRepositoryProvider));
}
