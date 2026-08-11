import 'package:cloud_firestore/cloud_firestore.dart';

/// Thrown when a status-changing action can't proceed because the request's
/// current state no longer matches what the caller expected — most commonly,
/// a second ambulance tried to accept a request another one claimed a moment
/// earlier. Screens catch this specifically to show "someone else already
/// took this" instead of a generic error.
class AmbulanceRequestConflictException implements Exception {
  final String message;
  const AmbulanceRequestConflictException(this.message);
  @override
  String toString() => message;
}

/// All Firestore access for the Ambulance module lives here — screens never
/// touch `FirebaseFirestore` directly. Every write only ever touches
/// `ambulance_requests`. Nothing here writes to `service_requests`,
/// `ambulance_trips` or `ambulance_transactions` — the Cloud Function mirror
/// (`functions/index.js`) is the sole writer of all three on this module's
/// behalf, which is what keeps the trip record and the earnings ledger
/// impossible to forge from a client.
class AmbulanceRequestService {
  AmbulanceRequestService._();

  static final _db = FirebaseFirestore.instance;

  /// Requests not yet claimed by any ambulance — the shared, realtime
  /// dispatch queue every ambulance partner sees.
  static Stream<QuerySnapshot<Map<String, dynamic>>> availableRequestsStream() {
    return _db
        .collection('ambulance_requests')
        .where('ambulanceId', isNull: true)
        .where('status', isEqualTo: 'pending')
        .orderBy('createdAt', descending: true)
        .limit(30)
        .snapshots();
  }

  /// Every request this partner has claimed. Deliberately unordered (sorted
  /// client-side instead) so it needs no extra composite index beyond the
  /// two already declared in `firestore.indexes.json` — the same trade-off
  /// `LabBookingService.myAllBookingsStream` makes.
  static Stream<QuerySnapshot<Map<String, dynamic>>> myRequestsStream(String ambulanceId) {
    return _db
        .collection('ambulance_requests')
        .where('ambulanceId', isEqualTo: ambulanceId)
        .snapshots();
  }

  static Stream<DocumentSnapshot<Map<String, dynamic>>> requestStream(String requestId) =>
      _db.collection('ambulance_requests').doc(requestId).snapshots();

  /// Completed trips, newest first. Backed by the immutable `ambulance_trips`
  /// records the Cloud Function writes on completion.
  static Stream<QuerySnapshot<Map<String, dynamic>>> myTripsStream(String ambulanceId) {
    return _db
        .collection('ambulance_trips')
        .where('ambulanceId', isEqualTo: ambulanceId)
        .orderBy('completedAt', descending: true)
        .limit(100)
        .snapshots();
  }

  // ── Status transitions ─────────────────────────────────────────────────
  //
  // Every transition below reads the request inside a Firestore transaction
  // and re-checks its *current* state before writing — this is what actually
  // prevents two ambulances from both successfully accepting the same
  // emergency (a plain `.update()` would let both writes "succeed"
  // independently; a transaction serializes them so the second one sees the
  // first one's result and can refuse). `firestore.rules`'
  // `_validAmbulanceTransition` enforces the same graph server-side as a
  // backstop against a client that skips this service entirely.

  static Future<void> _transitionRequest(
    String requestId, {
    required bool Function(Map<String, dynamic> data) precondition,
    required String conflictMessage,
    required Map<String, dynamic> Function(Map<String, dynamic> data) buildUpdate,
  }) {
    final ref = _db.collection('ambulance_requests').doc(requestId);
    return _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) {
        throw const AmbulanceRequestConflictException('This request no longer exists.');
      }
      final data = snap.data()!;
      if (!precondition(data)) {
        throw AmbulanceRequestConflictException(conflictMessage);
      }
      tx.update(ref, {
        ...buildUpdate(data),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  static Future<void> accept(String requestId, String ambulanceId) => _transitionRequest(
        requestId,
        precondition: (d) => d['ambulanceId'] == null && d['status'] == 'pending',
        conflictMessage: 'This request was already accepted by another ambulance.',
        buildUpdate: (d) => {'ambulanceId': ambulanceId, 'status': 'accepted'},
      );

  /// Declining a request nobody has claimed yet. Stamps `ambulanceId` so the
  /// owning-partner update rule keeps applying to the resulting doc, exactly
  /// like `LabBookingService.rejectBooking` does.
  static Future<void> reject(String requestId, String ambulanceId) => _transitionRequest(
        requestId,
        precondition: (d) =>
            (d['ambulanceId'] == null || d['ambulanceId'] == ambulanceId) &&
            d['status'] == 'pending',
        conflictMessage: 'This request is no longer available to decline.',
        buildUpdate: (d) => {'ambulanceId': ambulanceId, 'status': 'cancelled'},
      );

  static Future<void> startEnRoute(String requestId, {required String ambulanceId}) =>
      _transitionRequest(
        requestId,
        precondition: (d) => d['ambulanceId'] == ambulanceId && d['status'] == 'accepted',
        conflictMessage: 'This request is not ready to start navigation.',
        buildUpdate: (d) => {'status': 'enRoute'},
      );

  static Future<void> markArrived(String requestId, {required String ambulanceId}) =>
      _transitionRequest(
        requestId,
        precondition: (d) => d['ambulanceId'] == ambulanceId && d['status'] == 'enRoute',
        conflictMessage: 'This request is not currently en route.',
        buildUpdate: (d) => {'status': 'arrived'},
      );

  /// Retry-safe on purpose: calling this again after it already succeeded
  /// (e.g. a UI retry after a flaky network response) is a no-op rather than
  /// an error, because the precondition also accepts the already-`completed`
  /// case. The Cloud Function's trip record and ledger credit are separately
  /// guarded by deterministic doc IDs inside a transaction, so this can never
  /// double-credit even under a retry storm.
  static Future<void> complete(String requestId, {required String ambulanceId}) =>
      _transitionRequest(
        requestId,
        precondition: (d) =>
            d['ambulanceId'] == ambulanceId &&
            (d['status'] == 'arrived' || d['status'] == 'completed'),
        conflictMessage: 'This trip is not ready to be completed.',
        buildUpdate: (d) => {'status': 'completed'},
      );

  /// Cancelling a request this partner already accepted (as opposed to
  /// declining an unclaimed one — see [reject]).
  static Future<void> cancel(String requestId, {required String ambulanceId}) =>
      _transitionRequest(
        requestId,
        precondition: (d) =>
            d['ambulanceId'] == ambulanceId &&
            (d['status'] == 'accepted' || d['status'] == 'pending'),
        conflictMessage: 'This request can no longer be cancelled.',
        buildUpdate: (d) => {'status': 'cancelled'},
      );
}
