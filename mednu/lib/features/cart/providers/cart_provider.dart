import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/cart_item.dart';

class CartNotifier extends StateNotifier<List<CartItem>> {
  CartNotifier() : super([]);

  int _idCounter = 0;
  String _nextId() => '${DateTime.now().microsecondsSinceEpoch}_${_idCounter++}';

  static const _detailsEquality = DeepCollectionEquality();

  void addItem({
    required String type,
    required String serviceName,
    required Color themeColor,
    required int unitAmount,
    int quantity = 1,
    Map<String, dynamic> serviceDetails = const {},
  }) {
    final existingIndex = state.indexWhere((i) =>
        i.type == type &&
        i.serviceName == serviceName &&
        i.unitAmount == unitAmount &&
        _detailsEquality.equals(i.serviceDetails, serviceDetails));

    if (existingIndex != -1) {
      final existing = state[existingIndex];
      state = [
        for (final i in state)
          if (i.id == existing.id)
            i.copyWith(quantity: i.quantity + quantity)
          else
            i,
      ];
      return;
    }

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

  /// Vendor identity for cart-lock purposes. Only diagnostics (lab) and
  /// medicine (pharmacy) items are vendor-scoped; everything else (caregivers,
  /// physio, equipment, care_assistant) stays freely mixable, as today.
  String? _vendorKeyFor(String type, Map<String, dynamic> details) {
    if (type == 'diagnostics') return 'lab:${details['sourceLabId'] ?? 'direct'}';
    if (type == 'medicine') return 'pharmacy:${details['sourcePharmacyId'] ?? 'direct'}';
    return null;
  }

  /// Returns a conflict if adding a [type] item from [vendorKey] would mix
  /// vendors within that type (e.g. two different labs' tests in the cart at
  /// once). Callers should check this before [addItem] and, on conflict,
  /// confirm with the user before calling [clearType] then [addItem].
  CartVendorConflict? conflictFor({required String type, required String vendorKey}) {
    final existing = state
        .where((i) => i.type == type)
        .firstWhereOrNull((i) => _vendorKeyFor(i.type, i.serviceDetails) != vendorKey);
    if (existing == null) return null;
    return CartVendorConflict(
      existingVendorName: (existing.serviceDetails['labName'] ??
          existing.serviceDetails['pharmacyName'] ??
          'another provider') as String,
    );
  }

  void clearType(String type) => state = state.where((i) => i.type != type).toList();
}

class CartVendorConflict {
  final String existingVendorName;
  const CartVendorConflict({required this.existingVendorName});
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
