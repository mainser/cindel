import 'package:cindel_shop_lite/features/shopping/domain/entities/shopping_cart.dart';

// The demo keeps a repository boundary even while checkout has one operation.
// ignore: one_member_abstracts
abstract interface class ShoppingRepository {
  Future<void> checkout(List<CartItem> items);
}
