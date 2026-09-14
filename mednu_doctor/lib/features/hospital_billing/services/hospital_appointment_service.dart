import 'package:cloud_firestore/cloud_firestore.dart';

/// One `hospital_appointments/{id}` doc — the ₹99 OP registration token flow
/// (hospital_appointment_booking_screen.dart in mednu). Status flow:
/// booked -> checked_in -> completed, with `no_show` reachable from either
/// pre-completion state and `cancelled` reserved for the patient's own
/// cancel action (see firestore.rules' `hospital_appointments` update rule).
class HospitalAppointment {
  final String id;
  final String? patientId;
  final String patientName;
  final String? bookedByName;
  final String date;
  final String time;
  final String status;
  final String opToken;
  final String reasonForVisit;
  final List<String> symptoms;
  final double fee;
  final DateTime? createdAt;

  const HospitalAppointment({
    required this.id,
    required this.patientId,
    required this.patientName,
    required this.bookedByName,
    required this.date,
    required this.time,
    required this.status,
    required this.opToken,
    required this.reasonForVisit,
    required this.symptoms,
    required this.fee,
    required this.createdAt,
  });

  factory HospitalAppointment.fromFirestore(DocumentSnapshot doc) {
    final d = (doc.data() as Map<String, dynamic>?) ?? {};
    final ts = d['createdAt'];
    return HospitalAppointment(
      id: doc.id,
      patientId: d['patientId'] as String?,
      patientName: (d['patientName'] as String?)?.trim().isNotEmpty == true
          ? d['patientName'] as String
          : 'Patient',
      bookedByName: d['bookedByName'] as String?,
      date: d['date'] as String? ?? '',
      time: d['time'] as String? ?? '',
      status: d['status'] as String? ?? 'booked',
      opToken: d['opToken'] as String? ?? '',
      reasonForVisit: d['reasonForVisit'] as String? ?? '',
      symptoms: (d['symptoms'] as List?)?.whereType<String>().toList() ?? const [],
      fee: (d['fee'] as num?)?.toDouble() ?? 0,
      createdAt: ts is Timestamp ? ts.toDate() : null,
    );
  }
}

class HospitalAppointmentConflictException implements Exception {
  final String message;
  const HospitalAppointmentConflictException(this.message);
  @override
  String toString() => message;
}

class HospitalAppointmentService {
  HospitalAppointmentService._();

  static final _db = FirebaseFirestore.instance;

  /// Live-streamed queue for this hospital, newest booking first — a new
  /// booking (or a status change from another billing-desk device) shows up
  /// immediately, no manual refresh.
  static Stream<List<HospitalAppointment>> streamForHospital(String hospitalId) => _db
      .collection('hospital_appointments')
      .where('hospitalId', isEqualTo: hospitalId)
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map((s) => s.docs.map(HospitalAppointment.fromFirestore).toList());

  static Future<void> _transition(
    String appointmentId, {
    required String hospitalId,
    required List<String> from,
    required String to,
    required String timestampField,
  }) async {
    final ref = _db.collection('hospital_appointments').doc(appointmentId);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) {
        throw const HospitalAppointmentConflictException('This appointment no longer exists.');
      }
      final data = snap.data()!;
      if (data['hospitalId'] != hospitalId || !from.contains(data['status'])) {
        throw const HospitalAppointmentConflictException('This appointment can no longer be updated.');
      }
      tx.update(ref, {
        'status': to,
        timestampField: FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  /// The patient has arrived at reception with their OP token.
  static Future<void> checkIn(String appointmentId, {required String hospitalId}) =>
      _transition(appointmentId,
          hospitalId: hospitalId, from: const ['booked'], to: 'checked_in', timestampField: 'checkedInAt');

  /// The visit is done — the terminal, settlement-eligible state.
  static Future<void> markCompleted(String appointmentId, {required String hospitalId}) => _transition(
      appointmentId,
      hospitalId: hospitalId,
      from: const ['booked', 'checked_in'],
      to: 'completed',
      timestampField: 'completedAt');

  /// The patient never showed up for their slot.
  static Future<void> markNoShow(String appointmentId, {required String hospitalId}) => _transition(
      appointmentId,
      hospitalId: hospitalId,
      from: const ['booked', 'checked_in'],
      to: 'no_show',
      timestampField: 'noShowAt');
}
