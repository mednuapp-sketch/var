import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Shared persistence for the WhatsApp notifications opt-in toggle, used by
/// every partner role's settings screen. `mednu_doctor` has no i18n
/// framework, so `language` is always written as the fixed default `'en'`
/// (matches `WHATSAPP_DEFAULT_LANG` in functions/whatsapp/config.js).
class WhatsAppOptInService {
  WhatsAppOptInService._();

  static Future<void> save({
    required String collection,
    required String uid,
    required bool value,
  }) {
    return FirebaseFirestore.instance.collection(collection).doc(uid).set({
      'whatsappOptIn': value,
      'whatsappPhone': FirebaseAuth.instance.currentUser?.phoneNumber ?? '',
      'language': 'en',
      'whatsappOptInUpdatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}
