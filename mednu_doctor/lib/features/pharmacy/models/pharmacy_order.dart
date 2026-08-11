import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// Mirrors the exact status vocabulary the Pharmacy Partner module operates
/// on. A Cloud Function (see `functions/index.js`,
/// `onPharmacyOrderStatusChange`) translates these onto whichever real
/// source collection the order came from (`orders` for medicine,
/// `service_requests` for equipment) — this enum never needs to know about
/// that mapping.
enum PharmacyOrderStatus {
  pending,
  prescriptionRequired,
  verified,
  packed,
  outForDelivery,
  delivered,
  cancelled,
  unknown,
}

extension PharmacyOrderStatusX on PharmacyOrderStatus {
  String get firestoreValue {
    switch (this) {
      case PharmacyOrderStatus.pending:
        return 'pending';
      case PharmacyOrderStatus.prescriptionRequired:
        return 'prescription_required';
      case PharmacyOrderStatus.verified:
        return 'verified';
      case PharmacyOrderStatus.packed:
        return 'packed';
      case PharmacyOrderStatus.outForDelivery:
        return 'out_for_delivery';
      case PharmacyOrderStatus.delivered:
        return 'delivered';
      case PharmacyOrderStatus.cancelled:
        return 'cancelled';
      case PharmacyOrderStatus.unknown:
        return 'unknown';
    }
  }

  String get label {
    switch (this) {
      case PharmacyOrderStatus.pending:
        return 'New Order';
      case PharmacyOrderStatus.prescriptionRequired:
        return 'Needs Prescription';
      case PharmacyOrderStatus.verified:
        return 'Verified';
      case PharmacyOrderStatus.packed:
        return 'Packed';
      case PharmacyOrderStatus.outForDelivery:
        return 'Out for Delivery';
      case PharmacyOrderStatus.delivered:
        return 'Delivered';
      case PharmacyOrderStatus.cancelled:
        return 'Cancelled';
      case PharmacyOrderStatus.unknown:
        return 'Unknown';
    }
  }

  Color get color {
    switch (this) {
      case PharmacyOrderStatus.pending:
        return const Color(0xFF1565C0);
      case PharmacyOrderStatus.prescriptionRequired:
        return const Color(0xFFEF6C00);
      case PharmacyOrderStatus.verified:
        return const Color(0xFF00897B);
      case PharmacyOrderStatus.packed:
        return const Color(0xFF6A1B9A);
      case PharmacyOrderStatus.outForDelivery:
        return const Color(0xFFF9A825);
      case PharmacyOrderStatus.delivered:
        return const Color(0xFF2E7D32);
      case PharmacyOrderStatus.cancelled:
        return const Color(0xFFC62828);
      case PharmacyOrderStatus.unknown:
        return const Color(0xFF757575);
    }
  }

  static PharmacyOrderStatus fromFirestoreValue(String? raw) {
    switch (raw) {
      case 'pending':
        return PharmacyOrderStatus.pending;
      case 'prescription_required':
        return PharmacyOrderStatus.prescriptionRequired;
      case 'verified':
        return PharmacyOrderStatus.verified;
      case 'packed':
        return PharmacyOrderStatus.packed;
      case 'out_for_delivery':
        return PharmacyOrderStatus.outForDelivery;
      case 'delivered':
        return PharmacyOrderStatus.delivered;
      case 'cancelled':
        return PharmacyOrderStatus.cancelled;
      default:
        return PharmacyOrderStatus.unknown;
    }
  }
}

enum PharmacyOrderType { medicine, equipment }

class PharmacyOrder {
  final String id;
  final String sourceCollection; // 'orders' | 'service_requests'
  final String sourceId;
  final PharmacyOrderType orderType;
  final String? pharmacyId;
  final PharmacyOrderStatus status;
  final bool requiresPrescription;
  final String? prescriptionUrl;
  final String? prescriptionFileType; // 'image' | 'pdf'
  final DateTime? prescriptionUploadedAt;
  final bool? prescriptionVerified; // null = pending, true/false = decided
  final String? prescriptionRejectedReason;
  final String patientId;
  final String patientName;
  final String patientPhone;
  final String deliveryAddress;
  final int itemCount;
  final num totalAmount;
  final String? deliveryPersonName;
  final DateTime createdAt;
  final DateTime updatedAt;

  const PharmacyOrder({
    required this.id,
    required this.sourceCollection,
    required this.sourceId,
    required this.orderType,
    required this.pharmacyId,
    required this.status,
    required this.requiresPrescription,
    required this.prescriptionUrl,
    required this.prescriptionFileType,
    required this.prescriptionUploadedAt,
    required this.prescriptionVerified,
    required this.prescriptionRejectedReason,
    required this.patientId,
    required this.patientName,
    required this.patientPhone,
    required this.deliveryAddress,
    required this.itemCount,
    required this.totalAmount,
    required this.deliveryPersonName,
    required this.createdAt,
    required this.updatedAt,
  });

  factory PharmacyOrder.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    return PharmacyOrder(
      id: doc.id,
      sourceCollection: (d['sourceCollection'] as String?) ?? 'orders',
      sourceId: (d['sourceId'] as String?) ?? doc.id,
      orderType: (d['orderType'] as String?) == 'equipment'
          ? PharmacyOrderType.equipment
          : PharmacyOrderType.medicine,
      pharmacyId: d['pharmacyId'] as String?,
      status: PharmacyOrderStatusX.fromFirestoreValue(d['status'] as String?),
      requiresPrescription: (d['requiresPrescription'] as bool?) ?? false,
      prescriptionUrl: d['prescriptionUrl'] as String?,
      prescriptionFileType: d['prescriptionFileType'] as String?,
      prescriptionUploadedAt: (d['prescriptionUploadedAt'] as Timestamp?)?.toDate(),
      prescriptionVerified: d['prescriptionVerified'] as bool?,
      prescriptionRejectedReason: d['prescriptionRejectedReason'] as String?,
      patientId: (d['patientId'] as String?) ?? '',
      patientName: (d['patientName'] as String?) ?? 'Patient',
      patientPhone: (d['patientPhone'] as String?) ?? '',
      deliveryAddress: (d['deliveryAddress'] as String?) ?? '',
      itemCount: (d['itemCount'] as int?) ?? 1,
      totalAmount: (d['totalAmount'] as num?) ?? 0,
      deliveryPersonName: d['deliveryPersonName'] as String?,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (d['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  bool get isUnclaimed => pharmacyId == null;
  bool get hasPrescription => prescriptionUrl != null;
}
