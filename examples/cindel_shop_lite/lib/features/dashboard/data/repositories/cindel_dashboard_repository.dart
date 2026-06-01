import 'package:cindel_shop_lite/features/dashboard/data/datasources/dashboard_catalog_data_source.dart';
import 'package:cindel_shop_lite/features/dashboard/domain/entities/dashboard_metrics.dart';
import 'package:cindel_shop_lite/features/dashboard/domain/repositories/dashboard_repository.dart';

final class CindelDashboardRepository implements DashboardRepository {
  const CindelDashboardRepository(this._dataSource);

  final DashboardCatalogDataSource _dataSource;

  @override
  Future<DashboardMetrics> readMetrics() {
    return _dataSource.readMetrics();
  }
}
