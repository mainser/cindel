import 'package:cindel_shop_lite/features/dashboard/di/dashboard_di.dart';
import 'package:cindel_shop_lite/features/dashboard/domain/entities/dashboard_metrics.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'dashboard_providers.g.dart';

@riverpod
Future<DashboardMetrics> dashboardMetrics(Ref ref) {
  return ref.watch(readDashboardMetricsUseCaseProvider).call();
}
