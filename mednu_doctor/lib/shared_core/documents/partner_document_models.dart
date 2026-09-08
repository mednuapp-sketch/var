import 'package:cloud_firestore/cloud_firestore.dart';

/// Shared, role-parameterised model layer for partner verification documents.
///
/// One canonical set of `docType` keys is used everywhere — Firestore field
/// names under `{role}_profiles/{uid}.documents`, Storage path segments under
/// `{role}_documents/{uid}/`, and the Admin panel's `PARTNER_ROLES.docSlots`.
/// Changing a key here means changing it in all three places.

/// A document slot a role must fill in. `key` is the canonical docType.
class PartnerDocumentType {
  final String key;
  final String label;

  const PartnerDocumentType(this.key, this.label);

  static const lab = <PartnerDocumentType>[
    PartnerDocumentType('lab_license', 'Lab License'),
    PartnerDocumentType('address_proof', 'Address Proof'),
  ];

  static const pharmacy = <PartnerDocumentType>[
    PartnerDocumentType('pharmacy_license', 'Pharmacy License'),
    PartnerDocumentType('address_proof', 'Address Proof'),
  ];

  static const ambulance = <PartnerDocumentType>[
    PartnerDocumentType('vehicle_registration', 'Vehicle Registration'),
    PartnerDocumentType('driver_license', 'Driver License'),
    PartnerDocumentType('address_proof', 'Address Proof'),
  ];

  static const caregiver = <PartnerDocumentType>[
    PartnerDocumentType('caregiver_id', 'Caregiver ID'),
    PartnerDocumentType('certificates', 'Certificates'),
    PartnerDocumentType('address_proof', 'Address Proof'),
  ];

  /// A mental-health role — unlike Nutritionist/Hospital (which stay
  /// `docSlots: {}` by design, see `PARTNER_ROLES` in the admin panel), this
  /// one needs proof of who the applicant is and that they are actually
  /// qualified to counsel before an admin can approve them.
  static const counsellor = <PartnerDocumentType>[
    PartnerDocumentType('counsellor_id', 'Government ID Proof'),
    PartnerDocumentType('certificates', 'Certifications / Qualifications'),
  ];

  /// A clinical role, same reasoning as [counsellor]: a physiotherapist
  /// treats patients directly, so an admin needs ID + qualification proof
  /// before approval — this used to be the one role left at `docSlots: {}`
  /// alongside Nutritionist/Hospital, which was an intentional gap at the
  /// time but not the right end state for a hands-on clinical role.
  static const physiotherapist = <PartnerDocumentType>[
    PartnerDocumentType('physio_id', 'Government ID Proof'),
    PartnerDocumentType('physio_certificate', 'Physiotherapy Certification / Degree'),
  ];

  /// `role` is the same short token used for the Storage prefix and the
  /// `{role}_profiles` collection: 'lab' | 'pharmacy' | 'ambulance' |
  /// 'caregiver' | 'counsellor' | 'physiotherapist'.
  static List<PartnerDocumentType> forRole(String role) {
    switch (role) {
      case 'lab':
        return lab;
      case 'pharmacy':
        return pharmacy;
      case 'ambulance':
        return ambulance;
      case 'caregiver':
        return caregiver;
      case 'counsellor':
        return counsellor;
      case 'physiotherapist':
        return physiotherapist;
      default:
        return const [];
    }
  }
}

/// One entry of `{role}_profiles/{uid}.documents` — written by the partner
/// app on upload, never by admin.
class PartnerDocumentMeta {
  final String url;
  final String storagePath;
  final String fileName;
  final String contentType;
  final int sizeBytes;
  final DateTime? uploadedAt;

  const PartnerDocumentMeta({
    required this.url,
    required this.storagePath,
    required this.fileName,
    required this.contentType,
    required this.sizeBytes,
    required this.uploadedAt,
  });

  bool get isPdf => contentType == 'application/pdf';

  static PartnerDocumentMeta? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final url = raw['url']?.toString() ?? '';
    if (url.isEmpty) return null;
    final ts = raw['uploadedAt'];
    return PartnerDocumentMeta(
      url: url,
      storagePath: raw['storagePath']?.toString() ?? '',
      fileName: raw['fileName']?.toString() ?? '',
      contentType: raw['contentType']?.toString() ?? '',
      sizeBytes: (raw['sizeBytes'] as num?)?.toInt() ?? 0,
      uploadedAt: ts is Timestamp ? ts.toDate() : null,
    );
  }
}

enum PartnerDocumentStatus { notSubmitted, pending, verified, rejected }

/// One entry of `{role}_profiles/{uid}.documentVerification` — admin-only
/// writable (`firestore.rules` blocks the owner from modifying the whole
/// `documentVerification` key), so the partner app only ever reads this.
class PartnerDocumentVerification {
  final PartnerDocumentStatus status;
  final String? reason;
  final DateTime? verifiedAt;
  final String? verifiedBy;

  const PartnerDocumentVerification({
    required this.status,
    this.reason,
    this.verifiedAt,
    this.verifiedBy,
  });

  /// A missing entry means "uploaded but admin hasn't looked yet" when a file
  /// exists, and "nothing submitted" when it doesn't. A verification stamped
  /// *before* the current file was uploaded is stale (the partner replaced the
  /// document), so it also reads back as pending.
  static PartnerDocumentVerification fromMap(
    Object? raw, {
    required bool hasDocument,
    DateTime? uploadedAt,
  }) {
    if (raw is! Map) {
      return PartnerDocumentVerification(
        status: hasDocument
            ? PartnerDocumentStatus.pending
            : PartnerDocumentStatus.notSubmitted,
      );
    }

    final ts = raw['verifiedAt'];
    final verifiedAt = ts is Timestamp ? ts.toDate() : null;
    var status = switch (raw['status']?.toString()) {
      'verified' => PartnerDocumentStatus.verified,
      'rejected' => PartnerDocumentStatus.rejected,
      'pending' => PartnerDocumentStatus.pending,
      _ => hasDocument
          ? PartnerDocumentStatus.pending
          : PartnerDocumentStatus.notSubmitted,
    };

    if (!hasDocument) {
      status = PartnerDocumentStatus.notSubmitted;
    } else if (verifiedAt != null &&
        uploadedAt != null &&
        uploadedAt.isAfter(verifiedAt)) {
      status = PartnerDocumentStatus.pending;
    }

    return PartnerDocumentVerification(
      status: status,
      reason: raw['reason']?.toString(),
      verifiedAt: verifiedAt,
      verifiedBy: raw['verifiedBy']?.toString(),
    );
  }
}
