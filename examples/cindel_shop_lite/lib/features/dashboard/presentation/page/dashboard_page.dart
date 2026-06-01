import 'package:cindel_shop_lite/features/catalog/presentation/providers/catalog_providers.dart';
import 'package:cindel_shop_lite/features/dashboard/presentation/providers/dashboard_providers.dart';
import 'package:cindel_shop_lite/features/dashboard/presentation/utils/dashboard_messages.dart';
import 'package:cindel_shop_lite/features/dashboard/presentation/widgets/dashboard_content.dart';
import 'package:cindel_shop_lite/features/dashboard/presentation/widgets/dashboard_error.dart';
import 'package:cindel_shop_lite/features/shared/widgets/error_handling_widget.dart';
import 'package:cindel_shop_lite/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final startup = ref.watch(catalogStartupProvider);
    final metrics = ref.watch(dashboardMetricsProvider);

    return ErrorHandlingWidget<dynamic>(
      providers: [catalogStartupProvider, dashboardMetricsProvider],
      child: Scaffold(
        appBar: AppBar(title: Text(l10n.dashboard)),
        body: SafeArea(
          child: startup.when(
            data: (_) => metrics.when(
              data: (data) => DashboardContent(metrics: data),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => DashboardError(
                message: dashboardErrorMessage(error, l10n),
              ),
            ),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => DashboardError(
              message: dashboardErrorMessage(error, l10n),
            ),
          ),
        ),
      ),
    );
  }
}
