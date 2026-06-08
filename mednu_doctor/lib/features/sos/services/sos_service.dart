import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/emergency_contact.dart';

class SosService {
  SosService._();

  static CollectionReference<Map<String, dynamic>> _contactsRef(String uid) =>
      FirebaseFirestore.instance
          .collection('doctors')
          .doc(uid)
          .collection('emergency_contacts');

  static Stream<List<EmergencyContact>> contactsStream(String uid) =>
      _contactsRef(uid).snapshots().map(
            (snap) => snap.docs
                .map((d) => EmergencyContact.fromMap(d.data()))
                .toList(),
          );

  static Future<void> addContact(String uid, EmergencyContact contact) =>
      _contactsRef(uid).doc(contact.id).set(contact.toMap());

  static Future<void> deleteContact(String uid, String contactId) =>
      _contactsRef(uid).doc(contactId).delete();
}
