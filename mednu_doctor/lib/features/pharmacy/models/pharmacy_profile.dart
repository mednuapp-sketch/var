import 'package:cloud_firestore/cloud_firestore.dart';

class PharmacyProfile {
  final String uid;
  final String name;
  final String licenseNumber;
  final String address;
  final String phone;
  final String email;
  final bool deliveryAvailable;
  final bool isVerified;
  final String status; // 'pending' | 'active'
  final String photoUrl;
  final double rating;
  final int totalReviews;

  /// Raw `documents` / `documentVerification` maps, keyed by canonical
  /// docType. Kept untyped here so the shared documents layer
  /// (`shared_core/documents`) owns their parsing for every role.
  final Map<String, dynamic> documents;
  final Map<String, dynamic> documentVerification;

  const PharmacyProfile({
    required this.uid,
    required this.name,
    required this.licenseNumber,
    required this.address,
    required this.phone,
    required this.email,
    required this.deliveryAvailable,
    required this.isVerified,
    required this.status,
    required this.photoUrl,
    required this.rating,
    required this.totalReviews,
    this.documents = const {},
    this.documentVerification = const {},
  });

  factory PharmacyProfile.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    return PharmacyProfile(
      uid: doc.id,
      name: (d['name'] as String?) ?? '',
      licenseNumber: (d['licenseNumber'] as String?) ?? '',
      address: (d['address'] as String?) ?? '',
      phone: (d['phone'] as String?) ?? '',
      email: (d['email'] as String?) ?? '',
      deliveryAvailable: (d['deliveryAvailable'] as bool?) ?? true,
      isVerified: (d['isVerified'] as bool?) ?? false,
      status: (d['status'] as String?) ?? 'pending',
      photoUrl: (d['photoUrl'] as String?) ?? '',
      rating: ((d['rating'] as num?) ?? 0).toDouble(),
      totalReviews: (d['totalReviews'] as int?) ?? 0,
      documents: Map<String, dynamic>.from(
          (d['documents'] as Map?) ?? const <String, dynamic>{}),
      documentVerification: Map<String, dynamic>.from(
          (d['documentVerification'] as Map?) ?? const <String, dynamic>{}),
    );
  }
}
