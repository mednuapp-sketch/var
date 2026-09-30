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
  final int totalSessions;
  /// "Starting from" figure — the cheapest of [onlineRate]/[clinicRate]/
  /// [homeRate] that's actually offered, computed server-side (see
  /// PhysioProfileService._startingFrom in mednu_doctor). Kept for list-card
  /// display; booking a specific mode uses the per-mode rate instead.
  final num hourlyRate;
  final num onlineRate;
  /// 0 means this physiotherapist doesn't offer in-clinic appointments.
  final num clinicRate;
  final num homeRate;
  final String city;
  final List<String> languages;
  final double? clinicLat;
  final double? clinicLng;
  final bool isAvailable;
  final bool isOnline;
  final DateTime? lastHeartbeat;

  /// Same 3-minute staleness rule `ConsultationScreen._hasFreshHeartbeat`
  /// uses for doctors — `isOnline` alone can't be trusted once the app that
  /// last wrote it stops heartbeating (killed, crashed, lost network).
  bool get isCurrentlyOnline {
    if (!isOnline) return false;
    final hb = lastHeartbeat;
    if (hb == null) return true;
    return DateTime.now().difference(hb).inMinutes < 3;
  }

  const PhysiotherapistModel({
    required this.id,
    required this.name,
    required this.photoUrl,
    required this.certifications,
    required this.specialties,
    required this.experienceYears,
    required this.totalSessions,
    required this.hourlyRate,
    this.onlineRate = 0,
    this.clinicRate = 0,
    this.homeRate = 0,
    required this.city,
    required this.languages,
    this.clinicLat,
    this.clinicLng,
    required this.isAvailable,
    this.isOnline = false,
    this.lastHeartbeat,
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
      totalSessions: (d['totalSessions'] as num?)?.toInt() ?? 0,
      hourlyRate: (d['hourlyRate'] as num?) ?? 0,
      onlineRate: (d['onlineRate'] as num?) ?? 0,
      clinicRate: (d['clinicRate'] as num?) ?? 0,
      homeRate: (d['homeRate'] as num?) ?? 0,
      city: d['city'] as String? ?? '',
      languages: ((d['languages'] as List?) ?? const []).whereType<String>().toList(),
      clinicLat: (d['clinicLat'] as num?)?.toDouble(),
      clinicLng: (d['clinicLng'] as num?)?.toDouble(),
      isAvailable: d['isAvailable'] as bool? ?? true,
      isOnline: d['isOnline'] as bool? ?? false,
      lastHeartbeat: (d['lastHeartbeat'] as Timestamp?)?.toDate(),
    );
  }
}
