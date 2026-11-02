import 'package:cloud_firestore/cloud_firestore.dart';

import '../documents/partner_document_models.dart';

/// Applies a partner's profile self-edit the way firestore.rules requires it:
/// once a profile is 'active' (live and visible to patients), a self-edit can
/// no longer touch the fields patients actually see directly — it's diverted
/// into a `pendingChanges` snapshot instead, and only takes effect once an
/// admin approves it (see mednu-admin's "Pending Profile Edits" tab). While
/// still 'pending' (awaiting the very first approval), edits still apply
/// immediately — there's no live, patient-facing version to protect yet.
///
/// Shared by every partner role (caregiver/counsellor/nutritionist/
/// physiotherapist/lab/pharmacy/ambulance) since they all follow this exact
/// same status/approval shape.
///
/// Nothing is sent for review while a required verification document is
/// missing from the profile.
class PendingProfileEditService {
  PendingProfileEditService._();

  static Future<void> apply({
    required DocumentReference<Map<String, dynamic>> ref,
    required String currentStatus,
    required Map<String, dynamic> fields,
  }) async {
    // `lab_profiles` -> 'lab', `physiotherapist_profiles` -> 'physiotherapist'.
    final role = ref.parent.id.replaceAll('_profiles', '');
    if (PartnerDocumentType.forRole(role).isNotEmpty) {
      final snap = await ref.get();
      final missing =
          PartnerDocumentType.missingFor(role, snap.data()?['documents']);
      if (missing.isNotEmpty) {
        throw Exception(
          'Upload your required documents before submitting for review: '
          '${missing.join(', ')}.',
        );
      }
    }

    if (currentStatus == 'active') {
      return ref.set({
        'pendingChanges': fields,
        'hasPendingChanges': true,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
    return ref.set({
      ...fields,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}
