import 'package:cloud_firestore/cloud_firestore.dart';

/// Backed by `counsellor_profiles/{uid}` — the partner's own identity
/// document, and the same doc `firestore.rules`' `isCounsellorPartner()`
/// existence+status-checks to decide who may see unclaimed sessions.
class CounsellingProfile {
  final String name;
  final String photoUrl;
  final List<String> certifications;
  final List<String> specialties;
  final num hourlyRate;
  final double rating;
  final int totalSessions;
  final int experienceYears;
  final bool documentsVerified;
  final String status;

  const CounsellingProfile({
    required this.name,
    required this.photoUrl,
    required this.certifications,
    required this.specialties,
    required this.hourlyRate,
    required this.rating,
    required this.totalSessions,
    required this.experienceYears,
    required this.documentsVerified,
    this.status = 'pending',
  });

  factory CounsellingProfile.empty() => const CounsellingProfile(
        name: 'Complete your profile',
        photoUrl: '',
        certifications: [],
        specialties: [],
        hourlyRate: 0,
        rating: 0,
        totalSessions: 0,
        experienceYears: 0,
        documentsVerified: false,
      );

  factory CounsellingProfile.fromFirestore(DocumentSnapshot<Object?> doc) {
    final d = (doc.data() as Map<String, dynamic>?) ?? const {};
    return CounsellingProfile(
      name: d['name'] as String? ?? 'Counsellor',
      photoUrl: d['photoUrl'] as String? ?? '',
      certifications: (d['certifications'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .toList(),
      specialties: (d['specialties'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .toList(),
      hourlyRate: (d['hourlyRate'] as num?) ?? 0,
      rating: ((d['rating'] as num?) ?? 0).toDouble(),
      totalSessions: ((d['totalSessions'] as num?) ?? 0).toInt(),
      experienceYears: ((d['experienceYears'] as num?) ?? 0).toInt(),
      documentsVerified: d['documentsVerified'] as bool? ?? false,
      status: d['status'] as String? ?? 'pending',
    );
  }
}
