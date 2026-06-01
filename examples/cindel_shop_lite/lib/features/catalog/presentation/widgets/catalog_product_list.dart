import 'package:cindel_shop_lite/features/catalog/presentation/providers/catalog_providers.dart';
import 'package:cindel_shop_lite/features/catalog/presentation/utils/catalog_messages.dart';
import 'package:cindel_shop_lite/features/catalog/presentation/widgets/catalog_error.dart';
import 'package:cindel_shop_lite/features/catalog/presentation/widgets/product_card.dart';
import 'package:cindel_shop_lite/features/shared/animations/fade_slide_animation.dart';
import 'package:cindel_shop_lite/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class CatalogProductList extends HookWidget {
  const CatalogProductList({
    required this.products,
    required this.onLoadMore,
    super.key,
  });

  final AsyncValue<CatalogProductsPage> products;
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context) {
    final scrollController = useScrollController();

    useEffect(
      () {
        void onScroll() {
          if (!scrollController.hasClients) {
            return;
          }

          final position = scrollController.position;
          if (position.pixels >= position.maxScrollExtent * 0.9) {
            onLoadMore();
          }
        }

        scrollController.addListener(onScroll);
        return () => scrollController.removeListener(onScroll);
      },
      [scrollController, onLoadMore],
    );

    return products.when(
      data: (items) {
        if (items.products.isEmpty) {
          return const _EmptyCatalog();
        }

        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1120),
            child: GridView.builder(
              controller: scrollController,
              itemCount: items.products.length + (items.isLoadingMore ? 1 : 0),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 420,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                mainAxisExtent: 240,
              ),
              itemBuilder: (context, index) {
                if (index >= items.products.length) {
                  return const Center(child: CircularProgressIndicator());
                }
                return FadeSlideAnimation(
                  key: ValueKey(items.products[index].dbId),
                  begin: 0.2,
                  delay: Duration(milliseconds: index * 50),
                  child: ProductCard(product: items.products[index]),
                );
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
