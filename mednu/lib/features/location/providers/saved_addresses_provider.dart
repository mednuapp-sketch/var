import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/saved_address.dart';

// Stream of saved addresses for the current user
final savedAddressesProvider = StreamProvider<List<SavedAddress>>((ref) {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return Stream.value([]);
  return FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .collection('saved_addresses')
      .orderBy('updatedAt', descending: true)
      .snapshots()
      .map((snap) => snap.docs.map(SavedAddress.fromDoc).toList());
});

class SavedAddressesNotifier extends StateNotifier<AsyncValue<List<SavedAddress>>> {
  SavedAddressesNotifier() : super(const AsyncValue.loading());

  CollectionReference<Map<String, dynamic>>? get _col {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('saved_addresses');
  }

  Future<void> saveAddress(SavedAddress addr) async {
    final col = _col;
    if (col == null) return;
    if (addr.isDefault) await _clearDefaults(col);
    if (addr.id.isEmpty) {
      await col.add(addr.toMap());
    } else {
      await col.doc(addr.id).set(addr.toMap(), SetOptions(merge: true));
    }
  }

  Future<void> deleteAddress(String id) async {
    if (id.isEmpty) return;
    await _col?.doc(id).delete();
  }

  Future<void> setDefault(String id) async {
    if (id.isEmpty) return;
    final col = _col;
    if (col == null) return;
    await _clearDefaults(col);
    await col.doc(id).update({'isDefault': true});
  }

  Future<void> _clearDefaults(CollectionReference col) async {
    final snap = await col.where('isDefault', isEqualTo: true).get();
    final batch = FirebaseFirestore.instance.batch();
    for (final doc in snap.docs) {
      batch.update(doc.reference, {'isDefault': false});
    }
    await batch.commit();
  }
}

final savedAddressesNotifierProvider = StateNotifierProvider<
    SavedAddressesNotifier, AsyncValue<List<SavedAddress>>>(
  (_) => SavedAddressesNotifier(),
);
