import 'package:cindel_shop_lite/features/catalog/presentation/providers/catalog_providers.dart';
import 'package:cindel_shop_lite/features/catalog/presentation/utils/catalog_messages.dart';
import 'package:cindel_shop_lite/features/catalog/presentation/widgets/catalog_appbar.dart';
import 'package:cindel_shop_lite/features/catalog/presentation/widgets/catalog_error.dart';
import 'package:cindel_shop_lite/features/catalog/presentation/widgets/catalog_product_list.dart';
import 'package:cindel_shop_lite/features/shared/widgets/error_handling_widget.dart';
import 'package:cindel_shop_lite/features/shared/widgets/snack_messages.dart';
import 'package:cindel_shop_lite/features/shopping/presentation/providers/shopping_providers.dart';
import 'package:cindel_shop_lite/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class CatalogPage extends ConsumerWidget {
  const CatalogPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final products = ref.watch(catalogProductsControllerProvider);
    final startup = ref.watch(catalogStartupProvider);

    return ErrorHandlingWidget<dynamic>(
      providers: [catalogProductsControllerProvider, catalogStartupProvider],
      child: Scaffold(
        appBar: const CatalogAppbar(),
        body: SafeArea(
          child: startup.when(
            data: (_) => CatalogProductList(
              products: products,
              onLoadMore: () => ref
                  .read(catalogProductsControllerProvider.notifier)
                  .loadNextPage(),
              onAddToCart: (product) {
                final added = ref
                    .read(shoppingCartControllerProvider.notifier)
                    .addProduct(product);
                if (!added) {
                  SnackMessage.of(context).warning(
                    message: l10n.product_no_more_stock(product.name),
                  );
                  return;
                }
                SnackMessage.of(
                  context,
                ).success(message: l10n.product_added_to_cart(product.name));
              },
            ),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => CatalogError(
              message: catalogErrorMessage(error, l10n),
            ),
          ),
        ),
      ),
    );
  }
}
