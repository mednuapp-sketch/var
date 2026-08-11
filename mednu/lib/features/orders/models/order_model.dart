import 'package:cloud_firestore/cloud_firestore.dart';

class OrderItemModel {
  final String id;
  final String name;
  final String brand;
  final num price;
  final int count;

  const OrderItemModel({
    required this.id,
    required this.name,
    required this.brand,
    required this.price,
    required this.count,
  });

  factory OrderItemModel.fromMap(Map<String, dynamic> m) => OrderItemModel(
        id: (m['id'] as String?) ?? '',
        name: (m['name'] as String?) ?? 'Item',
        brand: (m['brand'] as String?) ?? '',
        price: (m['price'] as num?) ?? 0,
        count: (m['count'] as int?) ?? 1,
      );
}

/// Mirrors exactly the fields `cart_screen.dart` writes on checkout, plus
/// the additive prescription fields this feature introduces. Nothing here
/// changes what checkout writes — this is a read-side model only.
class OrderModel {
  final String orderId;
  final String patientId;
  final List<OrderItemModel> items;
  final num total;
  final String status;
  final String deliveryAddress;
  final String deliveryName;
  final String deliveryPhone;
  final DateTime createdAt;

  // ── Additive prescription fields ──────────────────────────────────────
  final String? prescriptionUrl;
  final String? prescriptionFileType; // 'image' | 'pdf'
  final DateTime? prescriptionUploadedAt;
  final bool? prescriptionVerified; // null = pending, true/false = decided
  final String? prescriptionRejectedReason;

  const OrderModel({
    required this.orderId,
    required this.patientId,
    required this.items,
    required this.total,
    required this.status,
    required this.deliveryAddress,
    required this.deliveryName,
    required this.deliveryPhone,
    required this.createdAt,
    required this.prescriptionUrl,
    required this.prescriptionFileType,
    required this.prescriptionUploadedAt,
    required this.prescriptionVerified,
    required this.prescriptionRejectedReason,
  });

  factory OrderModel.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    return OrderModel(
      orderId: (d['orderId'] as String?) ?? doc.id,
      patientId: (d['patientId'] as String?) ?? '',
      items: ((d['items'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(OrderItemModel.fromMap)
          .toList(),
      total: (d['total'] as num?) ?? 0,
      status: (d['status'] as String?) ?? 'confirmed',
      deliveryAddress: (d['deliveryAddress'] as String?) ?? '',
      deliveryName: (d['deliveryName'] as String?) ?? '',
      deliveryPhone: (d['deliveryPhone'] as String?) ?? '',
      createdAt: (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      prescriptionUrl: d['prescriptionUrl'] as String?,
      prescriptionFileType: d['prescriptionFileType'] as String?,
      prescriptionUploadedAt: (d['prescriptionUploadedAt'] as Timestamp?)?.toDate(),
      prescriptionVerified: d['prescriptionVerified'] as bool?,
      prescriptionRejectedReason: d['prescriptionRejectedReason'] as String?,
    );
  }

  bool get hasPrescription => prescriptionUrl != null;
  bool get needsPrescriptionDecision => hasPrescription && prescriptionVerified == null;
  bool get prescriptionWasRejected => prescriptionVerified == false;
}
