import 'package:cindel_shop_lite/features/catalog/domain/entities/product.dart';

List<Product> buildDemoCatalogProducts() {
  const categories = [
    'Accessories',
    'Audio',
    'Desk',
    'Kitchen',
    'Outdoor',
  ];
  const productTypes = [
    'Wireless Mouse',
    'Mechanical Keyboard',
    'Noise Canceling Headphones',
    'Desk Lamp',
    'Travel Mug',
    'USB-C Hub',
    'Standing Mat',
    'Portable Speaker',
    'Notebook Set',
    'Cable Organizer',
  ];
  const modifiers = [
    'Compact',
    'Pro',
    'Lite',
    'Studio',
    'Everyday',
    'Travel',
    'Premium',
    'Eco',
    'Classic',
    'Smart',
  ];
  const tags = [
    'wireless',
    'office',
    'portable',
    'ergonomic',
    'sale',
    'premium',
    'new',
    'compact',
  ];

  final baseDate = DateTime.utc(2026);
  return List<Product>.generate(100, (index) {
    final category = categories[index % categories.length];
    final type = productTypes[index % productTypes.length];
    final modifier = modifiers[(index * 3) % modifiers.length];
    final name = '$modifier $type';
    final productTags = [
      tags[index % tags.length],
      tags[(index + 3) % tags.length],
      category.toLowerCase(),
    ];
    final description =
        '$name for daily shopping demos with local inventory, fast lookup, '
        'and offline catalog updates.';
    final priceCents = 1299 + ((index * 731) % 18500);
    final stock = index % 11 == 0 ? 0 : 3 + ((index * 7) % 38);

    return Product(
      dbId: index + 1,
      sku: 'SHOP-${(index + 1).toString().padLeft(4, '0')}',
      name: name,
      description: description,
      searchText: '$name $description ${productTags.join(' ')}'.toLowerCase(),
      category: category,
      priceCents: priceCents,
      stock: stock,
      tags: productTags,
      createdAtMicros: baseDate
          .add(Duration(hours: index * 4))
          .microsecondsSinceEpoch,
    );
  }, growable: false);
}
