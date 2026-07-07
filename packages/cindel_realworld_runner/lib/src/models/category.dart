import 'package:cindel/cindel.dart';

import 'product.dart';

part 'category.g.dart';

@Collection(name: 'categories')
class Category {
  Id dbId = autoIncrement;

  @Index(unique: true, replace: true, caseSensitive: false)
  late String slug;

  late String name;

  int sortOrder = 0;

  @Backlink(to: 'category')
  final products = CindelLinks<Product>();
}
