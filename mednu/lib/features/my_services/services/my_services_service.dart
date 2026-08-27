import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/unified_booking.dart';
import '../../../../core/services/operation_logger.dart';

class MyServicesService {
  static final _db   = FirebaseFirestore.instance;
  static final _auth = FirebaseAuth.instance;

  static String? get _uid => _auth.currentUser?.uid;

  // ── Public API ──────────────────────────────────────────────────────────────

  /// Merged realtime stream of ALL booking types for the current user.
  static Stream<List<UnifiedBooking>> allBookingsStream() {
    final uid = _uid;
    if (uid == null) return Stream.value([]);
    return _mergeStreams([
      _appointmentsStream(uid),
      _consultationsStream(uid),
      _serviceRequestsStream(uid),
      _nutritionStream(uid),
      _ordersStream(uid),
    ]);
  }

  /// Realtime stream for a single booking document.
  static Stream<UnifiedBooking?> bookingDetailStream(UnifiedBooking booking) {
    final col = _collectionFor(booking.source);
    return _db.collection(col).doc(booking.id).snapshots().map((snap) {
      if (!snap.exists) return null;
      final d = snap.data();
      if (d == null) return null;
      switch (booking.source) {
        case BookingSource.appointment:
          return UnifiedBooking.fromAppointment(d, snap.id);
        case BookingSource.consultation:
          return UnifiedBooking.fromConsultation(d, snap.id);
        case BookingSource.serviceRequest:
          return UnifiedBooking.fromServiceRequest(d, snap.id);
        case BookingSource.nutrition:
          return UnifiedBooking.fromNutrition(d, snap.id);
        case BookingSource.medicineOrder:
          return UnifiedBooking.fromOrder(d, snap.id);
      }
    });
  }

  /// Update booking status and log the operation.
  static Future<void> updateStatus(
    UnifiedBooking booking,
    String newStatus,
  ) async {
    final col = _collectionFor(booking.source);

    final isCancellation = newStatus == 'cancelled';
    final action = isCancellation
        ? OpAction.bookingCancelled
        : OpAction.bookingStatusChanged;

    await OperationLogger.logPending(
      action: action,
      entityId: booking.id,
      entityType: booking.source.name,
      message: isCancellation
          ? 'Cancelling ${booking.serviceType}...'
          : 'Updating status to $newStatus...',
    );

    try {
      await _db.collection(col).doc(booking.id).update({
        'status':    newStatus,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      await OperationLogger.logSuccess(
        action: action,
        entityId: booking.id,
        entityType: booking.source.name,
        message: isCancellation
            ? '${booking.serviceType} cancelled successfully'
            : '${booking.serviceType} status updated to $newStatus',
        metadata: {'newStatus': newStatus},
      );
    } catch (e) {
      await OperationLogger.logError(
        action: action,
        entityId: booking.id,
        entityType: booking.source.name,
        message: isCancellation
            ? 'Failed to cancel ${booking.serviceType}'
            : 'Failed to update status',
        errorDetails: e.toString(),
      );
      rethrow;
    }
  }

  // ── Individual streams ──────────────────────────────────────────────────────

  /// Cap per-collection history. Without this each of these streams pulls a
  /// patient's ENTIRE lifetime history and keeps it live for the whole app
  /// session (allBookingsStream is subscribed from the root widget), which
  /// grows without bound over years of use.
  static const int _historyLimit = 50;

  static Stream<List<UnifiedBooking>> _appointmentsStream(String uid) {
    return _db
        .collection('appointments')
        .where('patientId', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .limit(_historyLimit)
        .snapshots()
        .handleError((e) => debugPrint('MyServicesService: appointments stream error: $e'))
        .map((s) => s.docs
            .map((d) => UnifiedBooking.fromAppointment(d.data(), d.id))
            .toList());
  }

  static Stream<List<UnifiedBooking>> _consultationsStream(String uid) {
    return _db
        .collection('consultations')
        .where('patientId', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .limit(_historyLimit)
        .snapshots()
        .handleError((e) => debugPrint('MyServicesService: consultations stream error: $e'))
        .map((s) => s.docs
            .map((d) => UnifiedBooking.fromConsultation(d.data(), d.id))
            .toList());
  }

  static Stream<List<UnifiedBooking>> _serviceRequestsStream(String uid) {
    return _db
        .collection('service_requests')
        .where('patientId', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .limit(_historyLimit)
        .snapshots()
        .handleError((e) => debugPrint('MyServicesService: service_requests stream error: $e'))
        .map((s) => s.docs
            .map((d) => UnifiedBooking.fromServiceRequest(d.data(), d.id))
            .toList());
  }

  static Stream<List<UnifiedBooking>> _nutritionStream(String uid) {
    return _db
        .collection('nutrition_appointments')
        .where('userId', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .limit(_historyLimit)
        .snapshots()
        .handleError((e) => debugPrint('MyServicesService: nutrition stream error: $e'))
        .map((s) => s.docs
            .map((d) => UnifiedBooking.fromNutrition(d.data(), d.id))
            .toList());
  }

  /// Medicine orders from the cart-checkout `orders` collection (previously
  /// only surfaced via the separate `orders` feature's own screens — see
  /// mednu/lib/features/orders/ — never folded into this unified stream).
  static Stream<List<UnifiedBooking>> _ordersStream(String uid) {
    return _db
        .collection('orders')
        .where('patientId', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .limit(_historyLimit)
        .snapshots()
        .handleError((e) => debugPrint('MyServicesService: orders stream error: $e'))
        .map((s) => s.docs
            .map((d) => UnifiedBooking.fromOrder(d.data(), d.id))
            .toList());
  }

  // ── Stream merger ───────────────────────────────────────────────────────────

  static Stream<List<UnifiedBooking>> _mergeStreams(
      List<Stream<List<UnifiedBooking>>> streams) {
    final latest = List<List<UnifiedBooking>>.filled(
        streams.length, const [], growable: false);
    int pendingCount = streams.length;
    final subs = <StreamSubscription<List<UnifiedBooking>>>[];
    late StreamController<List<UnifiedBooking>> ctrl;

    ctrl = StreamController<List<UnifiedBooking>>.broadcast(
      onCancel: () {
        for (final s in subs) {
          s.cancel();
        }
        subs.clear();
        if (!ctrl.isClosed) ctrl.close();
      },
    );

    for (int i = 0; i < streams.length; i++) {
      final idx = i;
      subs.add(streams[idx].listen(
        (list) {
          if (pendingCount > 0 && latest[idx].isEmpty) pendingCount--;
          latest[idx] = list;
          _emit(ctrl, latest);
        },
        onError: (_) {
          if (pendingCount > 0) pendingCount--;
          _emit(ctrl, latest);
        },
        cancelOnError: false,
      ));
    }

    return ctrl.stream;
  }

  static void _emit(StreamController<List<UnifiedBooking>> ctrl,
      List<List<UnifiedBooking>> latest) {
    if (ctrl.isClosed) return;
    final merged = latest
        .expand((l) => l)
        .toList()
      ..sort((a, b) {
        final at = a.createdAt ?? DateTime(1970);
        final bt = b.createdAt ?? DateTime(1970);
        return bt.compareTo(at);
      });
    ctrl.add(merged);
  }

  // ── Utility ─────────────────────────────────────────────────────────────────

  static String _collectionFor(BookingSource source) {
    switch (source) {
      case BookingSource.appointment:    return 'appointments';
      case BookingSource.consultation:   return 'consultations';
      case BookingSource.serviceRequest: return 'service_requests';
      case BookingSource.nutrition:      return 'nutrition_appointments';
      case BookingSource.medicineOrder:  return 'orders';
    }
  }
}
