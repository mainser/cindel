import 'package:cindel_shop_lite/features/shared/widgets/snack_messages.dart';
import 'package:cindel_shop_lite/features/shopping/presentation/providers/shopping_providers.dart';
import 'package:cindel_shop_lite/features/shopping/presentation/utils/shopping_messages.dart';
import 'package:cindel_shop_lite/features/shopping/presentation/widgets/empty_cart.dart';
import 'package:cindel_shop_lite/features/shopping/presentation/widgets/shopping_cart_content.dart';
import 'package:cindel_shop_lite/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class ShoppingPage extends ConsumerWidget {
  const ShoppingPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final cart = ref.watch(shoppingCartControllerProvider);
    final checkoutState = ref.watch(checkoutControllerProvider);
    final cartController = ref.read(shoppingCartControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.shopping)),
      body: SafeArea(
        child: cart.isEmpty
            ? const EmptyCart()
            : ShoppingCartContent(
                cart: cart,
                isCheckingOut: checkoutState.isLoading,
                onIncrement: cartController.increment,
                onDecrement: cartController.decrement,
                onRemove: cartController.remove,
                onCheckout: () async {
                  try {
                    await ref
                        .read(checkoutControllerProvider.notifier)
                        .checkout(cart);
                    if (!context.mounted) {
                      return;
                    }
                    SnackMessage.of(
                      context,
                    ).success(message: l10n.checkout_complete_stock_updated);
                  } on Object catch (error) {
                    if (!context.mounted) {
                      return;
                    }
                    SnackMessage.of(
                      context,
                    ).error(message: shoppingErrorMessage(error, l10n));
                  }
                },
              ),
      ),
    );
  }
}
