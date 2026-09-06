import 'package:cloud_firestore/cloud_firestore.dart';

class BannerModel {
  final String id;
  final String? title;
  final String? description;
  final String imageUrl;
  final String storagePath;
  final String? ctaText;
  final String? ctaUrl;
  final int order;
  final bool isEnabled;
  final DateTime? startDate;
  final DateTime? endDate;
  final DateTime createdAt;

  const BannerModel({
    required this.id,
    this.title,
    this.description,
    required this.imageUrl,
    required this.storagePath,
    this.ctaText,
    this.ctaUrl,
    this.order = 0,
    required this.isEnabled,
    this.startDate,
    this.endDate,
    required this.createdAt,
  });

  bool get isActive {
    if (!isEnabled) return false;
    final now = DateTime.now();
    if (startDate != null && now.isBefore(startDate!)) return false;
    if (endDate != null && now.isAfter(endDate!)) return false;
    return true;
  }

  factory BannerModel.fromFirestore(DocumentSnapshot doc) {
    final data = (doc.data() as Map<String, dynamic>?) ?? {};
    return BannerModel(
      id: doc.id,
      title: data['title'] as String?,
      description: data['description'] as String?,
      imageUrl: data['imageUrl'] as String? ?? '',
      storagePath: data['storagePath'] as String? ?? '',
      ctaText: data['ctaText'] as String?,
      ctaUrl: data['ctaUrl'] as String?,
      order: data['order'] as int? ?? 0,
      isEnabled: data['isEnabled'] as bool? ?? false,
      startDate: (data['startDate'] as Timestamp?)?.toDate(),
      endDate: (data['endDate'] as Timestamp?)?.toDate(),
      createdAt:
          (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }
}
