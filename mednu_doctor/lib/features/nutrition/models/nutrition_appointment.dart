import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// Mirrors the status vocabulary `mednu/lib/features/services/nutrition/
/// services/nutrition_service.dart` and its patient-facing screens already
/// use for `nutrition_appointments.status` — this module reads/writes the
/// same collection directly, there is no separate provider-side mirror.
enum NutritionAppointmentStatus { pending, confirmed, inProgress, completed, cancelled }

extension NutritionAppointmentStatusX on NutritionAppointmentStatus {
  String get label {
    switch (this) {
      case NutritionAppointmentStatus.pending:
        return 'Pending';
      case NutritionAppointmentStatus.confirmed:
        return 'Confirmed';
      case NutritionAppointmentStatus.inProgress:
        return 'In Progress';
      case NutritionAppointmentStatus.completed:
        return 'Completed';
      case NutritionAppointmentStatus.cancelled:
        return 'Cancelled';
    }
  }

  Color get color {
    switch (this) {
      case NutritionAppointmentStatus.pending:
        return const Color(0xFF1565C0);
      case NutritionAppointmentStatus.confirmed:
        return const Color(0xFF2E7D32);
      case NutritionAppointmentStatus.inProgress:
        return const Color(0xFFEF6C00);
      case NutritionAppointmentStatus.completed:
        return const Color(0xFF2E7D32);
      case NutritionAppointmentStatus.cancelled:
        return const Color(0xFFC62828);
    }
  }
}

/// Backed by `nutrition_appointments/{id}` — written directly by the patient
/// app, with `nutritionistId` already set at booking time (the patient picks
/// a specific nutritionist up front, same pre-assignment model as a doctor
/// appointment). No Cloud Function mirror exists for this collection; see
/// functions/index.js's "Nutrition partner access" note.
class NutritionAppointment {
  final String id;
  final NutritionAppointmentStatus status;
  final String userName;
  final String userPhone;
  final String consultationType;
  final String date;
  final String timeSlot;
  final String notes;
  final String? providerNotes;
  final String healthGoal;
  final num fee;
  final DateTime createdAt;

  const NutritionAppointment({
    required this.id,
    required this.status,
    required this.userName,
    required this.userPhone,
    required this.consultationType,
    required this.date,
    required this.timeSlot,
    required this.notes,
    required this.providerNotes,
    required this.healthGoal,
    required this.fee,
    required this.createdAt,
  });

  factory NutritionAppointment.fromFirestore(DocumentSnapshot<Object?> doc) {
    final d = (doc.data() as Map<String, dynamic>?) ?? const {};
    return NutritionAppointment(
      id: doc.id,
      status: _statusFrom(d['status'] as String?),
      userName: d['userName'] as String? ?? 'Patient',
      userPhone: d['userPhone'] as String? ?? '',
      consultationType: d['consultationType'] as String? ?? 'Consultation',
      date: d['date'] as String? ?? '',
      timeSlot: d['timeSlot'] as String? ?? '',
      notes: d['notes'] as String? ?? '',
      providerNotes: d['providerNotes'] as String?,
      healthGoal: d['healthGoal'] as String? ?? '',
      fee: (d['fee'] as num?) ?? 0,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  static NutritionAppointmentStatus _statusFrom(String? raw) {
    switch ((raw ?? '').toLowerCase()) {
      case 'confirmed':
      case 'accepted':
        return NutritionAppointmentStatus.confirmed;
      case 'in_progress':
      case 'started':
        return NutritionAppointmentStatus.inProgress;
      case 'completed':
        return NutritionAppointmentStatus.completed;
      case 'cancelled':
      case 'canceled':
        return NutritionAppointmentStatus.cancelled;
      default:
        return NutritionAppointmentStatus.pending;
    }
  }
}
