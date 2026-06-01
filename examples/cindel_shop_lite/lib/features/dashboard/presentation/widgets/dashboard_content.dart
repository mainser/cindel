import 'package:cindel_shop_lite/features/dashboard/domain/entities/dashboard_metrics.dart';
import 'package:cindel_shop_lite/features/dashboard/presentation/widgets/dashboard_metric_tile.dart';
import 'package:cindel_shop_lite/features/dashboard/presentation/widgets/dashboard_section.dart';
import 'package:cindel_shop_lite/features/dashboard/presentation/widgets/low_stock_product_tile.dart';
import 'package:cindel_shop_lite/features/shared/animations/fade_scale_animation.dart';
import 'package:flutter/material.dart';

class DashboardContent extends StatelessWidget {
  const DashboardContent({required this.metrics, super.key});

  final DashboardMetrics metrics;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1120),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            // Metrics header
            FadeScaleAnimation(
              delay: const Duration(milliseconds: 200),
              child: _DashboardHeader(metrics: metrics),
            ),

            // Metrics grid
            const SizedBox(height: 16),
            FadeScaleAnimation(
              delay: const Duration(milliseconds: 300),
              child: _MetricGrid(metrics: metrics),
            ),

            // Category stock section
            const SizedBox(height: 16),
            FadeScaleAnimation(
              delay: const Duration(milliseconds: 400),
              child: _CategoryStockSection(metrics: metrics),
            ),

            // Critical stock section
            const SizedBox(height: 16),
            FadeScaleAnimation(
              delay: const Duration(milliseconds: 500),
              child: _CriticalStockSection(metrics: metrics),
            ),
          ],
        ),
      ),
    );
  }
}

final class _DashboardHeader extends StatelessWidget {
  const _DashboardHeader({required this.metrics});

  final DashboardMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Icon(
                  Icons.dashboard_outlined,
                  size: 32,
                  color: colorScheme.onPrimaryContainer,
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Store overview',
                    style: textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${metrics.totalProducts} products across '
                    '${metrics.categoryCount} categories',
                    style: textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onPrimaryContainer,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final class _MetricGrid extends StatelessWidget {
  const _MetricGrid({required this.metrics});

  final DashboardMetrics metrics;

  @override
  Widget build(BuildContext context) {
    return GridView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 270,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        mainAxisExtent: 116,
      ),
      children: [
        DashboardMetricTile(
          icon: Icons.inventory_2_outlined,
          label: 'Products',
          value: '${metrics.totalProducts}',
        ),
        DashboardMetricTile(
          icon: Icons.category_outlined,
          label: 'Categories',
          value: '${metrics.categoryCount}',
        ),
        DashboardMetricTile(
          icon: Icons.warning_amber_outlined,
          label: 'Low stock',
          value: '${metrics.lowStockProducts}',
          supportingText: '${metrics.outOfStockProducts} out',
        ),
        DashboardMetricTile(
          icon: Icons.payments_outlined,
          label: 'Inventory value',
          value: _formatPrice(metrics.inventoryValueCents),
        ),
      ],
    );
  }
}

final class _CategoryStockSection extends StatelessWidget {
  const _CategoryStockSection({required this.metrics});

  final DashboardMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final maxStock = metrics.categories.fold<int>(
      0,
      (max, category) => category.stock > max ? category.stock : max,
    );

    return DashboardSection(
      title: 'Stock by category',
      icon: Icons.category_outlined,
      child: metrics.categories.isEmpty
          ? const _EmptyState(message: 'There are no categories yet.')
          : Column(
              children: [
                for (final category in metrics.categories)
                  _CategoryRow(category: category, maxStock: maxStock),
              ],
            ),
    );
  }
}

final class _CategoryRow extends StatelessWidget {
  const _CategoryRow({required this.category, required this.maxStock});

  final CategoryMetric category;
  final int maxStock;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    final progress = maxStock == 0 ? 0.0 : category.stock / maxStock;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(category.name, style: textTheme.bodyMedium),
          ),
          Expanded(
            flex: 4,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 8,
                backgroundColor: colorScheme.surfaceContainerHighest,
              ),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 72,
            child: Text(
              '${category.stock} units',
              textAlign: TextAlign.end,
              style: textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

final class _CriticalStockSection extends StatelessWidget {
  const _CriticalStockSection({required this.metrics});

  final DashboardMetrics metrics;

  @override
  Widget build(BuildContext context) {
    return DashboardSection(
      title: 'Critical stock',
      icon: Icons.inventory_outlined,
      child: metrics.criticalProducts.isEmpty
          ? const _EmptyState(message: 'All products have healthy stock.')
          : Column(
              children: [
                for (final product in metrics.criticalProducts)
                  LowStockProductTile(product: product),
              ],
            ),
    );
  }
}

final class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: Text(
          message,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

String _formatPrice(int cents) {
  return '\$${(cents / 100).toStringAsFixed(2)}';
}
