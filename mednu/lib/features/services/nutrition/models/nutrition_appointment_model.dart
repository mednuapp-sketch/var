import 'package:cloud_firestore/cloud_firestore.dart';

class NutritionAppointmentModel {
  final String id;
  final String userId;
  final String userName;
  final String userPhone;
  final String nutritionistId;
  final String nutritionistName;
  final String nutritionistSpecialization;
  final String consultationType; // 'online' | 'in_person'
  final String date;
  final String timeSlot;
  final String status; // pending | confirmed | completed | cancelled
  final String notes;
  final double fee;
  final String healthGoal;
  final DateTime createdAt;

  const NutritionAppointmentModel({
    required this.id,
    required this.userId,
    required this.userName,
    required this.userPhone,
    required this.nutritionistId,
    required this.nutritionistName,
    required this.nutritionistSpecialization,
    required this.consultationType,
    required this.date,
    required this.timeSlot,
    required this.status,
    required this.notes,
    required this.fee,
    required this.healthGoal,
    required this.createdAt,
  });

  factory NutritionAppointmentModel.fromFirestore(DocumentSnapshot doc) {
    final d = (doc.data() as Map<String, dynamic>?) ?? {};
    return NutritionAppointmentModel(
      id: doc.id,
      userId: d['userId'] as String? ?? '',
      userName: d['userName'] as String? ?? '',
      userPhone: d['userPhone'] as String? ?? '',
      nutritionistId: d['nutritionistId'] as String? ?? '',
      nutritionistName: d['nutritionistName'] as String? ?? '',
      nutritionistSpecialization: d['nutritionistSpecialization'] as String? ?? '',
      consultationType: d['consultationType'] as String? ?? 'online',
      date: d['date'] as String? ?? '',
      timeSlot: d['timeSlot'] as String? ?? '',
      status: d['status'] as String? ?? 'pending',
      notes: d['notes'] as String? ?? '',
      fee: (d['fee'] as num?)?.toDouble() ?? 0.0,
      healthGoal: d['healthGoal'] as String? ?? '',
      createdAt: (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  String get statusLabel {
    switch (status) {
      case 'confirmed': return 'Confirmed';
      case 'completed': return 'Completed';
      case 'cancelled': return 'Cancelled';
      default: return 'Pending';
    }
  }
}
