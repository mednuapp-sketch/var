import 'package:cloud_firestore/cloud_firestore.dart';

/// One `hospital_profiles/{uid}` doc — the billing-desk staff login itself,
/// not the hospital entity (see [HospitalProfileService]'s doc comment for
/// why those are two different things). Typed read model mirroring
/// `LabProfile`/`NutritionAppointment`'s `fromDoc`/`fromFirestore` shape used
/// elsewhere in this app.
class HospitalProfile {
  final String uid;
  final String contactName;
  final String phone;
  final String? hospitalId;
  final String? hospitalName;
  final String status;
  final String? photoUrl;

  /// `documents.{docType}` (written by the partner app on upload) and
  /// `documentVerification.{docType}` (admin-only) — same shape every other
  /// partner role uses, see `PartnerDocumentType.hospital`.
  final Map<String, dynamic> documents;
  final Map<String, dynamic> documentVerification;

  const HospitalProfile({
    required this.uid,
    required this.contactName,
    required this.phone,
    required this.hospitalId,
    required this.hospitalName,
    required this.status,
    required this.photoUrl,
    this.documents = const {},
    this.documentVerification = const {},
  });

  /// Whether a Director has linked this desk login to a real
  /// `hospitals/{hospitalId}` catalog entry yet — every appointment/payment
  /// query is scoped by this, so screens gate on it before querying.
  bool get isLinked => hospitalId != null && hospitalId!.isNotEmpty;

  bool get isActive => status == 'active';

  /// Best available display name — the hospital's own name once linked,
  /// falling back to the desk contact's name before that happens.
  String get displayName =>
      (hospitalName != null && hospitalName!.trim().isNotEmpty) ? hospitalName! : contactName;

  factory HospitalProfile.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    return HospitalProfile(
      uid: doc.id,
      contactName: d['contactName'] as String? ?? '',
      phone: d['phone'] as String? ?? '',
      hospitalId: d['hospitalId'] as String?,
      hospitalName: d['hospitalName'] as String?,
      status: d['status'] as String? ?? 'pending',
      photoUrl: d['photoUrl'] as String?,
      documents: Map<String, dynamic>.from(
          (d['documents'] as Map?) ?? const <String, dynamic>{}),
      documentVerification: Map<String, dynamic>.from(
          (d['documentVerification'] as Map?) ?? const <String, dynamic>{}),
    );
  }
}
