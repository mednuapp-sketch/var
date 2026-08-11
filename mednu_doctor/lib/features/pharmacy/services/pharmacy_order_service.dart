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

  /// Accepts (claims) a pending order. If the source order requires a
  /// prescription, it lands on `prescription_required` instead of jumping
  /// straight to `verified` — the pharmacist must review it first.
  static Future<void> acceptOrder(String orderId, String pharmacyId) => _transitionOrder(
        orderId,
        precondition: (d) => d['pharmacyId'] == null && d['status'] == 'pending',
        conflictMessage: 'This order was already claimed by another pharmacy.',
        buildUpdate: (d) => {
          'pharmacyId': pharmacyId,
          'status': (d['requiresPrescription'] as bool?) == true ? 'prescription_required' : 'verified',
        },
      );

  static Future<void> cancelOrder(String orderId, String pharmacyId) => _transitionOrder(
        orderId,
        precondition: (d) =>
            (d['pharmacyId'] == null || d['pharmacyId'] == pharmacyId) &&
            !['delivered', 'cancelled'].contains(d['status']),
        conflictMessage: 'This order can no longer be cancelled.',
        buildUpdate: (d) => {'pharmacyId': pharmacyId, 'status': 'cancelled'},
      );

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
  static Future<void> rejectPrescription(
    String orderId, {
    required String pharmacyId,
    required String reason,
  }) =>
      _transitionOrder(
        orderId,
        precondition: (d) => d['pharmacyId'] == pharmacyId && d['status'] == 'prescription_required',
        conflictMessage: 'This order is not awaiting prescription verification.',
        buildUpdate: (d) => {
          'status': 'cancelled',
          'prescriptionVerified': false,
          'prescriptionRejectedReason': reason,
        },
      );

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
