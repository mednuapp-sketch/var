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
  final String city;
  final double? lat;
  final double? lng;
  final bool documentsVerified;
  final String gender;

  /// Real, persisted on-duty/availability flag — `caregiver_profiles/{uid}.
  /// isOnDuty`. Toggled from the Dashboard's duty switch via
  /// [CaregiverProfileService.updateOnDuty] and read back live through
  /// `caregiverOnDutyProvider`, so it survives app restart and actually
  /// reflects what the matching pipeline sees, unlike the old session-local
  /// flag it replaced.
  final bool isOnDuty;

  /// 'caregiver' | 'care_assistant' — which patient-facing listing
  /// (`caregivers` vs `care_assistants`, see `functions/index.js`'
  /// `onCaregiverProfileWriteForVisibility`) this profile mirrors into.
  final String serviceType;

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
    this.city = '',
    this.lat,
    this.lng,
    required this.documentsVerified,
    this.status = 'pending',
    this.documents = const {},
    this.documentVerification = const {},
    this.gender = '',
    this.serviceType = 'caregiver',
    this.isOnDuty = false,
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
      city: d['city'] as String? ?? '',
      lat: (d['lat'] as num?)?.toDouble(),
      lng: (d['lng'] as num?)?.toDouble(),
      documentsVerified: d['documentsVerified'] as bool? ?? false,
      status: d['status'] as String? ?? 'pending',
      documents: Map<String, dynamic>.from(
          (d['documents'] as Map?) ?? const <String, dynamic>{}),
      documentVerification: Map<String, dynamic>.from(
          (d['documentVerification'] as Map?) ?? const <String, dynamic>{}),
      gender: d['gender'] as String? ?? '',
      serviceType: d['serviceType'] as String? ?? 'caregiver',
      isOnDuty: d['isOnDuty'] as bool? ?? false,
    );
  }
}
