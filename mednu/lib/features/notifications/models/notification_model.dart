import 'package:cloud_firestore/cloud_firestore.dart';

/// All notification types across every MedNu service module.
/// The raw string values must match what the Cloud Functions write to Firestore.
enum PatientNotifType {
  // ── Consultation & Quick Connect ──────────────────────────────────────────
  consultationDone,
  consultationUpdate,
  followupDay1,
  followupDay2,
  doctorStartedCall,
  quickConnectAccepted,
  quickConnectStarted,
  quickConnectCompleted,
  quickConnectRejected,
  quickConnectCancelled,

  // ── Appointments ──────────────────────────────────────────────────────────
  appointmentReminder,
  appointmentBooked,
  appointmentAccepted,
  appointmentRejected,
  appointmentRescheduled,
  appointmentCompleted,
  appointmentCancelled,
  prescriptionUploaded,
  reviewPrompt,

  // ── Medicine Orders ───────────────────────────────────────────────────────
  medicineReminder,
  medicineAccepted,
  medicineProcessing,
  medicineVerified,
  medicinePacked,
  medicineOutForDelivery,
  medicineDelivered,
  medicineRejected,
  medicineCancelled,
  medicineReturned,

  // ── Lab / Diagnostics ─────────────────────────────────────────────────────
  labAccepted,
  labAssigned,
  labInProgress,
  labSampleCollected,
  labProcessing,
  labReportReady,
  labCompleted,
  labRejected,
  labCancelled,

  // ── Ambulance ─────────────────────────────────────────────────────────────
  ambulanceAccepted,
  ambulanceAssigned,
  ambulanceEnRoute,
  ambulanceReached,
  ambulanceCompleted,
  ambulanceRejected,
  ambulanceCancelled,

  // ── Home Care / Caregiver ─────────────────────────────────────────────────
  homecareAccepted,
  caregiverAssigned,
  caregiverStarted,
  homecareCompleted,
  homecareRejected,
  homecareCancelled,

  // ── Physiotherapy ─────────────────────────────────────────────────────────
  physioAccepted,
  physioAssigned,
  physioStarted,
  physioCompleted,
  physioRejected,
  physioCancelled,

  // ── Hospital ──────────────────────────────────────────────────────────────
  hospitalAccepted,
  hospitalAssigned,
  hospitalAdmitted,
  hospitalDischarged,
  hospitalRejected,
  hospitalCancelled,

  // ── Pregnancy ─────────────────────────────────────────────────────────────
  pregnancyCheckupBooked,
  pregnancyCheckupReminder,
  pregnancyCheckupConfirmed,
  pregnancyCheckupCompleted,
  pregnancyCheckupCancelled,

  // ── Nutrition ─────────────────────────────────────────────────────────────
  nutritionAccepted,
  nutritionStarted,
  nutritionCompleted,
  nutritionRejected,
  nutritionCancelled,

  // ── Counselling ───────────────────────────────────────────────────────────
  counsellingAccepted,
  counsellingStarted,
  counsellingCompleted,
  counsellingCancelled,

  // ── Generic bookings (fallback) ───────────────────────────────────────────
  bookingAccepted,
  bookingAssigned,
  bookingStarted,
  bookingCompleted,
  bookingRejected,
  bookingCancelled,

  // ── Health & Wellness ─────────────────────────────────────────────────────
  waterReminder,
  periodTracker,
  healthTip,

  // ── Rewards / Misc ────────────────────────────────────────────────────────
  referralReward,
  welcomeBonus,
  orderUpdate, // legacy

  unknown,
}

class NotificationModel {
  final String id;
  final PatientNotifType type;
  final String title;
  final String body;
  final String serviceType;
  final String bookingId;
  final String doctorId;
  final String actionType;
  final DateTime createdAt;
  final DateTime deliverAt;
  final bool isRead;
  final Map<String, dynamic> data;

  const NotificationModel({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    this.serviceType = '',
    this.bookingId = '',
    this.doctorId = '',
    this.actionType = 'open_notifications',
    required this.createdAt,
    required this.deliverAt,
    required this.isRead,
    this.data = const {},
  });

  static PatientNotifType _typeFrom(String raw) {
    const map = <String, PatientNotifType>{
      // Consultation
      'consultation_done':         PatientNotifType.consultationDone,
      'consultation_update':       PatientNotifType.consultationUpdate,
      'followup_day1':             PatientNotifType.followupDay1,
      'followup_day2':             PatientNotifType.followupDay2,
      'doctor_started_call':       PatientNotifType.doctorStartedCall,
      'quickconnect_accepted':     PatientNotifType.quickConnectAccepted,
      'quickconnect_started':      PatientNotifType.quickConnectStarted,
      'quickconnect_completed':    PatientNotifType.quickConnectCompleted,
      'quickconnect_rejected':     PatientNotifType.quickConnectRejected,
      'quickconnect_cancelled':    PatientNotifType.quickConnectCancelled,

      // Appointments
      'appointment_reminder':      PatientNotifType.appointmentReminder,
      'appointment_booked':        PatientNotifType.appointmentBooked,
      'appointment_accepted':      PatientNotifType.appointmentAccepted,
      'appointment_rejected':      PatientNotifType.appointmentRejected,
      'appointment_rescheduled':   PatientNotifType.appointmentRescheduled,
      'appointment_completed':     PatientNotifType.appointmentCompleted,
      'appointment_cancelled':     PatientNotifType.appointmentCancelled,
      'prescription_uploaded':     PatientNotifType.prescriptionUploaded,
      'review_prompt':             PatientNotifType.reviewPrompt,

      // Medicine
      'medicine_reminder':         PatientNotifType.medicineReminder,
      'medicine_accepted':         PatientNotifType.medicineAccepted,
      'medicine_processing':       PatientNotifType.medicineProcessing,
      'medicine_verified':         PatientNotifType.medicineVerified,
      'medicine_packed':           PatientNotifType.medicinePacked,
      'medicine_out_for_delivery': PatientNotifType.medicineOutForDelivery,
      'medicine_delivered':        PatientNotifType.medicineDelivered,
      'medicine_rejected':         PatientNotifType.medicineRejected,
      'medicine_cancelled':        PatientNotifType.medicineCancelled,
      'medicine_returned':         PatientNotifType.medicineReturned,
      'order_update':              PatientNotifType.orderUpdate,

      // Lab
      'lab_accepted':              PatientNotifType.labAccepted,
      'lab_assigned':              PatientNotifType.labAssigned,
      'lab_in_progress':           PatientNotifType.labInProgress,
      'lab_sample_collected':      PatientNotifType.labSampleCollected,
      'lab_processing':            PatientNotifType.labProcessing,
      'lab_report_ready':          PatientNotifType.labReportReady,
      'lab_completed':             PatientNotifType.labCompleted,
      'lab_rejected':              PatientNotifType.labRejected,
      'lab_cancelled':             PatientNotifType.labCancelled,

      // Ambulance
      'ambulance_accepted':        PatientNotifType.ambulanceAccepted,
      'ambulance_assigned':        PatientNotifType.ambulanceAssigned,
      'ambulance_en_route':        PatientNotifType.ambulanceEnRoute,
      'ambulance_reached':         PatientNotifType.ambulanceReached,
      'ambulance_completed':       PatientNotifType.ambulanceCompleted,
      'ambulance_rejected':        PatientNotifType.ambulanceRejected,
      'ambulance_cancelled':       PatientNotifType.ambulanceCancelled,

      // Home Care
      'homecare_accepted':         PatientNotifType.homecareAccepted,
      'caregiver_accepted':        PatientNotifType.homecareAccepted,
      'caregiver_assigned':        PatientNotifType.caregiverAssigned,
      'caregiver_started':         PatientNotifType.caregiverStarted,
      'homecare_completed':        PatientNotifType.homecareCompleted,
      'caregiver_completed':       PatientNotifType.homecareCompleted,
      'homecare_rejected':         PatientNotifType.homecareRejected,
      'caregiver_rejected':        PatientNotifType.homecareRejected,
      'homecare_cancelled':        PatientNotifType.homecareCancelled,
      'caregiver_cancelled':       PatientNotifType.homecareCancelled,

      // Physiotherapy
      'physio_accepted':           PatientNotifType.physioAccepted,
      'physio_assigned':           PatientNotifType.physioAssigned,
      'physio_started':            PatientNotifType.physioStarted,
      'physio_completed':          PatientNotifType.physioCompleted,
      'physio_rejected':           PatientNotifType.physioRejected,
      'physio_cancelled':          PatientNotifType.physioCancelled,

      // Hospital
      'hospital_accepted':         PatientNotifType.hospitalAccepted,
      'hospital_assigned':         PatientNotifType.hospitalAssigned,
      'hospital_admitted':         PatientNotifType.hospitalAdmitted,
      'hospital_discharged':       PatientNotifType.hospitalDischarged,
      'hospital_rejected':         PatientNotifType.hospitalRejected,
      'hospital_cancelled':        PatientNotifType.hospitalCancelled,

      // Pregnancy
      'pregnancy_checkup_booked':     PatientNotifType.pregnancyCheckupBooked,
      'pregnancy_checkup_reminder':   PatientNotifType.pregnancyCheckupReminder,
      'pregnancy_checkup_confirmed':  PatientNotifType.pregnancyCheckupConfirmed,
      'pregnancy_checkup_completed':  PatientNotifType.pregnancyCheckupCompleted,
      'pregnancy_checkup_cancelled':  PatientNotifType.pregnancyCheckupCancelled,

      // Nutrition
      'nutrition_accepted':        PatientNotifType.nutritionAccepted,
      'nutrition_started':         PatientNotifType.nutritionStarted,
      'nutrition_completed':       PatientNotifType.nutritionCompleted,
      'nutrition_rejected':        PatientNotifType.nutritionRejected,
      'nutrition_cancelled':       PatientNotifType.nutritionCancelled,

      // Counselling
      'counselling_accepted':      PatientNotifType.counsellingAccepted,
      'counselling_started':       PatientNotifType.counsellingStarted,
      'counselling_completed':     PatientNotifType.counsellingCompleted,
      'counselling_cancelled':     PatientNotifType.counsellingCancelled,

      // Generic
      'booking_accepted':          PatientNotifType.bookingAccepted,
      'booking_assigned':          PatientNotifType.bookingAssigned,
      'booking_started':           PatientNotifType.bookingStarted,
      'booking_completed':         PatientNotifType.bookingCompleted,
      'booking_rejected':          PatientNotifType.bookingRejected,
      'booking_cancelled':         PatientNotifType.bookingCancelled,

      // Health
      'water_reminder':            PatientNotifType.waterReminder,
      'period_tracker':            PatientNotifType.periodTracker,
      'health_tip':                PatientNotifType.healthTip,

      // Rewards
      'referral_reward':           PatientNotifType.referralReward,
      'welcome_bonus':             PatientNotifType.welcomeBonus,
    };
    return map[raw] ?? PatientNotifType.unknown;
  }

  factory NotificationModel.fromDoc(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    final now = DateTime.now();

    // Merge legacy top-level fields into the data map for backward compat.
    final extraData = <String, dynamic>{
      ...((d['data'] as Map<String, dynamic>?) ?? {}),
      if (d['doctorName']      != null) 'doctorName':      d['doctorName'],
      if (d['consultationId']  != null) 'consultationId':  d['consultationId'],
      if (d['ctaRoute']        != null) 'ctaRoute':        d['ctaRoute'],
    };

    return NotificationModel(
      id:          doc.id,
      type:        _typeFrom(d['type'] as String? ?? ''),
      title:       d['title']       as String? ?? '',
      body:        d['body']        as String? ?? '',
      serviceType: d['serviceType'] as String? ?? '',
      bookingId:   d['bookingId']   as String? ?? '',
      doctorId:    d['doctorId']    as String? ?? '',
      actionType:  d['actionType']  as String? ?? 'open_notifications',
      createdAt:   (d['createdAt']  as Timestamp?)?.toDate() ?? now,
      deliverAt:   (d['deliverAt']  as Timestamp?)?.toDate() ?? now,
      isRead:      d['isRead']      as bool? ?? false,
      data:        extraData,
    );
  }

  NotificationModel copyWith({bool? isRead}) => NotificationModel(
        id: id, type: type, title: title, body: body,
        serviceType: serviceType, bookingId: bookingId,
        doctorId: doctorId, actionType: actionType,
        createdAt: createdAt, deliverAt: deliverAt,
        isRead: isRead ?? this.isRead, data: data,
      );
}
