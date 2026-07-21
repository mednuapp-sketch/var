import 'package:flutter/material.dart';

/// A single line item in the universal cart. Covers every non-consultation,
/// non-ambulance service: medicine, diagnostics, caregivers, care_assistant,
/// physiotherapy, equipment_hiring.
class CartItem {
  final String id;
  final String type;
  final String serviceName;
  final Color themeColor;
  final int unitAmount;
  final int quantity;
  final Map<String, dynamic> serviceDetails;

  const CartItem({
    required this.id,
    required this.type,
    required this.serviceName,
    required this.themeColor,
    required this.unitAmount,
    this.quantity = 1,
    this.serviceDetails = const {},
  });

  int get totalAmount => unitAmount * quantity;

  CartItem copyWith({int? quantity}) => CartItem(
        id: id,
        type: type,
        serviceName: serviceName,
        themeColor: themeColor,
        unitAmount: unitAmount,
        quantity: quantity ?? this.quantity,
        serviceDetails: serviceDetails,
      );
}
