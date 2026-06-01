import 'package:cindel_shop_lite/features/catalog/domain/entities/product.dart';
import 'package:cindel_shop_lite/features/catalog/presentation/utils/catalog_messages.dart';
import 'package:cindel_shop_lite/features/catalog/presentation/widgets/catalog_error.dart';
import 'package:cindel_shop_lite/features/catalog/presentation/widgets/product_card.dart';
import 'package:cindel_shop_lite/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class CatalogProductList extends StatelessWidget {
  const CatalogProductList({required this.products, super.key});

  final AsyncValue<List<Product>> products;

  @override
  Widget build(BuildContext context) {
    return products.when(
      data: (items) {
        if (items.isEmpty) {
          return const _EmptyCatalog();
        }

        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1120),
            child: GridView.builder(
              itemCount: items.length,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 420,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                mainAxisExtent: 240,
              ),
              itemBuilder: (context, index) {
                return ProductCard(product: items[index]);
              },
            ),
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => CatalogError(message: catalogErrorMessage(error)),
    );
  }
}

final class _EmptyCatalog extends StatelessWidget {
  const _EmptyCatalog();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.search_off,
            size: 48,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 12),
          Text(
            context.l10n.no_products_match_filters,
            style: Theme.of(context).textTheme.bodyLarge,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
