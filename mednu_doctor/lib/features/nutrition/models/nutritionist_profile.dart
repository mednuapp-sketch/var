import 'package:cloud_firestore/cloud_firestore.dart';

/// Backed by `nutritionist_profiles/{uid}` — the partner's own identity
/// document, same shape/role as `caregiver_profiles`/`lab_profiles`. Private
/// to the owner; a Cloud Function mirrors the patient-relevant fields into
/// the public `nutritionists/{uid}` catalogue entry once `status == 'active'`
/// (see `onNutritionistProfileWriteForVisibility`, functions/index.js).
class NutritionistProfile {
  final String name;
  final String qualification;
  final String specialization;
  final int experienceYears;
  final String bio;
  final num consultationFee;
  final String city;
  final double? lat;
  final double? lng;
  final List<String> languages;
  final double rating;
  final int reviewCount;
  final bool documentsVerified;

  /// Admin-approval status: 'pending' | 'active'.
  final String status;

  final Map<String, dynamic> documents;
  final Map<String, dynamic> documentVerification;

  const NutritionistProfile({
    required this.name,
    required this.qualification,
    required this.specialization,
    required this.experienceYears,
    required this.bio,
    required this.consultationFee,
    required this.city,
    this.lat,
    this.lng,
    this.languages = const [],
    required this.rating,
    required this.reviewCount,
    required this.documentsVerified,
    this.status = 'pending',
    this.documents = const {},
    this.documentVerification = const {},
  });

  factory NutritionistProfile.empty() => const NutritionistProfile(
        name: 'Complete your profile',
        qualification: '',
        specialization: '',
        experienceYears: 0,
        bio: '',
        consultationFee: 0,
        city: '',
        languages: [],
        rating: 0,
        reviewCount: 0,
        documentsVerified: false,
      );

  factory NutritionistProfile.fromFirestore(DocumentSnapshot<Object?> doc) {
    final d = (doc.data() as Map<String, dynamic>?) ?? const {};
    return NutritionistProfile(
      name: d['name'] as String? ?? 'Nutritionist',
      qualification: d['qualification'] as String? ?? '',
      specialization: d['specialization'] as String? ?? '',
      experienceYears: ((d['experienceYears'] as num?) ?? 0).toInt(),
      bio: d['bio'] as String? ?? '',
      consultationFee: (d['consultationFee'] as num?) ?? 0,
      city: d['city'] as String? ?? '',
      lat: (d['lat'] as num?)?.toDouble(),
      lng: (d['lng'] as num?)?.toDouble(),
      languages: ((d['languages'] as List?) ?? const []).whereType<String>().toList(),
      rating: ((d['rating'] as num?) ?? 0).toDouble(),
      reviewCount: ((d['reviewCount'] as num?) ?? 0).toInt(),
      documentsVerified: d['documentsVerified'] as bool? ?? false,
      status: d['status'] as String? ?? 'pending',
      documents: Map<String, dynamic>.from(
          (d['documents'] as Map?) ?? const <String, dynamic>{}),
      documentVerification: Map<String, dynamic>.from(
          (d['documentVerification'] as Map?) ?? const <String, dynamic>{}),
    );
  }
}
