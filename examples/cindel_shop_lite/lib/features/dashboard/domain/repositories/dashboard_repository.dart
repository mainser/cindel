import 'package:cindel_shop_lite/features/dashboard/domain/entities/dashboard_metrics.dart';

// The demo keeps the same domain boundary as the catalog feature.
// ignore: one_member_abstracts
abstract interface class DashboardRepository {
  Future<DashboardMetrics> readMetrics();
}
