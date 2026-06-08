import 'package:cloud_firestore/cloud_firestore.dart';

enum PatientNotifType {
  consultationDone,
  followupDay1,
  followupDay2,
  appointmentReminder,
  medicineReminder,
  waterReminder,
  periodTracker,
  orderUpdate,
  healthTip,
  referralReward,
  welcomeBonus,
  unknown,
}

class NotificationModel {
  final String id;
  final PatientNotifType type;
  final String title;
  final String body;
  final DateTime createdAt;
  final DateTime deliverAt;
  final bool isRead;
  final Map<String, dynamic> data;

  const NotificationModel({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.createdAt,
    required this.deliverAt,
    required this.isRead,
    this.data = const {},
  });

  static PatientNotifType _typeFrom(String raw) {
    switch (raw) {
      case 'consultation_done':     return PatientNotifType.consultationDone;
      case 'followup_day1':         return PatientNotifType.followupDay1;
      case 'followup_day2':         return PatientNotifType.followupDay2;
      case 'appointment_reminder':  return PatientNotifType.appointmentReminder;
      case 'medicine_reminder':     return PatientNotifType.medicineReminder;
      case 'water_reminder':        return PatientNotifType.waterReminder;
      case 'period_tracker':        return PatientNotifType.periodTracker;
      case 'order_update':          return PatientNotifType.orderUpdate;
      case 'health_tip':            return PatientNotifType.healthTip;
      case 'referral_reward':       return PatientNotifType.referralReward;
      case 'welcome_bonus':         return PatientNotifType.welcomeBonus;
      default:                      return PatientNotifType.unknown;
    }
  }

  factory NotificationModel.fromDoc(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    final now = DateTime.now();
    return NotificationModel(
      id:        doc.id,
      type:      _typeFrom(d['type'] as String? ?? ''),
      title:     d['title'] as String? ?? '',
      body:      d['body'] as String? ?? '',
      createdAt: (d['createdAt'] as Timestamp?)?.toDate() ?? now,
      deliverAt: (d['deliverAt'] as Timestamp?)?.toDate() ?? now,
      isRead:    d['isRead'] as bool? ?? false,
      data:      (d['data'] as Map<String, dynamic>?) ??
                 {
                   if (d['doctorName'] != null) 'doctorName': d['doctorName'],
                   if (d['consultationId'] != null) 'consultationId': d['consultationId'],
                   if (d['ctaRoute'] != null) 'ctaRoute': d['ctaRoute'],
                 },
    );
  }

  NotificationModel copyWith({bool? isRead}) => NotificationModel(
        id: id, type: type, title: title, body: body,
        createdAt: createdAt, deliverAt: deliverAt,
        isRead: isRead ?? this.isRead, data: data,
      );
}
