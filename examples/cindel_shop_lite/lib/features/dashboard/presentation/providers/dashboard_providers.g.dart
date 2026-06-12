// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'dashboard_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(dashboardMetrics)
final dashboardMetricsProvider = DashboardMetricsProvider._();

final class DashboardMetricsProvider
    extends
        $FunctionalProvider<
          AsyncValue<DashboardMetrics>,
          DashboardMetrics,
          FutureOr<DashboardMetrics>
        >
    with $FutureModifier<DashboardMetrics>, $FutureProvider<DashboardMetrics> {
  DashboardMetricsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'dashboardMetricsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$dashboardMetricsHash();

  @$internal
  @override
  $FutureProviderElement<DashboardMetrics> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<DashboardMetrics> create(Ref ref) {
    return dashboardMetrics(ref);
  }
}

String _$dashboardMetricsHash() => r'de23656bc3ed4b3443243691eb0d079158b4d1aa';
