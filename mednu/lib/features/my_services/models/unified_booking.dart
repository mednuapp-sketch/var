import 'package:cloud_firestore/cloud_firestore.dart';

enum BookingSource {
  appointment,
  consultation,
  serviceRequest,
  nutrition,
  medicineOrder,
}

enum BookingStatus {
  pending,
  requested,
  confirmed,
  assigned,
  onTheWay,
  inProgress,
  consultationStarted,
  sampleCollected,
  delivered,
  completed,
  cancelled,
  rescheduled,
  verified,
  packed,
  outForDelivery,
}

extension BookingStatusX on BookingStatus {
  String get label {
    switch (this) {
      case BookingStatus.pending:             return 'Pending';
      case BookingStatus.requested:           return 'Requested';
      case BookingStatus.confirmed:           return 'Confirmed';
      case BookingStatus.assigned:            return 'Assigned';
      case BookingStatus.onTheWay:            return 'On the Way';
      case BookingStatus.inProgress:          return 'In Progress';
      case BookingStatus.consultationStarted: return 'Started';
      case BookingStatus.sampleCollected:     return 'Sample Collected';
      case BookingStatus.delivered:           return 'Delivered';
      case BookingStatus.completed:           return 'Completed';
      case BookingStatus.cancelled:           return 'Cancelled';
      case BookingStatus.rescheduled:         return 'Rescheduled';
      case BookingStatus.verified:            return 'Verified';
      case BookingStatus.packed:              return 'Packed';
      case BookingStatus.outForDelivery:      return 'Out for Delivery';
    }
  }
}

class BookingStatusEvent {
  final String title;
  final String description;
  final bool isCompleted;
  final bool isActive;
  final DateTime? timestamp;

  const BookingStatusEvent({
    required this.title,
    required this.description,
    required this.isCompleted,
    required this.isActive,
    this.timestamp,
  });
}

class UnifiedBooking {
  final String id;
  final BookingSource source;
  final String serviceType;
  final String serviceName;
  final String? providerName;
  final String? providerPhone;
  final String? providerPhoto;
  final String? providerSpecialty;
  final String date;
  final String time;
  final BookingStatus status;
  final String? address;
  final String? notes;
  final double? amount;
  final Map<String, dynamic> rawData;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const UnifiedBooking({
    required this.id,
    required this.source,
    required this.serviceType,
    required this.serviceName,
    this.providerName,
    this.providerPhone,
    this.providerPhoto,
    this.providerSpecialty,
    required this.date,
    required this.time,
    required this.status,
    this.address,
    this.notes,
    this.amount,
    required this.rawData,
    this.createdAt,
    this.updatedAt,
  });

  // ── Parsers ────────────────────────────────────────────────────────────────

  static BookingStatus _parseStatus(String? s) {
    switch ((s ?? '').toLowerCase().replaceAll(' ', '_')) {
      case 'confirmed':
      case 'accepted':
      case 'booked':              return BookingStatus.confirmed;
      case 'assigned':            return BookingStatus.assigned;
      case 'on_the_way':          return BookingStatus.onTheWay;
      case 'in_progress':
      case 'started':             return BookingStatus.inProgress;
      case 'consultation_started':return BookingStatus.consultationStarted;
      case 'sample_collected':    return BookingStatus.sampleCollected;
      case 'verified':            return BookingStatus.verified;
      case 'packed':              return BookingStatus.packed;
      case 'out_for_delivery':    return BookingStatus.outForDelivery;
      case 'delivered':           return BookingStatus.delivered;
      case 'completed':           return BookingStatus.completed;
      case 'cancelled':
      case 'canceled':
      case 'rejected':            return BookingStatus.cancelled;
      case 'rescheduled':         return BookingStatus.rescheduled;
      case 'requested':           return BookingStatus.requested;
      default:                    return BookingStatus.pending;
    }
  }

  static DateTime? _tsToDate(dynamic ts) {
    if (ts is Timestamp) return ts.toDate();
    if (ts is String && ts.isNotEmpty) {
      try { return DateTime.parse(ts); } catch (_) {}
    }
    return null;
  }

  // ── Factories ──────────────────────────────────────────────────────────────

  factory UnifiedBooking.fromAppointment(Map<String, dynamic> d, String id) {
    return UnifiedBooking(
      id: id,
      source: BookingSource.appointment,
      serviceType: 'Doctor Appointment',
      serviceName: d['doctorName'] as String? ??
          d['specialty'] as String? ??
          'Doctor Appointment',
      providerName: d['doctorName'] as String?,
      providerSpecialty: d['specialty'] as String?,
      providerPhone: d['doctorPhone'] as String?,
      date: d['date'] as String? ?? '',
      time: d['time'] as String? ?? d['timeSlot'] as String? ?? '',
      status: _parseStatus(d['status'] as String?),
      address: d['address'] as String?,
      notes: d['notes'] as String?,
      amount: (d['fee'] as num?)?.toDouble() ?? (d['amount'] as num?)?.toDouble(),
      rawData: d,
      createdAt: _tsToDate(d['createdAt']),
      updatedAt: _tsToDate(d['updatedAt']),
    );
  }

  factory UnifiedBooking.fromConsultation(Map<String, dynamic> d, String id) {
    return UnifiedBooking(
      id: id,
      source: BookingSource.consultation,
      serviceType: 'Video Consultation',
      serviceName: d['doctorName'] as String? ?? 'Video Consultation',
      providerName: d['doctorName'] as String?,
      providerSpecialty:
          d['doctorSpecialty'] as String? ?? d['specialty'] as String?,
      date: d['scheduledDate'] as String? ?? d['date'] as String? ?? '',
      time: d['scheduledTime'] as String? ?? d['time'] as String? ?? '',
      status: _parseStatus(d['status'] as String?),
      notes: d['notes'] as String?,
      amount: (d['fee'] as num?)?.toDouble(),
      rawData: d,
      createdAt: _tsToDate(d['createdAt']),
      updatedAt: _tsToDate(d['updatedAt']),
    );
  }

  factory UnifiedBooking.fromServiceRequest(Map<String, dynamic> d, String id) {
    final type = d['type'] as String? ?? '';
    final serviceDetails = d['serviceDetails'] as Map<String, dynamic>?;
    final isEquipmentPurchase = type.toLowerCase() == 'equipment' && serviceDetails?['mode'] == 'buy';
    final serviceType = isEquipmentPurchase ? 'Equipment Purchase' : _serviceTypeLabel(type);
    return UnifiedBooking(
      id: id,
      source: BookingSource.serviceRequest,
      serviceType: serviceType,
      serviceName: d['serviceName'] as String? ?? serviceType,
      providerName: d['assignedTo'] as String?,
      providerPhone: d['providerPhone'] as String?,
      date: d['preferredDate'] as String? ?? '',
      time: d['preferredTime'] as String? ?? '',
      status: _parseStatus(d['status'] as String?),
      address: d['address'] as String?,
      notes: d['notes'] as String?,
      amount: (d['amount'] as num?)?.toDouble(),
      rawData: d,
      createdAt: _tsToDate(d['createdAt']),
      updatedAt: _tsToDate(d['updatedAt']),
    );
  }

  factory UnifiedBooking.fromNutrition(Map<String, dynamic> d, String id) {
    return UnifiedBooking(
      id: id,
      source: BookingSource.nutrition,
      serviceType: 'Nutrition Consultation',
      serviceName: d['nutritionistName'] as String? ?? 'Nutritionist',
      providerName: d['nutritionistName'] as String?,
      providerSpecialty: 'Nutritionist',
      date: d['date'] as String? ?? '',
      time: d['timeSlot'] as String? ?? '',
      status: _parseStatus(d['status'] as String?),
      notes: d['notes'] as String?,
      amount: (d['fee'] as num?)?.toDouble(),
      rawData: d,
      createdAt: _tsToDate(d['createdAt']),
      updatedAt: _tsToDate(d['updatedAt']),
    );
  }

  /// From the `orders` collection (mednu/lib/features/cart/screens/
  /// cart_screen.dart's medicine checkout) — the one booking source that
  /// isn't itself a request/appointment, so `date`/`time` are derived from
  /// `createdAt` rather than a patient-picked slot, and `providerName` is
  /// left null (the pharmacy isn't identified to the patient by name today).
  factory UnifiedBooking.fromOrder(Map<String, dynamic> d, String id) {
    final items = (d['items'] as List?) ?? const [];
    String? firstItemName;
    if (items.isNotEmpty && items.first is Map) {
      firstItemName = (items.first as Map)['name'] as String?;
    }
    final createdAt = _tsToDate(d['createdAt']);
    return UnifiedBooking(
      id: id,
      source: BookingSource.medicineOrder,
      serviceType: 'Pharmacy Delivery',
      serviceName: firstItemName ?? 'Medicine Order',
      date: createdAt != null
          ? '${createdAt.day}/${createdAt.month}/${createdAt.year}'
          : '',
      time: '',
      status: _parseStatus(d['status'] as String?),
      address: d['deliveryAddress'] as String?,
      amount: (d['total'] as num?)?.toDouble(),
      rawData: d,
      createdAt: createdAt,
      updatedAt: _tsToDate(d['updatedAt']),
    );
  }

  /// True only for a medicine order still waiting on a prescription
  /// decision — driven by the same boolean fields `OrderModel.
  /// needsPrescriptionDecision` already uses, not by a status string:
  /// `prescription_required` is a `pharmacy_orders`-only status that never
  /// lands on `orders.status` (see functions/index.js's pharmacy module).
  bool get needsPrescriptionDecision =>
      source == BookingSource.medicineOrder &&
      rawData['prescriptionUrl'] != null &&
      rawData['prescriptionVerified'] == null;

  /// True for a medicine order whose uploaded prescription was rejected.
  bool get prescriptionWasRejected =>
      source == BookingSource.medicineOrder &&
      rawData['prescriptionVerified'] == false;

  // ── Helpers ────────────────────────────────────────────────────────────────

  static String _serviceTypeLabel(String type) {
    switch (type.toLowerCase().replaceAll(' ', '_')) {
      case 'ambulance':          return 'Ambulance';
      case 'diagnostics':
      case 'diagnostic':         return 'Diagnostics';
      case 'caregiver':
      case 'caregivers':         return 'Caregiver';
      case 'care_assistant':     return 'Care Assistant';
      case 'physiotherapy':
      case 'physio':             return 'Physiotherapy';
      case 'counselling':
      case 'counseling':         return 'Counselling';
      case 'equipment':
      case 'equipment_hiring':   return 'Equipment Rental';
      case 'medicine':
      case 'medicine_delivery':  return 'Pharmacy Delivery';
      case 'lab_test':
      case 'lab_tests':
      case 'lab':                return 'Lab Test';
      case 'home_sample':        return 'Home Sample Collection';
      case 'pregnancy':          return 'Pregnancy Checkup';
      default:
        if (type.isEmpty) return 'Service';
        return type[0].toUpperCase() + type.substring(1);
    }
  }

  bool get isActive => const {
        BookingStatus.pending,
        BookingStatus.requested,
        BookingStatus.confirmed,
        BookingStatus.assigned,
        BookingStatus.onTheWay,
        BookingStatus.inProgress,
        BookingStatus.consultationStarted,
        BookingStatus.rescheduled,
      }.contains(status);

  bool get isCompleted =>
      status == BookingStatus.completed ||
      status == BookingStatus.delivered ||
      status == BookingStatus.sampleCollected;

  bool get isCancelled => status == BookingStatus.cancelled;

  // ── Timeline ───────────────────────────────────────────────────────────────

  List<BookingStatusEvent> get timeline => _buildTimeline();

  List<BookingStatusEvent> _buildTimeline() {
    final steps = _timelineSteps();
    final currentIdx = _currentStepIndex(steps.length);
    return steps.asMap().entries.map((e) {
      return BookingStatusEvent(
        title: e.value['title']!,
        description: e.value['desc']!,
        isCompleted: e.key < currentIdx,
        isActive: e.key == currentIdx && !isCancelled,
        timestamp: e.key == 0 ? createdAt : null,
      );
    }).toList();
  }

  int _currentStepIndex(int stepCount) {
    switch (status) {
      case BookingStatus.pending:
      case BookingStatus.requested:           return 0;
      case BookingStatus.confirmed:
      case BookingStatus.rescheduled:
      case BookingStatus.verified:
      case BookingStatus.packed:              return 1;
      case BookingStatus.assigned:
      case BookingStatus.outForDelivery:      return 2;
      case BookingStatus.onTheWay:
      case BookingStatus.inProgress:
      case BookingStatus.consultationStarted: return 3;
      case BookingStatus.sampleCollected:
      case BookingStatus.delivered:
      case BookingStatus.completed:           return stepCount - 1;
      case BookingStatus.cancelled:           return 0;
    }
  }

  List<Map<String, String>> _timelineSteps() {
    switch (source) {
      case BookingSource.appointment:
        return [
          {'title': 'Appointment Requested', 'desc': 'Your appointment request was submitted'},
          {'title': 'Appointment Confirmed', 'desc': 'Your slot has been confirmed by the clinic'},
          {'title': 'Doctor Ready', 'desc': 'Your doctor is ready for your visit'},
          {'title': 'Consultation Completed', 'desc': 'Your appointment is done'},
        ];
      case BookingSource.consultation:
        return [
          {'title': 'Consultation Requested', 'desc': 'Your request was submitted successfully'},
          {'title': 'Doctor Available', 'desc': 'Doctor is ready to connect with you'},
          {'title': 'Call In Progress', 'desc': 'Video consultation is active'},
          {'title': 'Consultation Completed', 'desc': 'Session completed successfully'},
        ];
      case BookingSource.nutrition:
        return [
          {'title': 'Session Requested', 'desc': 'Your nutrition booking was submitted'},
          {'title': 'Nutritionist Confirmed', 'desc': 'Your session has been confirmed'},
          {'title': 'Session In Progress', 'desc': 'Consultation is currently active'},
          {'title': 'Session Completed', 'desc': 'Your nutrition session is complete'},
        ];
      case BookingSource.serviceRequest:
        final type = (rawData['type'] as String? ?? '').toLowerCase();
        if (type == 'ambulance') {
          return [
            {'title': 'Request Placed', 'desc': 'Ambulance request submitted'},
            {'title': 'Ambulance Assigned', 'desc': 'Ambulance team has been notified'},
            {'title': 'On the Way', 'desc': 'Ambulance is heading to your location'},
            {'title': 'Arrived', 'desc': 'Ambulance has reached your location'},
          ];
        }
        if (type == 'diagnostics' || type == 'lab_test') {
          return [
            {'title': 'Test Requested', 'desc': 'Diagnostic test booking submitted'},
            {'title': 'Slot Confirmed', 'desc': 'Your test slot is confirmed'},
            {'title': 'Sample Collected', 'desc': 'Sample collection completed'},
            {'title': 'Report Ready', 'desc': 'Your test report is available'},
          ];
        }
        if (type == 'medicine' || type == 'medicine_delivery') {
          return [
            {'title': 'Order Placed', 'desc': 'Medicine order submitted'},
            {'title': 'Order Confirmed', 'desc': 'Pharmacy has confirmed your order'},
            {'title': 'Out for Delivery', 'desc': 'Delivery partner is on the way'},
            {'title': 'Delivered', 'desc': 'Order delivered to your doorstep'},
          ];
        }
        return [
          {'title': 'Request Placed', 'desc': 'Your service request was submitted'},
          {'title': 'Request Confirmed', 'desc': 'Service provider confirmed your request'},
          {'title': 'Service Started', 'desc': 'Service is currently in progress'},
          {'title': 'Service Completed', 'desc': 'Your service has been completed'},
        ];
      case BookingSource.medicineOrder:
        // Same copy as the serviceRequest 'medicine'/'medicine_delivery'
        // branch above, for consistency — 'verified'/'packed' both read as
        // still-preparing (step 1) until 'out_for_delivery' advances it.
        return [
          {'title': 'Order Placed', 'desc': 'Medicine order submitted'},
          {'title': 'Order Confirmed', 'desc': 'Pharmacy has confirmed your order'},
          {'title': 'Out for Delivery', 'desc': 'Delivery partner is on the way'},
          {'title': 'Delivered', 'desc': 'Order delivered to your doorstep'},
        ];
    }
  }
}
