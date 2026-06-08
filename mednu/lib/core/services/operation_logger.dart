import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

enum OpStatus { pending, success, error }

enum OpAction {
  // Booking
  bookingCreated,
  bookingCancelled,
  bookingRescheduled,
  bookingStatusChanged,
  // Profile
  profileUpdated,
  profilePictureUpdated,
  familyMemberAdded,
  familyMemberUpdated,
  familyMemberDeleted,
  // Medical
  prescriptionUploaded,
  prescriptionViewed,
  // Consultation
  consultationStarted,
  consultationEnded,
  // Health
  waterLogUpdated,
  periodTrackerUpdated,
  pregnancyDataUpdated,
  // Payment
  paymentInitiated,
  paymentCompleted,
  paymentFailed,
  // Reviews
  reviewSubmitted,
  // Auth
  accountCreated,
  passwordChanged,
  // Misc
  addressSaved,
  addressDeleted,
  referralSent,
}

class OperationLogger {
  static final _db   = FirebaseFirestore.instance;
  static final _auth = FirebaseAuth.instance;

  static String get _uid => _auth.currentUser?.uid ?? 'anonymous';

  static String _actionName(OpAction action) => action.name;

  /// Log any operation to Firestore `operation_logs` collection.
  static Future<void> log({
    required OpAction action,
    required OpStatus status,
    String? entityId,
    String? entityType,
    String? message,
    Map<String, dynamic>? metadata,
    String? errorDetails,
  }) async {
    try {
      await _db.collection('operation_logs').add({
        'userId':       _uid,
        'userType':     'patient',
        'action':       _actionName(action),
        'status':       status.name,
        'entityId':     entityId,
        'entityType':   entityType,
        'message':      message,
        'metadata':     metadata ?? {},
        'errorDetails': errorDetails,
        'timestamp':    FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // Logging must never crash the app — silently swallow.
    }
  }

  static Future<void> logSuccess({
    required OpAction action,
    String? entityId,
    String? entityType,
    String? message,
    Map<String, dynamic>? metadata,
  }) =>
      log(
        action: action,
        status: OpStatus.success,
        entityId: entityId,
        entityType: entityType,
        message: message,
        metadata: metadata,
      );

  static Future<void> logError({
    required OpAction action,
    required String errorDetails,
    String? entityId,
    String? entityType,
    String? message,
    Map<String, dynamic>? metadata,
  }) =>
      log(
        action: action,
        status: OpStatus.error,
        entityId: entityId,
        entityType: entityType,
        message: message,
        metadata: metadata,
        errorDetails: errorDetails,
      );

  static Future<void> logPending({
    required OpAction action,
    String? entityId,
    String? entityType,
    String? message,
    Map<String, dynamic>? metadata,
  }) =>
      log(
        action: action,
        status: OpStatus.pending,
        entityId: entityId,
        entityType: entityType,
        message: message,
        metadata: metadata,
      );

  /// Real-time stream of recent logs for the current user.
  static Stream<List<Map<String, dynamic>>> recentLogsStream({int limit = 20}) {
    if (_auth.currentUser == null) return Stream.value([]);
    return _db
        .collection('operation_logs')
        .where('userId', isEqualTo: _uid)
        .orderBy('timestamp', descending: true)
        .limit(limit)
        .snapshots()
        .map((s) => s.docs.map((d) => {'id': d.id, ...d.data()}).toList());
  }
}
