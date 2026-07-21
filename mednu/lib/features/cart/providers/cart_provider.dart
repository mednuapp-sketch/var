import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/cart_item.dart';

class CartNotifier extends StateNotifier<List<CartItem>> {
  CartNotifier() : super([]);

  int _idCounter = 0;
  String _nextId() => '${DateTime.now().microsecondsSinceEpoch}_${_idCounter++}';

  void addItem({
    required String type,
    required String serviceName,
    required Color themeColor,
    required int unitAmount,
    int quantity = 1,
    Map<String, dynamic> serviceDetails = const {},
  }) {
    state = [
      ...state,
      CartItem(
        id: _nextId(),
        type: type,
        serviceName: serviceName,
        themeColor: themeColor,
        unitAmount: unitAmount,
        quantity: quantity,
        serviceDetails: serviceDetails,
      ),
    ];
  }

  void removeItem(String id) {
    state = state.where((i) => i.id != id).toList();
  }

  void incrementQty(String id) {
    state = [
      for (final i in state)
        if (i.id == id) i.copyWith(quantity: i.quantity + 1) else i,
    ];
  }

  void decrementQty(String id) {
    state = [
      for (final i in state)
        if (i.id == id)
          if (i.quantity > 1) i.copyWith(quantity: i.quantity - 1) else i
        else
          i,
    ];
  }

  void clear() => state = [];
}

final cartProvider = StateNotifierProvider<CartNotifier, List<CartItem>>(
  (ref) => CartNotifier(),
);

final cartCountProvider = Provider<int>((ref) {
  return ref.watch(cartProvider).fold<int>(0, (s, i) => s + i.quantity);
});

final cartTotalProvider = Provider<int>((ref) {
  return ref.watch(cartProvider).fold<int>(0, (s, i) => s + i.totalAmount);
});
