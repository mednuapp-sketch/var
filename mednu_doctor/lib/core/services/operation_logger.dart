import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

enum OpStatus { pending, success, error }

enum DoctorOpAction {
  // Availability
  wentOnline,
  wentOffline,
  availabilityUpdated,
  // Appointments
  appointmentAccepted,
  appointmentRejected,
  appointmentCompleted,
  appointmentRescheduled,
  // Consultation
  consultationStarted,
  consultationEnded,
  consultationMissed,
  // Prescription
  prescriptionWritten,
  prescriptionSent,
  // Profile
  profileUpdated,
  profilePictureUpdated,
  specializationChangeRequested,
  // Patients
  patientNoteAdded,
  patientViewed,
  // Earnings
  earningsViewed,
  // Reviews
  reviewResponded,
}

class OperationLogger {
  static final _db   = FirebaseFirestore.instance;
  static final _auth = FirebaseAuth.instance;

  static String get _uid => _auth.currentUser?.uid ?? 'anonymous';

  static String _actionName(DoctorOpAction action) => action.name;

  static Future<void> log({
    required DoctorOpAction action,
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
        'userType':     'doctor',
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
      // Logging must never crash the app.
    }
  }

  static Future<void> logSuccess({
    required DoctorOpAction action,
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
    required DoctorOpAction action,
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
    required DoctorOpAction action,
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
}
