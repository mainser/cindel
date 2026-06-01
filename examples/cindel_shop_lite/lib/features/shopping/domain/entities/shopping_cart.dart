import 'package:cindel_shop_lite/features/catalog/domain/entities/product.dart';

/// In-memory cart aggregate used before checkout is committed.
final class ShoppingCart {
  const ShoppingCart({required this.items});

  const ShoppingCart.empty() : items = const [];

  final List<CartItem> items;

  bool get isEmpty => items.isEmpty;

  int get itemCount {
    return items.fold(0, (total, item) => total + item.quantity);
  }

  int get subtotalCents {
    return items.fold(0, (total, item) => total + item.lineTotalCents);
  }
}

/// A product selected for checkout with a user-controlled quantity.
final class CartItem {
  const CartItem({required this.product, required this.quantity});

  final Product product;
  final int quantity;

  int get lineTotalCents => product.priceCents * quantity;

  CartItem copyWith({Product? product, int? quantity}) {
    return CartItem(
      product: product ?? this.product,
      quantity: quantity ?? this.quantity,
    );
  }
}
