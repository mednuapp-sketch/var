import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

enum DeletionRequestResult { created, alreadyRequested }

/// Files an account-deletion request in `deletion_requests/{uid}` (create is
/// owner-only, read is owner/admin, update/delete is admin-only — see
/// firestore.rules). Google Play's User Data policy requires an in-app
/// deletion entry point; actual erasure is processed by the MedNU team so
/// records that must be retained by law (consultations, payments) are handled
/// correctly.
class AccountDeletionService {
  AccountDeletionService._();

  static Future<DeletionRequestResult> requestDeletion({required String role}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('Not signed in');

    final ref = FirebaseFirestore.instance.collection('deletion_requests').doc(user.uid);
    final existing = await ref.get();
    if (existing.exists) return DeletionRequestResult.alreadyRequested;

    await ref.set({
      'uid': user.uid,
      'role': role,
      'phone': user.phoneNumber ?? '',
      'email': user.email ?? '',
      'status': 'pending',
      'source': 'partner_app',
      'requestedAt': FieldValue.serverTimestamp(),
    });
    return DeletionRequestResult.created;
  }
}
