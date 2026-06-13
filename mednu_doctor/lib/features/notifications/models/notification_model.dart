import 'package:cloud_firestore/cloud_firestore.dart';

enum NotifType {
  consultationRequest,
  emergencyRequest,
  review,
  payment,
  appointment,
  summary,
  patientFollowup,
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
      case 'appointment':          return NotifType.appointment;
      case 'summary':              return NotifType.summary;
      case 'patient_followup':     return NotifType.patientFollowup;
      default:                     return NotifType.unknown;
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
      payload:   (d['payload'] as Map<String, dynamic>?) ?? {},
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
