import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'operation_logger.dart';

class BookingService {
  static final _db   = FirebaseFirestore.instance;
  static final _auth = FirebaseAuth.instance;

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
  }) async {
    final uid = _auth.currentUser?.uid ?? '';

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
        'status':         'pending',
        'assignedTo':     null,
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
