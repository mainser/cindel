import 'package:cindel/cindel.dart';

import 'category.dart';
import 'product_details.dart';

part 'product.g.dart';

@Collection(
  name: 'products',
  indexes: [
    CompositeIndex(['active', 'stock']),
  ],
)
class Product {
  Id dbId = autoIncrement;

  @Index(unique: true, replace: true, caseSensitive: false)
  late String sku;

  @Index(caseSensitive: false)
  late String name;

  @Index(type: CindelIndexType.words, caseSensitive: false)
  String? description;

  @index
  double price = 0;

  @index
  int stock = 0;

  bool active = true;

  @index
  DateTime createdAt = DateTime.fromMicrosecondsSinceEpoch(0, isUtc: true);

  @Index(type: CindelIndexType.multiEntry, caseSensitive: false)
  List<String> tags = const [];

  ProductDetails? details;

  final category = CindelLink<Category>();
}
