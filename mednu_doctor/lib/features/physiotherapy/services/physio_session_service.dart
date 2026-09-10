import 'package:cloud_firestore/cloud_firestore.dart';

/// Thrown when a status-changing action can't proceed because the session's
/// current state no longer matches what the caller expected — most commonly,
/// a second physiotherapist tried to claim a session another one took a
/// moment earlier.
class PhysioSessionConflictException implements Exception {
  final String message;
  const PhysioSessionConflictException(this.message);
  @override
  String toString() => message;
}

/// All Firestore access for the Physiotherapy module lives here — screens
/// never touch `FirebaseFirestore` directly. Every write only ever touches
/// `physio_sessions`. Nothing here writes to `service_requests` or
/// `physio_transactions` — the Cloud Function mirror (`functions/index.js`)
/// is the sole writer of both on this module's behalf.
class PhysioSessionService {
  PhysioSessionService._();

  static final _db = FirebaseFirestore.instance;

  static CollectionReference<Map<String, dynamic>> get _sessions =>
      _db.collection('physio_sessions');

  /// Sessions not yet claimed by any physiotherapist — the shared, realtime
  /// assignment pool every physiotherapist partner sees.
  static Stream<QuerySnapshot<Map<String, dynamic>>> availableSessionsStream() {
    return _sessions
        .where('physiotherapistId', isNull: true)
        .where('status', isEqualTo: 'pending')
        .orderBy('createdAt', descending: true)
        .limit(30)
        .snapshots();
  }

  /// Every session this physiotherapist has claimed. Deliberately unordered
  /// (sorted client-side) so it needs no extra composite index.
  static Stream<QuerySnapshot<Map<String, dynamic>>> mySessionsStream(String physiotherapistId) {
    return _sessions.where('physiotherapistId', isEqualTo: physiotherapistId).snapshots();
  }

  static Stream<DocumentSnapshot<Map<String, dynamic>>> sessionStream(String sessionId) =>
      _sessions.doc(sessionId).snapshots();

  // ── Status transitions ─────────────────────────────────────────────────
  //
  // Every transition reads the session inside a Firestore transaction and
  // re-checks its *current* state before writing, exactly like
  // CaregiverVisitService — `firestore.rules`' `_validSessionTransition`
  // enforces the same graph server-side as a backstop.

  static Future<void> _transitionSession(
    String sessionId, {
    required bool Function(Map<String, dynamic> data) precondition,
    required String conflictMessage,
    required Map<String, dynamic> Function(Map<String, dynamic> data) buildUpdate,
  }) {
    final ref = _sessions.doc(sessionId);
    return _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) {
        throw const PhysioSessionConflictException('This session no longer exists.');
      }
      final data = snap.data()!;
      if (!precondition(data)) {
        throw PhysioSessionConflictException(conflictMessage);
      }
      tx.update(ref, {
        ...buildUpdate(data),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  /// Claiming a session sets both `physiotherapistId` and `status` in one
  /// write — unlike Caregiver, this is a single-practitioner service with no
  /// separate check-in step (matches Ambulance's claim shape). Also allows
  /// confirming a session already pinned to this physiotherapist (a patient
  /// booked straight from this physiotherapist's own profile) — normally
  /// that arrives already `status: 'accepted'` (see `_buildSessionDoc` in
  /// functions/index.js, which sets status 'accepted' immediately whenever
  /// a provider is pre-assigned) so this branch shouldn't be reachable in
  /// the happy path, but a bare `physiotherapistId == null` precondition
  /// here — unlike PharmacyOrderService.acceptOrder, which had exactly this
  /// gap for pharmacy's own pinned-but-still-'pending' orders — is a
  /// needless landmine if a pinned session is ever still 'pending' for any
  /// reason (a retried/duplicated write, a future change to that mirror,
  /// manual data repair, ...).
  static Future<void> claim(String sessionId, String physiotherapistId) => _transitionSession(
        sessionId,
        precondition: (d) =>
            (d['physiotherapistId'] == null || d['physiotherapistId'] == physiotherapistId) &&
            d['status'] == 'pending',
        conflictMessage: 'This session was already taken by another physiotherapist.',
        buildUpdate: (d) => {'physiotherapistId': physiotherapistId, 'status': 'accepted'},
      );

  /// Declining a session — same widened rule as [claim] (see its own doc
  /// comment), just with a 'cancelled' result instead of 'accepted'.
  static Future<void> decline(String sessionId, String physiotherapistId) => _transitionSession(
        sessionId,
        precondition: (d) =>
            (d['physiotherapistId'] == null || d['physiotherapistId'] == physiotherapistId) &&
            d['status'] == 'pending',
        conflictMessage: 'This session is no longer available to decline.',
        buildUpdate: (d) => {'physiotherapistId': physiotherapistId, 'status': 'cancelled'},
      );

  static Future<void> start(String sessionId, {required String physiotherapistId}) =>
      _transitionSession(
        sessionId,
        precondition: (d) =>
            d['physiotherapistId'] == physiotherapistId && d['status'] == 'accepted',
        conflictMessage: 'This session is not ready to be started.',
        buildUpdate: (d) => {'status': 'in_progress'},
      );

  /// Retry-safe on purpose: re-running this after it already succeeded is a
  /// no-op rather than an error. The Cloud Function's ledger credit is
  /// separately guarded by a deterministic doc ID inside a transaction.
  static Future<void> complete(String sessionId, {required String physiotherapistId}) =>
      _transitionSession(
        sessionId,
        precondition: (d) =>
            d['physiotherapistId'] == physiotherapistId &&
            (d['status'] == 'in_progress' || d['status'] == 'completed'),
        conflictMessage: 'This session is not ready to be completed.',
        buildUpdate: (d) => {'status': 'completed'},
      );

  static Future<void> cancel(String sessionId, {required String physiotherapistId}) =>
      _transitionSession(
        sessionId,
        precondition: (d) =>
            d['physiotherapistId'] == physiotherapistId &&
            (d['status'] == 'accepted' || d['status'] == 'pending'),
        conflictMessage: 'This session can no longer be cancelled.',
        buildUpdate: (d) => {'status': 'cancelled'},
      );
}
