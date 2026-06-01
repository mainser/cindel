import 'package:cindel_shop_lite/features/catalog/presentation/providers/catalog_providers.dart';
import 'package:cindel_shop_lite/features/catalog/presentation/utils/catalog_messages.dart';
import 'package:cindel_shop_lite/features/catalog/presentation/widgets/catalog_appbar.dart';
import 'package:cindel_shop_lite/features/catalog/presentation/widgets/catalog_error.dart';
import 'package:cindel_shop_lite/features/catalog/presentation/widgets/catalog_product_list.dart';
import 'package:cindel_shop_lite/features/shared/widgets/error_handling_widget.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class CatalogPage extends ConsumerWidget {
  const CatalogPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final products = ref.watch(catalogProductsProvider);
    final startup = ref.watch(catalogStartupProvider);

    return ErrorHandlingWidget<dynamic>(
      providers: [catalogProductsProvider, catalogStartupProvider],
      child: Scaffold(
        appBar: const CatalogAppbar(),
        body: SafeArea(
          child: startup.when(
            data: (_) => CatalogProductList(products: products),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => CatalogError(
              message: catalogErrorMessage(error),
            ),
          ),
        ),
      ),
    );
  }
}
