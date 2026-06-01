import 'package:cindel_shop_lite/features/catalog/domain/entities/product.dart';
import 'package:flutter/material.dart';

class LowStockProductTile extends StatelessWidget {
  const LowStockProductTile({required this.product, super.key});

  final Product product;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final stockColor = product.stock == 0
        ? colorScheme.error
        : colorScheme.tertiary;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Icon(Icons.inventory_2_outlined, color: stockColor),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(product.sku, style: textTheme.bodySmall),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            product.stock == 0 ? 'Out' : '${product.stock} left',
            style: textTheme.bodyMedium?.copyWith(
              color: stockColor,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
