import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../router/app_router.dart';
import 'maps_launcher.dart';

/// Shared logic for the in-person "OP" (out-patient) slip and clinic
/// directions, used by both the dedicated My Appointments card
/// (appointment_screen.dart) and the unified My Services detail screen
/// (service_detail_screen.dart) so an in-person appointment behaves the
/// same wherever the patient finds it.
class OpSlipService {
  OpSlipService._();

  /// Opens the OP slip PDF viewer for an appointment. If the doctor has
  /// already written a prescription for it, shows that (real-time, since
  /// Firestore pushed `prescriptionId` onto the appointment doc the moment
  /// it was written). Otherwise, for in-person visits, builds a blank slip
  /// straight from the appointment + doctor profile so the patient has a
  /// downloadable proof-of-booking document before the visit even happens.
  static Future<void> openSlip(
    BuildContext context, {
    required String appointmentId,
    required Map<String, dynamic> appointmentData,
  }) async {
    try {
      await _openSlip(context, appointmentId, appointmentData);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open OP slip: $e')),
        );
      }
    }
  }

  static Future<void> _openSlip(
    BuildContext context,
    String appointmentId,
    Map<String, dynamic> appointmentData,
  ) async {
    final consultationId =
        (appointmentData['consultationId'] as String?)?.isNotEmpty == true
        ? appointmentData['consultationId'] as String
        : appointmentId;
    // The `prescriptions` security rule only allows reads where
    // resource.data.patientId == request.auth.uid. Firestore can only verify
    // that for a *query* (as opposed to a single-doc get) if the query
    // itself also filters on patientId — otherwise it can't prove the rule
    // holds for every possible match and rejects the whole query with
    // PERMISSION_DENIED, even when a matching, ownable document exists.
    final uid = FirebaseAuth.instance.currentUser?.uid;

    final snap = await FirebaseFirestore.instance
        .collection('prescriptions')
        .where('appointmentId', isEqualTo: appointmentId)
        .where('patientId', isEqualTo: uid)
        .limit(1)
        .get();

    Map<String, dynamic>? rxData;
    if (snap.docs.isNotEmpty) {
      rxData = snap.docs.first.data();
    } else {
      final snap2 = await FirebaseFirestore.instance
          .collection('prescriptions')
          .where('consultationId', isEqualTo: consultationId)
          .where('patientId', isEqualTo: uid)
          .limit(1)
          .get();
      if (snap2.docs.isNotEmpty) rxData = snap2.docs.first.data();
    }

    if (!context.mounted) return;

    if (rxData == null) {
      final type = appointmentData['consultationType'] as String? ?? 'Video';
      if (type != 'In-Person') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No prescription found for this appointment'),
          ),
        );
        return;
      }

      Map<String, dynamic>? doctorDoc;
      final doctorId = appointmentData['doctorId'] as String? ?? '';
      if (doctorId.isNotEmpty) {
        try {
          final d = await FirebaseFirestore.instance
              .collection('doctors')
              .doc(doctorId)
              .get();
          doctorDoc = d.data();
        } catch (_) {}
      }
      if (!context.mounted) return;

      final slot = parseSlot(
        appointmentData['date'] as String? ?? '',
        appointmentData['time'] as String? ?? '',
      );
      context.push(
        AppRoutes.prescriptionViewer,
        extra: {
          'doctorName': appointmentData['doctorName'],
          'doctorSpecialty': appointmentData['doctorSpecialty'],
          'doctorRegNo': doctorDoc?['registrationNumber'],
          'doctorHospital': doctorDoc?['clinicName'],
          'patientId': appointmentData['patientId'],
          'patientName': appointmentData['patientName'],
          'consultationType': type,
          'appointmentId': appointmentId,
          if (slot != null) 'createdAt': Timestamp.fromDate(slot),
        },
      );
      return;
    }

    context.push(
      AppRoutes.prescriptionViewer,
      extra: {
        ...rxData,
        'doctorName': appointmentData['doctorName'],
        'doctorSpecialty': appointmentData['doctorSpecialty'],
        'date': appointmentData['date'],
        'consultationType': appointmentData['consultationType'],
      },
    );
  }

  /// Fetches the doctor's clinic address and opens Google Maps navigation
  /// to it. Shows a snackbar instead of failing silently when the doctor
  /// hasn't set an address yet.
  static Future<void> openDirections(
    BuildContext context, {
    required Map<String, dynamic> appointmentData,
  }) async {
    try {
      await _openDirections(context, appointmentData);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open directions: $e')),
        );
      }
    }
  }

  static Future<void> _openDirections(
    BuildContext context,
    Map<String, dynamic> appointmentData,
  ) async {
    final doctorId = appointmentData['doctorId'] as String? ?? '';
    final doctorName = appointmentData['doctorName'] as String? ?? 'the doctor';
    String address = '';
    String clinicName = '';
    if (doctorId.isNotEmpty) {
      final doc = await FirebaseFirestore.instance
          .collection('doctors')
          .doc(doctorId)
          .get();
      address = doc.data()?['clinicAddress'] as String? ?? '';
      clinicName = doc.data()?['clinicName'] as String? ?? '';
    }
    if (!context.mounted) return;
    if (address.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Clinic address not available yet. Please contact Dr. $doctorName directly.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    await MapsLauncher.navigateToAddress(
      clinicName.isNotEmpty ? '$clinicName, $address' : address,
    );
  }

  /// Converts "yyyy-MM-dd" + "hh:mm AM/PM" appointment fields into a
  /// DateTime, tolerant of a few alternate date formats. Returns null if
  /// either field is missing or unparseable.
  static DateTime? parseSlot(String dateStr, String timeStr) {
    if (dateStr.isEmpty || timeStr.isEmpty) return null;
    try {
      DateTime? date;
      try {
        date = DateTime.parse(dateStr);
      } catch (_) {
        for (final fmt in [
          'EEE, d MMM yyyy',
          'EEE, dd MMM yyyy',
          'd MMM yyyy',
        ]) {
          try {
            date = DateFormat(fmt).parse(dateStr);
            break;
          } catch (_) {}
        }
      }
      if (date == null) return null;
      final parts = timeStr.trim().split(' ');
      final hm = parts[0].split(':');
      int h = int.parse(hm[0]);
      final m = int.parse(hm[1]);
      if (parts.length > 1 && parts[1].toUpperCase() == 'PM' && h != 12) {
        h += 12;
      }
      if (parts.length > 1 && parts[1].toUpperCase() == 'AM' && h == 12) {
        h = 0;
      }
      return DateTime(date.year, date.month, date.day, h, m);
    } catch (_) {
      return null;
    }
  }
}
