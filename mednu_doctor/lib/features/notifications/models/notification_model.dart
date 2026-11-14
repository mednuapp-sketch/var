import 'package:cloud_firestore/cloud_firestore.dart';

enum NotifType {
  consultationRequest,
  emergencyRequest,
  review,
  payment,
  appointment,
  summary,
  patientFollowup,
  accountApproved,
  accountRejected,
  /// New / cancelled booking, order, session or job for a partner role
  /// (`new_lab_booking`, `new_pharmacy_order`, `new_ambulance_request`, ...).
  booking,
  unknown,
}

class NotificationModel {
  final String id;
  final NotifType type;
  final String title;
  final String body;
  final DateTime createdAt;
  final bool isRead;
  final Map<String, dynamic> payload;

  const NotificationModel({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.createdAt,
    required this.isRead,
    this.payload = const {},
  });

  static NotifType _typeFrom(String raw) {
    switch (raw) {
      case 'consultation_request': return NotifType.consultationRequest;
      case 'emergency_request':    return NotifType.emergencyRequest;
      case 'review':               return NotifType.review;
      case 'payment':              return NotifType.payment;
      // Backend `_sendProviderNotification` earnings/settlement types.
      case 'new_earnings':
      case 'settlement_approved':
      case 'money_sent':           return NotifType.payment;
      case 'appointment':          return NotifType.appointment;
      case 'summary':              return NotifType.summary;
      case 'patient_followup':     return NotifType.patientFollowup;
      case 'account_approved':     return NotifType.accountApproved;
      case 'account_rejected':     return NotifType.accountRejected;
      case 'booking_cancelled_by_patient':
      case 'nutrition_cancelled':
      case 'hospital_appointment_cancelled':
                                   return NotifType.booking;
      default:
        // Every backend "new job for you" push is `new_<service>_<noun>`
        // (new_lab_booking, new_pharmacy_order, new_equipment_order,
        // new_physio_session, new_counselling_session, new_ambulance_request,
        // new_caregiver_visit, new_appointment, new_nutrition_appointment,
        // new_hospital_appointment). `new_earnings` is matched above.
        if (raw.startsWith('new_')) return NotifType.booking;
        return NotifType.unknown;
    }
  }

  factory NotificationModel.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    return NotificationModel(
      id:        doc.id,
      type:      _typeFrom(d['type'] as String? ?? ''),
      title:     d['title'] as String? ?? '',
      body:      d['body'] as String? ?? '',
      createdAt: (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      isRead:    d['isRead'] as bool? ?? false,
      // `provider_notifications` (written by the backend's
      // `_sendProviderNotification` helper) names this field `data`, not
      // `payload` — accept either so that collection renders correctly too.
      payload:   (d['payload'] as Map<String, dynamic>?) ??
          (d['data'] as Map<String, dynamic>?) ?? {},
    );
  }

  Map<String, dynamic> toMap() => {
    'type':      type.name,
    'title':     title,
    'body':      body,
    'createdAt': Timestamp.fromDate(createdAt),
    'isRead':    isRead,
    'payload':   payload,
  };

  NotificationModel copyWith({bool? isRead}) => NotificationModel(
    id: id, type: type, title: title, body: body,
    createdAt: createdAt,
    isRead: isRead ?? this.isRead,
    payload: payload,
  );
}
