import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

/// Thrown when a status-changing action can't proceed because the order's
/// current state no longer matches what the caller expected — most
/// commonly, a second pharmacy claimed the order a moment earlier.
class PharmacyOrderConflictException implements Exception {
  final String message;
  const PharmacyOrderConflictException(this.message);
  @override
  String toString() => message;
}

/// All Firestore/Storage access for the Pharmacy module lives here —
/// screens never touch `FirebaseFirestore`/`FirebaseStorage` directly.
/// Every write only ever touches `pharmacy_orders`, `pharmacy_order_items`,
/// and Storage under `pharmacy_prescriptions/{orderId}/...`. Nothing here
/// writes to `orders` or `service_requests` — the Cloud Function mirror
/// (`functions/index.js`) is the only writer of those on this module's
/// behalf, exactly like the Lab module's relationship with
/// `service_requests`.
class PharmacyOrderService {
  PharmacyOrderService._();

  static final _db = FirebaseFirestore.instance;
  static final _storage = FirebaseStorage.instance;

  static const int pageSize = 20;

  static Stream<QuerySnapshot<Map<String, dynamic>>> availableOrdersStream() {
    return _db
        .collection('pharmacy_orders')
        .where('pharmacyId', isNull: true)
        .where('status', isEqualTo: 'pending')
        .orderBy('createdAt', descending: true)
        .limit(30)
        .snapshots();
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> myOrdersFirstPageStream(
    String pharmacyId, {
    String? statusFilter,
  }) {
    Query<Map<String, dynamic>> q = _db
        .collection('pharmacy_orders')
        .where('pharmacyId', isEqualTo: pharmacyId);
    if (statusFilter != null) q = q.where('status', isEqualTo: statusFilter);
    return q.orderBy('createdAt', descending: true).limit(pageSize).snapshots();
  }

  static Future<QuerySnapshot<Map<String, dynamic>>> fetchMoreMyOrders(
    String pharmacyId, {
    required DocumentSnapshot<Map<String, dynamic>> startAfter,
    String? statusFilter,
  }) {
    Query<Map<String, dynamic>> q = _db
        .collection('pharmacy_orders')
        .where('pharmacyId', isEqualTo: pharmacyId);
    if (statusFilter != null) q = q.where('status', isEqualTo: statusFilter);
    return q
        .orderBy('createdAt', descending: true)
        .startAfterDocument(startAfter)
        .limit(pageSize)
        .get();
  }

  static Stream<DocumentSnapshot<Map<String, dynamic>>> orderStream(String orderId) =>
      _db.collection('pharmacy_orders').doc(orderId).snapshots();

  static Stream<QuerySnapshot<Map<String, dynamic>>> myAllOrdersStream(String pharmacyId) {
    return _db
        .collection('pharmacy_orders')
        .where('pharmacyId', isEqualTo: pharmacyId)
        .snapshots();
  }

  static Stream<List<Map<String, dynamic>>> orderItemsStream(String orderId) {
    return _db
        .collection('pharmacy_order_items')
        .where('orderId', isEqualTo: orderId)
        .snapshots()
        .map((s) => s.docs.map((d) => {'id': d.id, ...d.data()}).toList());
  }

  /// Orders currently in the delivery pipeline (packed → out for delivery)
  /// for this pharmacy — the operational queue the Delivery Tracking
  /// screen shows.
  static Stream<QuerySnapshot<Map<String, dynamic>>> deliveryQueueStream(String pharmacyId) {
    return _db
        .collection('pharmacy_orders')
        .where('pharmacyId', isEqualTo: pharmacyId)
        .where('status', whereIn: ['packed', 'out_for_delivery'])
        .snapshots();
  }

  // ── Status transitions ─────────────────────────────────────────────────
  //
  // Every transition reads the order inside a Firestore transaction and
  // re-checks its *current* state before writing — the same pattern
  // (with the same reasoning) as the Lab module's `_transitionBooking`,
  // applied from the start here rather than retrofitted.

  static Future<void> _transitionOrder(
    String orderId, {
    required bool Function(Map<String, dynamic> data) precondition,
    required String conflictMessage,
    required Map<String, dynamic> Function(Map<String, dynamic> data) buildUpdate,
  }) {
    final ref = _db.collection('pharmacy_orders').doc(orderId);
    return _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) {
        throw const PharmacyOrderConflictException('This order no longer exists.');
      }
      final data = snap.data()!;
      if (!precondition(data)) {
        throw PharmacyOrderConflictException(conflictMessage);
      }
      tx.update(ref, {
        ...buildUpdate(data),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  /// Resolves each of [orderId]'s line items that were sourced from this
  /// pharmacy's own inventory (`medicineId` matching
  /// `phinv_{pharmacyId}_{itemId}`) to its inventory doc ref and total
  /// ordered quantity. Order items are written once, in the same batch as
  /// the order itself, and never rewritten afterward (see
  /// onMedicineOrderCreated in functions/index.js) — safe to read outside
  /// the transaction the caller runs this inside of.
  ///
  /// Shared by [acceptOrder] (decrements stock once, when status first
  /// leaves 'pending') and [cancelOrder]/[rejectPrescription] (restore
  /// whatever accept decremented, since a cancelled/rejected order never
  /// actually consumes that stock).
  static Future<List<MapEntry<DocumentReference<Map<String, dynamic>>, int>>>
      _ownInventoryDeltas(String orderId, String pharmacyId) async {
    final itemsSnap = await _db
        .collection('pharmacy_order_items')
        .where('orderId', isEqualTo: orderId)
        .get();

    final prefix = 'phinv_${pharmacyId}_';
    final byRef = <DocumentReference<Map<String, dynamic>>, int>{};
    for (final doc in itemsSnap.docs) {
      final medicineId = doc.data()['medicineId'] as String?;
      if (medicineId == null || !medicineId.startsWith(prefix)) continue;
      final itemId = medicineId.substring(prefix.length);
      final ref = _db
          .collection('pharmacy_profiles')
          .doc(pharmacyId)
          .collection('inventory')
          .doc(itemId);
      byRef[ref] = (byRef[ref] ?? 0) + ((doc.data()['count'] as num?)?.toInt() ?? 1);
    }
    return byRef.entries.toList();
  }

  /// Accepts a pending order — either claims it from the shared unclaimed
  /// pool (`pharmacyId == null`, another pharmacy might grab it first) or
  /// confirms one already pinned to this pharmacy (a patient ordered
  /// straight from this pharmacy's own menu — see onMedicineOrderCreated's
  /// `pinnedPharmacyId` branch in functions/index.js, which sets `status:
  /// 'pending'` regardless of whether it pinned a pharmacy or not). Mirrors
  /// `cancelOrder`'s precondition below — that one already allowed both
  /// cases; this one only allowed the pool-claim case, so accepting a
  /// pharmacy's own pinned order always failed with a "claimed by another
  /// pharmacy" error that was never actually true.
  ///
  /// Also decrements this pharmacy's own inventory stock for every line item
  /// sourced from it (`pharmacy_order_items.medicineId` matching
  /// `phinv_{pharmacyId}_{itemId}`), inside the same transaction as the
  /// status write, and refuses to accept at all if any of those items don't
  /// have enough stock left. Items with no resolvable inventory doc (an
  /// admin-added catalogue medicine, or one sourced from a different
  /// pharmacy via the shared claim pool) are left untouched — there is
  /// nothing owned by this pharmacy to decrement for them.
  static Future<void> acceptOrder(String orderId, String pharmacyId) async {
    final orderRef = _db.collection('pharmacy_orders').doc(orderId);
    final stockEntries = await _ownInventoryDeltas(orderId, pharmacyId);

    await _db.runTransaction((tx) async {
      final snap = await tx.get(orderRef);
      if (!snap.exists) {
        throw const PharmacyOrderConflictException('This order no longer exists.');
      }
      final data = snap.data()!;
      if (!((data['pharmacyId'] == null || data['pharmacyId'] == pharmacyId) &&
          data['status'] == 'pending')) {
        throw const PharmacyOrderConflictException('This order was already claimed by another pharmacy.');
      }

      if (stockEntries.isNotEmpty) {
        final invSnaps = await Future.wait(stockEntries.map((e) => tx.get(e.key)));
        for (var i = 0; i < invSnaps.length; i++) {
          final have = (invSnaps[i].data()?['stock'] as int?) ?? 0;
          if (!invSnaps[i].exists || have < stockEntries[i].value) {
            final name = invSnaps[i].data()?['name'] as String? ?? 'An item';
            throw PharmacyOrderConflictException(
              '$name is out of stock — update your inventory before accepting this order.',
            );
          }
        }
        for (var i = 0; i < invSnaps.length; i++) {
          tx.update(invSnaps[i].reference, {'stock': FieldValue.increment(-stockEntries[i].value)});
        }
      }

      tx.update(orderRef, {
        'pharmacyId': pharmacyId,
        'status': (data['requiresPrescription'] as bool?) == true ? 'prescription_required' : 'verified',
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  /// Restores whatever [acceptOrder] decremented if this order had already
  /// been accepted (status past 'pending') — a cancelled order never
  /// actually consumes that stock. A still-'pending' order was never
  /// decremented, so there's nothing to restore.
  static Future<void> cancelOrder(String orderId, String pharmacyId) async {
    final orderRef = _db.collection('pharmacy_orders').doc(orderId);
    final stockEntries = await _ownInventoryDeltas(orderId, pharmacyId);

    await _db.runTransaction((tx) async {
      final snap = await tx.get(orderRef);
      if (!snap.exists) {
        throw const PharmacyOrderConflictException('This order no longer exists.');
      }
      final data = snap.data()!;
      if (!((data['pharmacyId'] == null || data['pharmacyId'] == pharmacyId) &&
          !['delivered', 'cancelled'].contains(data['status']))) {
        throw const PharmacyOrderConflictException('This order can no longer be cancelled.');
      }

      if (data['status'] != 'pending') {
        for (final e in stockEntries) {
          tx.set(e.key, {'stock': FieldValue.increment(e.value)}, SetOptions(merge: true));
        }
      }

      tx.update(orderRef, {
        'pharmacyId': pharmacyId,
        'status': 'cancelled',
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  /// Approves the patient-uploaded prescription and moves the order
  /// forward. Sets `prescriptionVerified: true`, which the Cloud Function
  /// mirror (`onPharmacyOrderStatusChange`) copies onto the real `orders`
  /// doc and notifies the patient about — this service never touches
  /// `orders` directly.
  static Future<void> verifyPrescription(String orderId, {required String pharmacyId}) =>
      _transitionOrder(
        orderId,
        precondition: (d) => d['pharmacyId'] == pharmacyId && d['status'] == 'prescription_required',
        conflictMessage: 'This order is not awaiting prescription verification.',
        buildUpdate: (d) => {
          'status': 'verified',
          'prescriptionVerified': true,
          'prescriptionRejectedReason': null,
        },
      );

  /// A hard rejection — the prescription is invalid for what was ordered
  /// (e.g. wrong medicine, expired, illegible beyond re-upload) and the
  /// order is cancelled. [reason] is shown to the patient verbatim.
  ///
  /// 'prescription_required' is only ever reached via [acceptOrder], so
  /// stock was unconditionally decremented already — restore it here too.
  static Future<void> rejectPrescription(
    String orderId, {
    required String pharmacyId,
    required String reason,
  }) async {
    final orderRef = _db.collection('pharmacy_orders').doc(orderId);
    final stockEntries = await _ownInventoryDeltas(orderId, pharmacyId);

    await _db.runTransaction((tx) async {
      final snap = await tx.get(orderRef);
      if (!snap.exists) {
        throw const PharmacyOrderConflictException('This order no longer exists.');
      }
      final data = snap.data()!;
      if (!(data['pharmacyId'] == pharmacyId && data['status'] == 'prescription_required')) {
        throw const PharmacyOrderConflictException('This order is not awaiting prescription verification.');
      }

      for (final e in stockEntries) {
        tx.set(e.key, {'stock': FieldValue.increment(e.value)}, SetOptions(merge: true));
      }

      tx.update(orderRef, {
        'status': 'cancelled',
        'prescriptionVerified': false,
        'prescriptionRejectedReason': reason,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  /// A soft rejection — the order stays alive; the patient is asked to
  /// re-upload (e.g. a blurry photo). Deliberately does not touch `status`
  /// (stays `prescription_required`) or clear the existing
  /// `prescriptionUrl` — the patient can still see what they uploaded
  /// while they prepare a better copy; uploading a new one overwrites it.
  static Future<void> requestClearerPrescription(
    String orderId, {
    required String pharmacyId,
    required String reason,
  }) =>
      _transitionOrder(
        orderId,
        precondition: (d) => d['pharmacyId'] == pharmacyId && d['status'] == 'prescription_required',
        conflictMessage: 'This order is not awaiting prescription verification.',
        buildUpdate: (d) => {
          'prescriptionVerified': false,
          'prescriptionRejectedReason': reason,
        },
      );

  static Future<void> markPacked(String orderId, {required String pharmacyId}) => _transitionOrder(
        orderId,
        precondition: (d) => d['pharmacyId'] == pharmacyId && d['status'] == 'verified',
        conflictMessage: 'This order is not ready to be packed.',
        buildUpdate: (d) => {'status': 'packed'},
      );

  static Future<void> markOutForDelivery(
    String orderId, {
    required String pharmacyId,
    required String deliveryPersonName,
  }) =>
      _transitionOrder(
        orderId,
        precondition: (d) => d['pharmacyId'] == pharmacyId && d['status'] == 'packed',
        conflictMessage: 'This order is not ready to go out for delivery.',
        buildUpdate: (d) => {'status': 'out_for_delivery', 'deliveryPersonName': deliveryPersonName},
      );

  /// Retry-safe: also accepts an already-`delivered` order as a no-op
  /// success rather than an error — the ledger credit in
  /// `onPharmacyOrderStatusChange` is separately idempotent either way.
  static Future<void> markDelivered(String orderId, {required String pharmacyId}) => _transitionOrder(
        orderId,
        precondition: (d) =>
            d['pharmacyId'] == pharmacyId &&
            (d['status'] == 'out_for_delivery' || d['status'] == 'delivered'),
        conflictMessage: 'This order is not out for delivery.',
        buildUpdate: (d) => {'status': 'delivered'},
      );

  // ── Prescription photo upload ─────────────────────────────────────────
  //
  // There is currently no patient-side prescription upload in MedNu Patient
  // — this is the pharmacy attaching the photo it verified against (e.g.
  // collected at hand-off, or received by call/WhatsApp outside the app),
  // which is why this writes `prescriptionUrl` without changing `status`
  // itself; verifying is a separate explicit action (`verifyPrescription`).
  static Future<String> uploadPrescriptionPhoto({
    required String orderId,
    required String pharmacyId,
    required File file,
  }) async {
    final fileName = file.path.split(Platform.pathSeparator).last;
    final storagePath =
        'pharmacy_prescriptions/$orderId/${DateTime.now().millisecondsSinceEpoch}_$fileName';
    final ref = _storage.ref(storagePath);
    await ref.putFile(file);
    final downloadUrl = await ref.getDownloadURL();

    await _transitionOrder(
      orderId,
      precondition: (d) => d['pharmacyId'] == pharmacyId,
      conflictMessage: 'You no longer own this order.',
      buildUpdate: (d) => {'prescriptionUrl': downloadUrl},
    );
    return downloadUrl;
  }
}
