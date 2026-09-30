import 'package:cloud_firestore/cloud_firestore.dart';

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
class PendingProfileEditService {
  PendingProfileEditService._();

  static Future<void> apply({
    required DocumentReference<Map<String, dynamic>> ref,
    required String currentStatus,
    required Map<String, dynamic> fields,
  }) {
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
