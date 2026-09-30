import 'package:cloud_firestore/cloud_firestore.dart';

/// Backed by `physiotherapist_profiles/{uid}` — the partner's own identity
/// document, and the same doc `firestore.rules`' `isPhysiotherapistPartner()`
/// existence+status-checks to decide who may see unclaimed sessions.
class PhysioProfile {
  final String name;
  final String photoUrl;
  final List<String> certifications;
  final List<String> specialties;
  /// Kept as a "starting from" figure for older display spots (dashboard
  /// stat, patient list card) — derived from the cheapest of
  /// [onlineRate]/[clinicRate]/[homeRate] whenever the profile is written
  /// via `PhysioProfileService.createProfile`/`updateProfile`, never edited
  /// directly.
  final num hourlyRate;
  final num onlineRate;
  /// 0 means this physiotherapist doesn't offer in-clinic appointments —
  /// unlike [onlineRate]/[homeRate], this one is genuinely optional per the
  /// registration form.
  final num clinicRate;
  final num homeRate;
  final double rating;
  final int totalSessions;
  final int experienceYears;
  final bool documentsVerified;
  final String city;
  final double? clinicLat;
  final double? clinicLng;
  final List<String> languages;

  /// Admin-approval status: 'pending' | 'active'. Distinct from
  /// [documentsVerified] — this is the account-level gate the router keys
  /// off (via the shared `roleProfileExists`/`status` fields it reads).
  final String status;

  /// Raw `documents` / `documentVerification` maps, keyed by canonical
  /// docType. Kept untyped here so the shared documents layer
  /// (`shared_core/documents`) owns their parsing for every role.
  final Map<String, dynamic> documents;
  final Map<String, dynamic> documentVerification;

  /// Realtime presence — written by [PhysioPresenceService]'s heartbeat, same
  /// `isOnline`/`lastHeartbeat` shape as `doctors/{uid}` and
  /// `ambulance_profiles/{uid}`.
  final bool isOnline;
  final DateTime? lastHeartbeat;

  /// True once a self-edit has been submitted while `status == 'active'`
  /// and is awaiting admin approval — see [PendingProfileEditService].
  /// [pendingChanges] holds exactly what was last submitted (a full
  /// snapshot of the editable fields), so the edit form can show it back
  /// to the partner even though it isn't live yet.
  final bool hasPendingChanges;
  final Map<String, dynamic> pendingChanges;

  const PhysioProfile({
    required this.name,
    required this.photoUrl,
    required this.certifications,
    required this.specialties,
    required this.hourlyRate,
    this.onlineRate = 0,
    this.clinicRate = 0,
    this.homeRate = 0,
    required this.rating,
    required this.totalSessions,
    required this.experienceYears,
    required this.documentsVerified,
    this.city = '',
    this.clinicLat,
    this.clinicLng,
    this.languages = const [],
    this.status = 'pending',
    this.documents = const {},
    this.documentVerification = const {},
    this.isOnline = false,
    this.lastHeartbeat,
    this.hasPendingChanges = false,
    this.pendingChanges = const {},
  });

  /// What the Profile screen renders before the partner has completed
  /// onboarding (no `physiotherapist_profiles/{uid}` doc yet).
  factory PhysioProfile.empty() => const PhysioProfile(
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

  factory PhysioProfile.fromFirestore(DocumentSnapshot<Object?> doc) {
    final d = (doc.data() as Map<String, dynamic>?) ?? const {};
    return PhysioProfile(
      name: d['name'] as String? ?? 'Physiotherapist',
      photoUrl: d['photoUrl'] as String? ?? '',
      certifications: (d['certifications'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .toList(),
      specialties: (d['specialties'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .toList(),
      hourlyRate: (d['hourlyRate'] as num?) ?? 0,
      onlineRate: (d['onlineRate'] as num?) ?? 0,
      clinicRate: (d['clinicRate'] as num?) ?? 0,
      homeRate: (d['homeRate'] as num?) ?? 0,
      rating: ((d['rating'] as num?) ?? 0).toDouble(),
      totalSessions: ((d['totalSessions'] as num?) ?? 0).toInt(),
      experienceYears: ((d['experienceYears'] as num?) ?? 0).toInt(),
      documentsVerified: d['documentsVerified'] as bool? ?? false,
      city: d['city'] as String? ?? '',
      clinicLat: (d['clinicLat'] as num?)?.toDouble(),
      clinicLng: (d['clinicLng'] as num?)?.toDouble(),
      languages: ((d['languages'] as List?) ?? const []).whereType<String>().toList(),
      status: d['status'] as String? ?? 'pending',
      documents: Map<String, dynamic>.from(
          (d['documents'] as Map?) ?? const <String, dynamic>{}),
      documentVerification: Map<String, dynamic>.from(
          (d['documentVerification'] as Map?) ?? const <String, dynamic>{}),
      isOnline: d['isOnline'] as bool? ?? false,
      lastHeartbeat: (d['lastHeartbeat'] as Timestamp?)?.toDate(),
      hasPendingChanges: d['hasPendingChanges'] as bool? ?? false,
      pendingChanges: Map<String, dynamic>.from(
          (d['pendingChanges'] as Map?) ?? const <String, dynamic>{}),
    );
  }
}
