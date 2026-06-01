import 'package:cindel_shop_lite/features/shopping/domain/entities/shopping_cart.dart';
import 'package:cindel_shop_lite/features/shopping/domain/repositories/shopping_repository.dart';

final class CheckoutCart {
  const CheckoutCart(this._repository);

  final ShoppingRepository _repository;

  Future<void> call(List<CartItem> items) {
    return _repository.checkout(items);
  }
}
