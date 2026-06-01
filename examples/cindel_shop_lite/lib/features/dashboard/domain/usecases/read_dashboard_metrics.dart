import 'package:cindel_shop_lite/features/dashboard/domain/entities/dashboard_metrics.dart';
import 'package:cindel_shop_lite/features/dashboard/domain/repositories/dashboard_repository.dart';

final class ReadDashboardMetrics {
  const ReadDashboardMetrics(this._repository);

  final DashboardRepository _repository;

  Future<DashboardMetrics> call() {
    return _repository.readMetrics();
  }
}
