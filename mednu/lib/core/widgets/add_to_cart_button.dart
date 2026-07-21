import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../router/app_router.dart';
import '../../features/cart/providers/cart_provider.dart';

/// Add / increment / decrement control shared by every service screen that
/// feeds the universal cart. Generalized from the medicine screen's
/// original per-file `_ProductCard` counter.
class AddToCartButton extends StatelessWidget {
  final int cartCount;
  final Color color;
  final VoidCallback onAdd;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;

  const AddToCartButton({
    super.key,
    required this.cartCount,
    required this.color,
    required this.onAdd,
    required this.onIncrement,
    required this.onDecrement,
  });

  @override
  Widget build(BuildContext context) {
    if (cartCount == 0) {
      return SizedBox(
        height: 32,
        child: OutlinedButton(
          onPressed: onAdd,
          style: OutlinedButton.styleFrom(
            foregroundColor: color,
            side: BorderSide(color: color),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          child: const Text(
            'Add',
            style: TextStyle(fontFamily: 'Poppins', fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ),
      );
    }
    return Container(
      height: 32,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _stepButton(Icons.remove_rounded, onDecrement),
          SizedBox(
            width: 22,
            child: Text(
              '$cartCount',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'Poppins',
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
          _stepButton(Icons.add_rounded, onIncrement),
        ],
      ),
    );
  }

  Widget _stepButton(IconData icon, VoidCallback onTap) => InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 28,
          height: 32,
          child: Icon(icon, size: 16, color: Colors.white),
        ),
      );
}

/// AppBar action showing the cart icon with a live item-count badge,
/// used by every screen that feeds the universal cart.
class CartBadgeAction extends ConsumerWidget {
  final Color? color;
  const CartBadgeAction({super.key, this.color});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(cartCountProvider);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          icon: Icon(Icons.shopping_cart_rounded, color: color ?? Colors.white),
          onPressed: () => context.push(AppRoutes.cart),
        ),
        if (count > 0)
          Positioned(
            top: 6,
            right: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white, width: 1),
              ),
              child: Text(
                '$count',
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
