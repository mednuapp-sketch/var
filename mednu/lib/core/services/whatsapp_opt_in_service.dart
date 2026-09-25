import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Shared persistence for the WhatsApp notifications opt-in toggle —
/// used by [WhatsAppOptInTile] callers and by any settings screen that
/// renders its own matching tile instead of that widget for visual
/// consistency with its existing toggle style.
class WhatsAppOptInService {
  WhatsAppOptInService._();

  /// Merges the opt-in fields onto `users/{uid}` — safe to call even before
  /// the rest of the profile exists (creates just these fields), and never
  /// touches any other field on the document.
  static Future<void> save({
    required String uid,
    required bool value,
    required String language,
  }) {
    return FirebaseFirestore.instance.collection('users').doc(uid).set({
      'whatsappOptIn': value,
      'whatsappPhone': FirebaseAuth.instance.currentUser?.phoneNumber ?? '',
      'language': language,
      'whatsappOptInUpdatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}
