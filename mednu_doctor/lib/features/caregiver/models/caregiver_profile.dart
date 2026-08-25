import 'package:cloud_firestore/cloud_firestore.dart';

/// Backed by `caregiver_profiles/{uid}` — the partner's own identity
/// document, and the same doc `firestore.rules`' `isCaregiverPartner()`
/// existence-checks to decide who may see unclaimed visits.
class CaregiverProfile {
  final String name;
  final String photoUrl;
  final List<String> certifications;
  final List<String> specialties;
  final num hourlyRate;
  final double rating;
  final int totalVisits;
  final int experienceYears;
  final bool documentsVerified;

  /// Admin-approval status: 'pending' | 'active'. Distinct from
  /// [documentsVerified] (a per-document flag) — this is the account-level
  /// gate the router and the Documents section's `locked` state key off.
  final String status;

  /// Raw `documents` / `documentVerification` maps, keyed by canonical
  /// docType. Kept untyped here so the shared documents layer
  /// (`shared_core/documents`) owns their parsing for every role.
  final Map<String, dynamic> documents;
  final Map<String, dynamic> documentVerification;

  const CaregiverProfile({
    required this.name,
    required this.photoUrl,
    required this.certifications,
    required this.specialties,
    required this.hourlyRate,
    required this.rating,
    required this.totalVisits,
    required this.experienceYears,
    required this.documentsVerified,
    this.status = 'pending',
    this.documents = const {},
    this.documentVerification = const {},
  });

  /// What the Profile screen renders before the partner has completed
  /// onboarding (no `caregiver_profiles/{uid}` doc yet). Keeping this
  /// non-null preserves `caregiverProfileProvider`'s type — and therefore
  /// every screen consuming it — unchanged.
  factory CaregiverProfile.empty() => const CaregiverProfile(
        name: 'Complete your profile',
        photoUrl: '',
        certifications: [],
        specialties: [],
        hourlyRate: 0,
        rating: 0,
        totalVisits: 0,
        experienceYears: 0,
        documentsVerified: false,
      );

  factory CaregiverProfile.fromFirestore(DocumentSnapshot<Object?> doc) {
    final d = (doc.data() as Map<String, dynamic>?) ?? const {};
    return CaregiverProfile(
      name: d['name'] as String? ?? 'Caregiver',
      photoUrl: d['photoUrl'] as String? ?? '',
      certifications: (d['certifications'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .toList(),
      specialties: (d['specialties'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .toList(),
      hourlyRate: (d['hourlyRate'] as num?) ?? 0,
      rating: ((d['rating'] as num?) ?? 0).toDouble(),
      totalVisits: ((d['totalVisits'] as num?) ?? 0).toInt(),
      experienceYears: ((d['experienceYears'] as num?) ?? 0).toInt(),
      documentsVerified: d['documentsVerified'] as bool? ?? false,
      status: d['status'] as String? ?? 'pending',
      documents: Map<String, dynamic>.from(
          (d['documents'] as Map?) ?? const <String, dynamic>{}),
      documentVerification: Map<String, dynamic>.from(
          (d['documentVerification'] as Map?) ?? const <String, dynamic>{}),
    );
  }
}
