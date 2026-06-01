import 'package:cindel_shop_lite/features/shopping/domain/entities/shopping_cart.dart';
import 'package:cindel_shop_lite/l10n/l10n.dart';
import 'package:flutter/material.dart';

final class CheckoutSummary extends StatelessWidget {
  const CheckoutSummary({
    required this.cart,
    required this.isCheckingOut,
    required this.onCheckout,
    super.key,
  });

  final ShoppingCart cart;
  final bool isCheckingOut;
  final VoidCallback onCheckout;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text(l10n.items, style: theme.textTheme.bodyMedium),
                const Spacer(),
                Text('${cart.itemCount}', style: theme.textTheme.bodyMedium),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  l10n.subtotal,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                Text(
                  _formatPrice(cart.subtotalCents),
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: isCheckingOut ? null : onCheckout,
                icon: isCheckingOut
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.lock_outline),
                label: Text(l10n.simulate_checkout),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _formatPrice(int cents) {
  return '\$${(cents / 100).toStringAsFixed(2)}';
}
