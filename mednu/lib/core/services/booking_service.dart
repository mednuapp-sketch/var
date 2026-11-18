import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'operation_logger.dart';

class BookingService {
  static final _db   = FirebaseFirestore.instance;
  static final _auth = FirebaseAuth.instance;

  /// Free (zero-price) booking created SERVER-side via the `createFreeBooking`
  /// callable. Used instead of a direct Firestore write while the real-payments
  /// switch (`PaymentConfig.requirePayment`) is ON, because firestore.rules then
  /// deny client creates of booking docs. The server verifies the real price is
  /// zero. Pass the SAME [idempotencyKey] on retry (no duplicate booking).
  /// Returns the booking id; throws a readable [Exception] on failure.
  static Future<String> createFreeBooking({
    required String serviceType,
    required String bookingCollection,
    required Map<String, dynamic> bookingData,
    required String idempotencyKey,
  }) async {
    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable('createFreeBooking')
          .call({
        'serviceType': serviceType,
        'bookingCollection': bookingCollection,
        'bookingData': bookingData,
        'idempotencyKey': idempotencyKey,
      });
      final id = ((result.data as Map?) ?? const {})['bookingId'];
      if (id is! String || id.isEmpty) {
        throw Exception('Booking could not be created. Please try again.');
      }
      return id;
    } on FirebaseFunctionsException catch (e) {
      throw Exception(e.message ?? 'Booking could not be created. Please try again.');
    }
  }

  /// Creates a service request in Firestore and logs the operation.
  /// Returns the new document ID on success, throws on failure.
  static Future<String> createRequest({
    required String type,
    required String serviceName,
    required String patientName,
    required String patientPhone,
    required String address,
    required String preferredDate,
    required String preferredTime,
    String notes = '',
    Map<String, dynamic> serviceDetails = const {},
    num? amount,
    // Lets a caller pre-assign a specific provider (e.g. {'physiotherapistId':
    // id} from booking a specific physiotherapist rather than requesting any
    // available one) — merged straight into the request doc. The Cloud
    // Function mirror for that module (see functions/index.js
    // `_buildSessionDoc`) honors this field and skips the unclaimed pool.
    Map<String, dynamic> extraFields = const {},
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null || uid.isEmpty) throw Exception('User not authenticated');

    await OperationLogger.logPending(
      action: OpAction.bookingCreated,
      entityType: type,
      message: 'Creating $serviceName request...',
      metadata: {'serviceName': serviceName, 'date': preferredDate},
    );

    try {
      final ref = await _db.collection('service_requests').add({
        'type':           type,
        'serviceName':    serviceName,
        'patientId':      uid,
        'patientName':    patientName,
        'patientPhone':   patientPhone,
        'address':        address,
        'preferredDate':  preferredDate,
        'preferredTime':  preferredTime,
        'notes':          notes,
        'serviceDetails': serviceDetails,
        'amount':         amount,
        'status':         'pending',
        'assignedTo':     null,
        ...extraFields,
        'createdAt':      FieldValue.serverTimestamp(),
        'updatedAt':      FieldValue.serverTimestamp(),
      });

      await OperationLogger.logSuccess(
        action: OpAction.bookingCreated,
        entityId: ref.id,
        entityType: type,
        message: '$serviceName request created successfully',
        metadata: {'serviceName': serviceName, 'requestId': ref.id},
      );

      return ref.id;
    } catch (e) {
      await OperationLogger.logError(
        action: OpAction.bookingCreated,
        entityType: type,
        message: 'Failed to create $serviceName request',
        errorDetails: e.toString(),
        metadata: {'serviceName': serviceName},
      );
      rethrow;
    }
  }

  static Stream<List<Map<String, dynamic>>> userRequestsStream() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return Stream.value([]);
    return _db
        .collection('service_requests')
        .where('patientId', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((s) => s.docs.map((d) => {'id': d.id, ...d.data()}).toList());
  }
}
