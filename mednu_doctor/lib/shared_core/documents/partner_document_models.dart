import 'package:cloud_firestore/cloud_firestore.dart';

/// Shared, role-parameterised model layer for partner verification documents.
///
/// One canonical set of `docType` keys is used everywhere — Firestore field
/// names under `{role}_profiles/{uid}.documents`, Storage path segments under
/// `{role}_documents/{uid}/`, and the Admin panel's `PARTNER_ROLES.docSlots`.
/// Changing a key here means changing it in all three places.

/// A document slot a role fills in. `key` is the canonical docType.
/// [optional] slots can be left empty — they never block submission or
/// admin approval.
class PartnerDocumentType {
  final String key;
  final String label;
  final bool optional;

  const PartnerDocumentType(this.key, this.label, {this.optional = false});

  // The lists below follow the client's document checklist per partner type.
  // Where an old docType key still describes the same document it is reused,
  // so files already uploaded by existing partners stay attached.

  static const lab = <PartnerDocumentType>[
    PartnerDocumentType('lab_license', 'Lab Licence'),
    PartnerDocumentType('maridi_certificate', 'Maridi Certificate'),
    PartnerDocumentType('lab_technician_details', 'Lab Technician Details'),
    PartnerDocumentType('pathologist_registration',
        'Biochemist / Pathologist / Microbiologist Details (as per lab type)'),
    PartnerDocumentType('trade_license', 'Trade Licence', optional: true),
    PartnerDocumentType('gst_certificate', 'GST Certificate'),
  ];

  static const pharmacy = <PartnerDocumentType>[
    PartnerDocumentType('pharmacy_license', 'Drug Licence Forms'),
    PartnerDocumentType('pharmacist_registration', 'Pharmacist Details'),
    PartnerDocumentType('trade_license', 'Trade Licence'),
    PartnerDocumentType('gst_certificate', 'GST Certificate'),
  ];

  /// Client checklist for "Pharmacy & Equipment" is a single shared list.
  static const equipment = pharmacy;

  static const ambulance = <PartnerDocumentType>[
    PartnerDocumentType('driver_license', "Driver's Licence"),
    PartnerDocumentType('vehicle_fitness', 'Ambulance Certificate'),
    PartnerDocumentType('vehicle_registration', 'C Book (RC Book)'),
    PartnerDocumentType('vehicle_insurance', 'Insurance'),
    PartnerDocumentType('pollution_certificate', 'Pollution Certificate'),
  ];

  /// Nurse (stored under `caregiver_profiles`).
  static const caregiver = <PartnerDocumentType>[
    PartnerDocumentType('certificates',
        'Basic Qualification + ANM / GNM / B.Sc. Nursing'),
    PartnerDocumentType('resume', 'Resume', optional: true),
    PartnerDocumentType('caregiver_id', 'Government ID Proof'),
  ];

  /// Care Assistant — shares `caregiver_profiles`, but needs only an ID.
  static const careAssistant = <PartnerDocumentType>[
    PartnerDocumentType('caregiver_id', 'Government ID Proof'),
  ];

  /// A mental-health role — not part of the client's checklist, unchanged.
  static const counsellor = <PartnerDocumentType>[
    PartnerDocumentType('counsellor_id', 'Government ID Proof'),
    PartnerDocumentType('certificates', 'Certifications / Qualifications'),
  ];

  /// Physiotherapy / Dental.
  static const physiotherapist = <PartnerDocumentType>[
    PartnerDocumentType('ug_certificate', 'UG Degree'),
    PartnerDocumentType('pg_certificate', 'PG Degree', optional: true),
    PartnerDocumentType('renewal_certificate', 'Renewal Certificate'),
    PartnerDocumentType('registration_state', 'Registration - State'),
    PartnerDocumentType('registration_national', 'Registration - National'),
    PartnerDocumentType('other_certificate', 'Others', optional: true),
  ];

  /// Dietician.
  static const nutritionist = <PartnerDocumentType>[
    PartnerDocumentType('ug_certificate', 'UG Degree'),
    PartnerDocumentType('pg_certificate', 'PG Degree', optional: true),
    PartnerDocumentType('registration_certificate', 'Registration Certificate'),
    PartnerDocumentType('other_certificate', 'Others', optional: true),
  ];

  static const hospital = <PartnerDocumentType>[
    PartnerDocumentType('dmho_license', 'DM&HO Licence'),
    PartnerDocumentType('fire_certificate', 'Fire Certificate'),
    PartnerDocumentType('maridi_certificate', 'Maridi Certificate'),
    PartnerDocumentType('gvmc_certificate', 'GVMC Certificate'),
    PartnerDocumentType('pollution_certificate', 'Pollution Certificate'),
    PartnerDocumentType('trade_license', 'Trade Licence'),
    PartnerDocumentType('gst_certificate', 'GST Certificate'),
    PartnerDocumentType('hospital_resume', 'Hospital Resume', optional: true),
  ];

  /// Optional, partner-typed extra documents (`other_doc_1` .. `other_doc_5`)
  /// available to every role. Deliberately NOT part of [forRole] / [missingFor]
  /// — they never block submission or admin approval.
  static const int maxOtherDocs = 5;
  static const int maxOtherLabelLength = 60;
  static const String otherDocPrefix = 'other_doc_';

  static String otherDocKey(int n) => '$otherDocPrefix$n';

  static bool isOtherDocKey(String key) => key.startsWith(otherDocPrefix);

  /// Keys `other_doc_N` present in [documents], sorted by N.
  static List<String> otherDocKeysIn(Object? documents) {
    final map = documents is Map ? documents : const {};
    final keys = [
      for (final k in map.keys)
        if (k is String &&
            isOtherDocKey(k) &&
            PartnerDocumentMeta.fromMap(map[k]) != null)
          k,
    ]..sort();
    return keys;
  }

  /// First free `other_doc_N` slot given [usedKeys], or null at the cap.
  static String? nextFreeOtherDocKey(Iterable<String> usedKeys) {
    final used = usedKeys.toSet();
    for (var n = 1; n <= maxOtherDocs; n++) {
      if (!used.contains(otherDocKey(n))) return otherDocKey(n);
    }
    return null;
  }

  /// Labels of the required documents for [role] that have no uploaded file
  /// in [documents] (the `{role}_profiles/{uid}.documents` map). Empty means
  /// the profile is complete enough to go to admin review.
  static List<String> missingFor(String role, Object? documents) {
    final map = documents is Map ? documents : const {};
    return [
      for (final type in forRole(role))
        if (!type.optional && PartnerDocumentMeta.fromMap(map[type.key]) == null)
          type.label,
    ];
  }

  /// `role` is the same short token used for the Storage prefix and the
  /// `{role}_profiles` collection: 'lab' | 'pharmacy' | 'equipment' | 'ambulance' |
  /// 'caregiver' | 'care_assistant' | 'counsellor' | 'physiotherapist' | 'nutritionist' |
  /// 'hospital'.
  static List<PartnerDocumentType> forRole(String role) {
    switch (role) {
      case 'lab':
        return lab;
      case 'pharmacy':
        return pharmacy;
      case 'equipment':
        return equipment;
      case 'ambulance':
        return ambulance;
      case 'caregiver':
        return caregiver;
      case 'care_assistant':
        return careAssistant;
      case 'counsellor':
        return counsellor;
      case 'physiotherapist':
        return physiotherapist;
      case 'nutritionist':
        return nutritionist;
      case 'hospital':
        return hospital;
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

  /// Partner-typed title — only set on `other_doc_N` entries.
  final String? label;

  const PartnerDocumentMeta({
    required this.url,
    required this.storagePath,
    required this.fileName,
    required this.contentType,
    required this.sizeBytes,
    required this.uploadedAt,
    this.label,
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
      label: raw['label']?.toString(),
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
