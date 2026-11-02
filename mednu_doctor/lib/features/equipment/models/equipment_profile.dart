import 'package:cloud_firestore/cloud_firestore.dart';

/// A medical-equipment vendor's operational profile at
/// `equipment_profiles/{uid}` — the "restaurant" in the hotel/menu model.
/// Same shape as `PharmacyProfile`; the vendor's menu lives in the private
/// `items` subcollection (see [EquipmentItem]).
class EquipmentProfile {
  final String uid;
  final String name;
  final String licenseNumber;
  final String address;
  final double? latitude;
  final double? longitude;
  final String city;
  final String phone;
  final String email;
  final bool deliveryAvailable;
  final List<String> categoriesOffered;
  final bool isVerified;
  final String status; // 'pending' | 'active'
  final String photoUrl;
  final double rating;
  final int totalReviews;

  /// The shop's open / closed switch. When `false` every item on the menu
  /// shows to patients as unavailable and no new orders can be placed.
  final bool acceptingOrders;

  final Map<String, dynamic> documents;
  final Map<String, dynamic> documentVerification;
  final bool hasPendingChanges;
  final Map<String, dynamic> pendingChanges;

  const EquipmentProfile({
    required this.uid,
    required this.name,
    required this.licenseNumber,
    required this.address,
    this.latitude,
    this.longitude,
    this.city = '',
    required this.phone,
    required this.email,
    required this.deliveryAvailable,
    this.categoriesOffered = const [],
    required this.isVerified,
    required this.status,
    required this.photoUrl,
    required this.rating,
    required this.totalReviews,
    this.acceptingOrders = true,
    this.documents = const {},
    this.documentVerification = const {},
    this.hasPendingChanges = false,
    this.pendingChanges = const {},
  });

  bool get isActive => status == 'active';

  factory EquipmentProfile.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    return EquipmentProfile(
      uid: doc.id,
      name: (d['name'] as String?) ?? '',
      licenseNumber: (d['licenseNumber'] as String?) ?? '',
      address: (d['address'] as String?) ?? '',
      latitude: (d['latitude'] as num?)?.toDouble(),
      longitude: (d['longitude'] as num?)?.toDouble(),
      city: (d['city'] as String?) ?? '',
      phone: (d['phone'] as String?) ?? '',
      email: (d['email'] as String?) ?? '',
      deliveryAvailable: (d['deliveryAvailable'] as bool?) ?? true,
      categoriesOffered: ((d['categoriesOffered'] as List?) ?? const [])
          .whereType<String>()
          .toList(),
      isVerified: (d['isVerified'] as bool?) ?? false,
      status: (d['status'] as String?) ?? 'pending',
      photoUrl: (d['photoUrl'] as String?) ?? '',
      rating: ((d['rating'] as num?) ?? 0).toDouble(),
      totalReviews: (d['totalReviews'] as num?)?.toInt() ?? 0,
      acceptingOrders: (d['acceptingOrders'] as bool?) ?? true,
      documents: Map<String, dynamic>.from(
          (d['documents'] as Map?) ?? const <String, dynamic>{}),
      documentVerification: Map<String, dynamic>.from(
          (d['documentVerification'] as Map?) ?? const <String, dynamic>{}),
      hasPendingChanges: (d['hasPendingChanges'] as bool?) ?? false,
      pendingChanges: Map<String, dynamic>.from(
          (d['pendingChanges'] as Map?) ?? const <String, dynamic>{}),
    );
  }
}

/// Equipment categories — a UI convenience list used both for the vendor's
/// onboarding checklist and for tagging menu items. A vendor can still list
/// anything; this only keeps the spelling consistent for filtering.
const kEquipmentCategoryCatalog = <String>[
  'Mobility Aids',
  'Hospital Beds',
  'Oxygen & Respiratory',
  'Monitoring Devices',
  'Home Care',
  'Physiotherapy',
  'Diabetic Care',
  'Surgical Support',
];
