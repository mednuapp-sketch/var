import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/order_model.dart';

/// Realtime view of a single medicine order — the `orders` collection has
/// no existing Riverpod provider anywhere in the app (it's currently
/// write-only from `cart_screen.dart`), so this is new, additive
/// infrastructure rather than a change to `my_services_provider.dart`.
final orderDetailProvider =
    StreamProvider.autoDispose.family<OrderModel?, String>((ref, orderId) {
  if (orderId.isEmpty) return Stream.value(null);
  return FirebaseFirestore.instance
      .collection('orders')
      .doc(orderId)
      .snapshots()
      .map((snap) => snap.exists ? OrderModel.fromDoc(snap) : null);
});

/// This patient's medicine orders, most recent first — used only by the
/// new order-detail entry points added in this feature; doesn't touch or
/// replace `my_services`'s own booking list.
final myOrdersProvider = StreamProvider.autoDispose<List<OrderModel>>((ref) {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return Stream.value(const []);
  return FirebaseFirestore.instance
      .collection('orders')
      .where('patientId', isEqualTo: uid)
      .orderBy('createdAt', descending: true)
      .limit(30)
      .snapshots()
      .map((snap) => snap.docs.map(OrderModel.fromDoc).toList());
});
