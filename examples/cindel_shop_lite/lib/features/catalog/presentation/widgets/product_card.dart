import 'package:cindel_shop_lite/features/catalog/domain/entities/product.dart';
import 'package:cindel_shop_lite/l10n/l10n.dart';
import 'package:flutter/material.dart';

class ProductCard extends StatelessWidget {
  const ProductCard({required this.product, this.onAddToCart, super.key});

  final Product product;
  final VoidCallback? onAddToCart;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final stockColor = product.stock == 0
        ? colorScheme.error
        : product.stock < 8
        ? colorScheme.tertiary
        : colorScheme.primary;

    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    product.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.titleMedium,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _formatPrice(product.priceCents),
                  style: textTheme.titleMedium?.copyWith(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              product.description,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: textTheme.bodyMedium,
            ),
            const Spacer(),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _SmallChip(label: product.category),
                for (final tag in product.tags.take(2)) _SmallChip(label: tag),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.qr_code_2, size: 18, color: colorScheme.outline),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    product.sku,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodySmall,
                  ),
                ),
                Icon(Icons.inventory_2_outlined, size: 18, color: stockColor),
                const SizedBox(width: 6),
                Text(
                  product.stock == 0
                      ? l10n.out.toLowerCase()
                      : '${product.stock} ${l10n.left}',
                  style: textTheme.bodySmall?.copyWith(color: stockColor),
                ),
              ],
            ),
            if (onAddToCart != null) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: product.stock == 0 ? null : onAddToCart,
                  icon: const Icon(Icons.add_shopping_cart),
                  label: Text(l10n.add_to_cart),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

final class _SmallChip extends StatelessWidget {
  const _SmallChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text(label.toLowerCase()),
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
    );
  }
}

String _formatPrice(int cents) {
  return '\$${(cents / 100).toStringAsFixed(2)}';
}
