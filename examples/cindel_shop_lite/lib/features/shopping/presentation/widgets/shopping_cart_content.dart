import 'package:cindel_shop_lite/features/shared/animations/fade_scale_animation.dart';
import 'package:cindel_shop_lite/features/shopping/domain/entities/shopping_cart.dart';
import 'package:cindel_shop_lite/features/shopping/presentation/widgets/cart_item_tile.dart';
import 'package:cindel_shop_lite/features/shopping/presentation/widgets/checkout_summary.dart';
import 'package:flutter/material.dart';

final class ShoppingCartContent extends StatelessWidget {
  const ShoppingCartContent({
    required this.cart,
    required this.isCheckingOut,
    required this.onIncrement,
    required this.onDecrement,
    required this.onRemove,
    required this.onCheckout,
    super.key,
  });

  final ShoppingCart cart;
  final bool isCheckingOut;
  final ValueChanged<int> onIncrement;
  final ValueChanged<int> onDecrement;
  final ValueChanged<int> onRemove;
  final VoidCallback onCheckout;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 920),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
          child: Column(
            children: [
              Expanded(
                child: ListView.builder(
                  itemCount: cart.items.length,
                  itemBuilder: (context, index) {
                    final item = cart.items[index];
                    return FadeScaleAnimation(
                      delay: Duration(milliseconds: index * 100),
                      child: CartItemTile(
                        item: item,
                        onIncrement: () => onIncrement(item.product.dbId),
                        onDecrement: () => onDecrement(item.product.dbId),
                        onRemove: () => onRemove(item.product.dbId),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              CheckoutSummary(
                cart: cart,
                isCheckingOut: isCheckingOut,
                onCheckout: onCheckout,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
