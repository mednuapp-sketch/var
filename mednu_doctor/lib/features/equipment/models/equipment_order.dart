import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';

/// Vendor-side order lifecycle, stored verbatim in `equipment_orders.status`.
///
///   pending -> accepted -> out_for_delivery -> delivered -> (rent) returned
///   pending -> rejected            (vendor declines; patient is refunded)
///   accepted/out_for_delivery -> cancelled (vendor can't fulfil; refunded)
///
/// Mirrors `_validEquipmentTransition` in firestore.rules.
enum EquipmentOrderStatus {
  pending('pending', 'New', AppColors.warning),
  accepted('accepted', 'Accepted', AppColors.info),
  outForDelivery('out_for_delivery', 'Out for delivery', AppColors.primary),
  delivered('delivered', 'Delivered', AppColors.success),
  returned('returned', 'Returned', AppColors.success),
  rejected('rejected', 'Declined', AppColors.error),
  cancelled('cancelled', 'Cancelled', AppColors.error);

  final String value;
  final String label;
  final Color color;
  const EquipmentOrderStatus(this.value, this.label, this.color);

  static EquipmentOrderStatus fromValue(String? raw) {
    for (final s in EquipmentOrderStatus.values) {
      if (s.value == raw) return s;
    }
    return EquipmentOrderStatus.pending;
  }

  /// Still needs the vendor's attention.
  bool get isActive => this == pending || this == accepted || this == outForDelivery;
}

class EquipmentOrder {
  final String id;
  final String vendorId;
  final String patientId;
  final String patientName;
  final String patientPhone;
  final String deliveryAddress;
  final String? itemId;
  final String itemName;
  final String mode; // 'rent' | 'buy'
  final int rentalDays;
  final num pricePerDay;
  final int quantity;
  final num deposit;
  final num totalAmount;
  final String preferredDate;
  final String preferredTime;
  final String notes;
  final EquipmentOrderStatus status;
  final bool stockHeld;
  final String? cancelReason;
  final String? cancelledBy;
  final DateTime createdAt;
  final DateTime updatedAt;

  const EquipmentOrder({
    required this.id,
    required this.vendorId,
    required this.patientId,
    required this.patientName,
    required this.patientPhone,
    required this.deliveryAddress,
    required this.itemId,
    required this.itemName,
    required this.mode,
    required this.rentalDays,
    required this.pricePerDay,
    required this.quantity,
    required this.deposit,
    required this.totalAmount,
    required this.preferredDate,
    required this.preferredTime,
    required this.notes,
    required this.status,
    required this.stockHeld,
    required this.cancelReason,
    required this.cancelledBy,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isRent => mode == 'rent';

  /// "Rent · 3 days" / "Buy"
  String get modeLabel => isRent ? 'Rent · $rentalDays day${rentalDays == 1 ? '' : 's'}' : 'Buy';

  factory EquipmentOrder.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    DateTime ts(Object? v) => v is Timestamp ? v.toDate() : DateTime.now();
    return EquipmentOrder(
      id: doc.id,
      vendorId: (d['vendorId'] as String?) ?? '',
      patientId: (d['patientId'] as String?) ?? '',
      patientName: (d['patientName'] as String?) ?? 'Patient',
      patientPhone: (d['patientPhone'] as String?) ?? '',
      deliveryAddress: (d['deliveryAddress'] as String?) ?? '',
      itemId: d['itemId'] as String?,
      itemName: (d['itemName'] as String?) ?? 'Equipment',
      mode: (d['mode'] as String?) ?? 'buy',
      rentalDays: (d['rentalDays'] as num?)?.toInt() ?? 0,
      pricePerDay: (d['pricePerDay'] as num?) ?? 0,
      quantity: (d['quantity'] as num?)?.toInt() ?? 1,
      deposit: (d['deposit'] as num?) ?? 0,
      totalAmount: (d['totalAmount'] as num?) ?? 0,
      preferredDate: (d['preferredDate'] as String?) ?? '',
      preferredTime: (d['preferredTime'] as String?) ?? '',
      notes: (d['notes'] as String?) ?? '',
      status: EquipmentOrderStatus.fromValue(d['status'] as String?),
      stockHeld: (d['stockHeld'] as bool?) ?? false,
      cancelReason: d['cancelReason'] as String?,
      cancelledBy: d['cancelledBy'] as String?,
      createdAt: ts(d['createdAt']),
      updatedAt: ts(d['updatedAt']),
    );
  }
}
