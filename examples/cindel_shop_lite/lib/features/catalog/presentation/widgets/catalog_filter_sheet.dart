import 'package:cindel_shop_lite/features/catalog/domain/entities/catalog_query.dart';
import 'package:cindel_shop_lite/features/catalog/presentation/providers/catalog_providers.dart';
import 'package:cindel_shop_lite/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

Future<void> showCatalogFilterSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    useSafeArea: true,
    builder: (_) => const CatalogFilterSheet(),
  );
}

class CatalogFilterSheet extends ConsumerWidget {
  const CatalogFilterSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;

    final query = ref.watch(catalogQueryControllerProvider);
    final controller = ref.read(catalogQueryControllerProvider.notifier);

    return DefaultTabController(
      length: 3,
      child: SizedBox(
        height: 500,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.filters,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      controller
                        ..setCategory('All')
                        ..setInStockOnly(value: false)
                        ..setSort(CatalogSort.newest);
                    },
                    child: Text(l10n.reset),
                  ),
                ],
              ),
            ),
            TabBar(
              tabs: [
                _FilterTab(
                  icon: Icons.category_outlined,
                  label: l10n.category,
                ),
                _FilterTab(icon: Icons.inventory_outlined, label: l10n.stock),
                _FilterTab(icon: Icons.sort, label: l10n.sort),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _CategoryTab(
                    selectedCategory: query.category,
                    onChanged: controller.setCategory,
                  ),
                  _StockTab(
                    inStockOnly: query.inStockOnly,
                    onChanged: (value) =>
                        controller.setInStockOnly(value: value),
                  ),
                  _SortTab(
                    selectedSort: query.sort,
                    onChanged: controller.setSort,
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

class _FilterTab extends StatelessWidget {
  const _FilterTab({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Tab(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 8),
          Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }
}

const _categories = [
  'All',
  'Accessories',
  'Audio',
  'Desk',
  'Kitchen',
  'Outdoor',
];

class _CategoryTab extends StatelessWidget {
  const _CategoryTab({
    required this.selectedCategory,
    required this.onChanged,
  });

  final String selectedCategory;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _categories.length,
      itemBuilder: (context, index) {
        final category = _categories[index];
        final selected = category == selectedCategory;
        return ListTile(
          title: Text(_categoryLabel(context.l10n, category)),
          trailing: selected ? const Icon(Icons.check) : null,
          selected: selected,
          onTap: () => onChanged(category),
        );
      },
    );
  }
}

class _StockTab extends StatelessWidget {
  const _StockTab({
    required this.inStockOnly,
    required this.onChanged,
  });

  final bool inStockOnly;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        SwitchListTile(
          value: inStockOnly,
          secondary: const Icon(Icons.inventory_2_outlined),
          title: Text(context.l10n.in_stock_only),
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _SortTab extends StatelessWidget {
  const _SortTab({required this.selectedSort, required this.onChanged});

  final CatalogSort selectedSort;
  final ValueChanged<CatalogSort> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        for (final option in CatalogSort.values)
          ListTile(
            title: Text(_sortLabel(l10n, option)),
            trailing: option == selectedSort ? const Icon(Icons.check) : null,
            selected: option == selectedSort,
            onTap: () => onChanged(option),
          ),
      ],
    );
  }
}

String _categoryLabel(AppLocalizations l10n, String category) {
  if (category == 'All') {
    return l10n.all_categories;
  }
  return category;
}

String _sortLabel(AppLocalizations l10n, CatalogSort sort) {
  return switch (sort) {
    CatalogSort.newest => l10n.newest_first,
    CatalogSort.nameAsc => l10n.name_a_z,
    CatalogSort.priceAsc => l10n.price_low_high,
    CatalogSort.priceDesc => l10n.price_high_low,
    CatalogSort.stockAsc => l10n.low_stock_first,
  };
}
