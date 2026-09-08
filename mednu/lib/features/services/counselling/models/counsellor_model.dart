import 'package:cloud_firestore/cloud_firestore.dart';

/// Backed by the public `counsellors/{id}` catalogue — mirrored from an
/// approved `counsellor_profiles/{uid}` doc in the partner app by
/// `onCounsellorProfileWriteForVisibility` (functions/index.js). Same shape
/// family as [PhysiotherapistModel], minus the location/language fields:
/// counsellor registration collects neither (sessions are remote-only), so
/// this model doesn't carry `city`/`clinicLat`/`clinicLng`/`languages`.
class CounsellorModel {
  final String id;
  final String name;
  final String photoUrl;
  final List<String> certifications;
  final List<String> specialties;
  final int experienceYears;
  final double rating;
  final int totalSessions;
  final num hourlyRate;
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

  const CounsellorModel({
    required this.id,
    required this.name,
    required this.photoUrl,
    required this.certifications,
    required this.specialties,
    required this.experienceYears,
    required this.rating,
    required this.totalSessions,
    required this.hourlyRate,
    required this.isAvailable,
    this.isOnline = false,
    this.lastHeartbeat,
  });

  factory CounsellorModel.fromFirestore(DocumentSnapshot doc) {
    final d = (doc.data() as Map<String, dynamic>?) ?? {};
    return CounsellorModel(
      id: doc.id,
      name: d['name'] as String? ?? 'Counsellor',
      photoUrl: d['photoUrl'] as String? ?? '',
      certifications: ((d['certifications'] as List?) ?? const []).whereType<String>().toList(),
      specialties: ((d['specialties'] as List?) ?? const []).whereType<String>().toList(),
      experienceYears: (d['experienceYears'] as num?)?.toInt() ?? 0,
      rating: (d['rating'] as num?)?.toDouble() ?? 0.0,
      totalSessions: (d['totalSessions'] as num?)?.toInt() ?? 0,
      hourlyRate: (d['hourlyRate'] as num?) ?? 0,
      isAvailable: d['isAvailable'] as bool? ?? true,
      isOnline: d['isOnline'] as bool? ?? false,
      lastHeartbeat: (d['lastHeartbeat'] as Timestamp?)?.toDate(),
    );
  }
}
