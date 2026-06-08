import 'package:cloud_firestore/cloud_firestore.dart';

class NutritionistModel {
  final String id;
  final String name;
  final String qualification;
  final String specialization;
  final int experienceYears;
  final double rating;
  final int reviewCount;
  final double consultationFee;
  final List<String> languages;
  final List<String> expertiseAreas;
  final String bio;
  final String photoUrl;
  final bool isAvailable;
  final bool isOnlineAvailable;
  final bool isInPersonAvailable;
  final String city;
  final String clinicName;
  final List<String> availableDays;
  final Map<String, List<String>> slots; // day -> list of time slots
  final DateTime createdAt;

  const NutritionistModel({
    required this.id,
    required this.name,
    required this.qualification,
    required this.specialization,
    required this.experienceYears,
    required this.rating,
    required this.reviewCount,
    required this.consultationFee,
    required this.languages,
    required this.expertiseAreas,
    required this.bio,
    required this.photoUrl,
    required this.isAvailable,
    required this.isOnlineAvailable,
    required this.isInPersonAvailable,
    required this.city,
    required this.clinicName,
    required this.availableDays,
    required this.slots,
    required this.createdAt,
  });

  factory NutritionistModel.fromFirestore(DocumentSnapshot doc) {
    final d = (doc.data() as Map<String, dynamic>?) ?? {};
    return NutritionistModel(
      id: doc.id,
      name: d['name'] as String? ?? '',
      qualification: d['qualification'] as String? ?? '',
      specialization: d['specialization'] as String? ?? '',
      experienceYears: (d['experienceYears'] as num?)?.toInt() ?? 0,
      rating: (d['rating'] as num?)?.toDouble() ?? 0.0,
      reviewCount: (d['reviewCount'] as num?)?.toInt() ?? 0,
      consultationFee: (d['consultationFee'] as num?)?.toDouble() ?? 0.0,
      languages: List<String>.from(d['languages'] as List? ?? []),
      expertiseAreas: List<String>.from(d['expertiseAreas'] as List? ?? []),
      bio: d['bio'] as String? ?? '',
      photoUrl: d['photoUrl'] as String? ?? '',
      isAvailable: d['isAvailable'] as bool? ?? true,
      isOnlineAvailable: d['isOnlineAvailable'] as bool? ?? true,
      isInPersonAvailable: d['isInPersonAvailable'] as bool? ?? false,
      city: d['city'] as String? ?? '',
      clinicName: d['clinicName'] as String? ?? '',
      availableDays: List<String>.from(d['availableDays'] as List? ?? []),
      slots: (d['slots'] as Map<String, dynamic>?)?.map(
            (k, v) => MapEntry(k, List<String>.from(v as List? ?? [])),
          ) ??
          {},
      createdAt: (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() => {
        'name': name,
        'qualification': qualification,
        'specialization': specialization,
        'experienceYears': experienceYears,
        'rating': rating,
        'reviewCount': reviewCount,
        'consultationFee': consultationFee,
        'languages': languages,
        'expertiseAreas': expertiseAreas,
        'bio': bio,
        'photoUrl': photoUrl,
        'isAvailable': isAvailable,
        'isOnlineAvailable': isOnlineAvailable,
        'isInPersonAvailable': isInPersonAvailable,
        'city': city,
        'clinicName': clinicName,
        'availableDays': availableDays,
        'slots': slots,
        'createdAt': FieldValue.serverTimestamp(),
      };
}
