import 'package:cindel_shop_lite/features/catalog/domain/entities/catalog_query.dart';
import 'package:cindel_shop_lite/features/catalog/presentation/providers/catalog_providers.dart';
import 'package:cindel_shop_lite/features/catalog/presentation/widgets/catalog_filter_sheet.dart';
import 'package:cindel_shop_lite/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class CatalogAppbar extends HookConsumerWidget implements PreferredSizeWidget {
  const CatalogAppbar({super.key});

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight * 2);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;

    final query = ref.watch(catalogQueryControllerProvider);
    final productCount = ref.watch(catalogProductCountProvider);
    final searchController = useTextEditingController(text: query.searchText);
    final hasFilters =
        query.category != 'All' ||
        query.inStockOnly ||
        query.sort != CatalogSort.newest;

    useEffect(
      () {
        if (searchController.text != query.searchText) {
          searchController.text = query.searchText;
        }
        return null;
      },
      [query.searchText],
    );

    Widget searchIcon() => IconButton(
      tooltip: l10n.clear_search,
      icon: const Icon(Icons.close),
      onPressed: () =>
          ref.read(catalogQueryControllerProvider.notifier).clearSearch(),
    );

    return AppBar(
      title: Text(l10n.catalog),
      actions: [
        Center(
          child: productCount.when(
            data: (count) => Chip(
              avatar: const Icon(Icons.inventory_2_outlined, size: 18),
              label: Text('$count'),
              side: BorderSide.none,
            ),
            loading: () => const SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            error: (_, _) => Chip(
              label: Text(l10n.products.toLowerCase()),
              side: BorderSide.none,
            ),
          ),
        ),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: Row(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
                child: TextField(
                  controller: searchController,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: l10n.search_products,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: query.searchText.isEmpty ? null : searchIcon(),
                  ),
                  onChanged: (value) => ref
                      .read(catalogQueryControllerProvider.notifier)
                      .setSearchText(value),
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.filter_list),
              color: hasFilters ? Theme.of(context).colorScheme.primary : null,
              onPressed: () => showCatalogFilterSheet(context),
            ),
          ],
        ),
      ),
    );
  }
}
