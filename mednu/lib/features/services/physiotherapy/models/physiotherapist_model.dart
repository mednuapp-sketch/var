import 'package:cloud_firestore/cloud_firestore.dart';

/// Backed by the public `physiotherapists/{id}` catalogue — mirrored from an
/// approved `physiotherapist_profiles/{uid}` doc in the partner app by
/// `onPhysiotherapistProfileWriteForVisibility` (functions/index.js). Same
/// shape family as `NutritionistModel`, adapted to physiotherapy's own field
/// names (`hourlyRate`/`totalSessions` rather than `consultationFee`/
/// `reviewCount`) since those already exist in the partner-side model.
class PhysiotherapistModel {
  final String id;
  final String name;
  final String photoUrl;
  final List<String> certifications;
  final List<String> specialties;
  final int experienceYears;
  final double rating;
  final int totalSessions;
  final num hourlyRate;
  final String city;
  final List<String> languages;
  final double? clinicLat;
  final double? clinicLng;
  final bool isAvailable;

  const PhysiotherapistModel({
    required this.id,
    required this.name,
    required this.photoUrl,
    required this.certifications,
    required this.specialties,
    required this.experienceYears,
    required this.rating,
    required this.totalSessions,
    required this.hourlyRate,
    required this.city,
    required this.languages,
    this.clinicLat,
    this.clinicLng,
    required this.isAvailable,
  });

  factory PhysiotherapistModel.fromFirestore(DocumentSnapshot doc) {
    final d = (doc.data() as Map<String, dynamic>?) ?? {};
    return PhysiotherapistModel(
      id: doc.id,
      name: d['name'] as String? ?? 'Physiotherapist',
      photoUrl: d['photoUrl'] as String? ?? '',
      certifications: ((d['certifications'] as List?) ?? const []).whereType<String>().toList(),
      specialties: ((d['specialties'] as List?) ?? const []).whereType<String>().toList(),
      experienceYears: (d['experienceYears'] as num?)?.toInt() ?? 0,
      rating: (d['rating'] as num?)?.toDouble() ?? 0.0,
      totalSessions: (d['totalSessions'] as num?)?.toInt() ?? 0,
      hourlyRate: (d['hourlyRate'] as num?) ?? 0,
      city: d['city'] as String? ?? '',
      languages: ((d['languages'] as List?) ?? const []).whereType<String>().toList(),
      clinicLat: (d['clinicLat'] as num?)?.toDouble(),
      clinicLng: (d['clinicLng'] as num?)?.toDouble(),
      isAvailable: d['isAvailable'] as bool? ?? true,
    );
  }
}
