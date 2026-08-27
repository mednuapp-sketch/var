import 'package:cloud_firestore/cloud_firestore.dart';

/// Thrown when a status-changing action can't proceed because the session's
/// current state no longer matches what the caller expected — most commonly,
/// a second counsellor tried to claim a session another one took a moment
/// earlier.
class CounsellingSessionConflictException implements Exception {
  final String message;
  const CounsellingSessionConflictException(this.message);
  @override
  String toString() => message;
}

/// All Firestore access for the Counselling module lives here — screens
/// never touch `FirebaseFirestore` directly. Every write only ever touches
/// `counselling_sessions`. Nothing here writes to `service_requests` or
/// `counselling_transactions` — the Cloud Function mirror
/// (`functions/index.js`) is the sole writer of both on this module's behalf.
class CounsellingSessionService {
  CounsellingSessionService._();

  static final _db = FirebaseFirestore.instance;

  static CollectionReference<Map<String, dynamic>> get _sessions =>
      _db.collection('counselling_sessions');

  /// Sessions not yet claimed by any counsellor — the shared, realtime
  /// assignment pool every counsellor partner sees.
  static Stream<QuerySnapshot<Map<String, dynamic>>> availableSessionsStream() {
    return _sessions
        .where('counsellorId', isNull: true)
        .where('status', isEqualTo: 'pending')
        .orderBy('createdAt', descending: true)
        .limit(30)
        .snapshots();
  }

  /// Every session this counsellor has claimed. Deliberately unordered
  /// (sorted client-side) so it needs no extra composite index.
  static Stream<QuerySnapshot<Map<String, dynamic>>> mySessionsStream(String counsellorId) {
    return _sessions.where('counsellorId', isEqualTo: counsellorId).snapshots();
  }

  static Stream<DocumentSnapshot<Map<String, dynamic>>> sessionStream(String sessionId) =>
      _sessions.doc(sessionId).snapshots();

  // ── Status transitions ─────────────────────────────────────────────────

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
        throw const CounsellingSessionConflictException('This session no longer exists.');
      }
      final data = snap.data()!;
      if (!precondition(data)) {
        throw CounsellingSessionConflictException(conflictMessage);
      }
      tx.update(ref, {
        ...buildUpdate(data),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  /// Claiming a session sets both `counsellorId` and `status` in one write —
  /// a single-practitioner service with no separate check-in step.
  static Future<void> claim(String sessionId, String counsellorId) => _transitionSession(
        sessionId,
        precondition: (d) => d['counsellorId'] == null && d['status'] == 'pending',
        conflictMessage: 'This session was already taken by another counsellor.',
        buildUpdate: (d) => {'counsellorId': counsellorId, 'status': 'accepted'},
      );

  /// Declining an unclaimed session — same rule branch as [claim], just with
  /// a 'cancelled' result instead of 'accepted'.
  static Future<void> decline(String sessionId, String counsellorId) => _transitionSession(
        sessionId,
        precondition: (d) => d['counsellorId'] == null && d['status'] == 'pending',
        conflictMessage: 'This session is no longer available to decline.',
        buildUpdate: (d) => {'counsellorId': counsellorId, 'status': 'cancelled'},
      );

  static Future<void> start(String sessionId, {required String counsellorId}) =>
      _transitionSession(
        sessionId,
        precondition: (d) => d['counsellorId'] == counsellorId && d['status'] == 'accepted',
        conflictMessage: 'This session is not ready to be started.',
        buildUpdate: (d) => {'status': 'in_progress'},
      );

  /// Retry-safe on purpose: re-running this after it already succeeded is a
  /// no-op rather than an error. The Cloud Function's ledger credit is
  /// separately guarded by a deterministic doc ID inside a transaction.
  static Future<void> complete(String sessionId, {required String counsellorId}) =>
      _transitionSession(
        sessionId,
        precondition: (d) =>
            d['counsellorId'] == counsellorId &&
            (d['status'] == 'in_progress' || d['status'] == 'completed'),
        conflictMessage: 'This session is not ready to be completed.',
        buildUpdate: (d) => {'status': 'completed'},
      );

  static Future<void> cancel(String sessionId, {required String counsellorId}) =>
      _transitionSession(
        sessionId,
        precondition: (d) =>
            d['counsellorId'] == counsellorId &&
            (d['status'] == 'accepted' || d['status'] == 'pending'),
        conflictMessage: 'This session can no longer be cancelled.',
        buildUpdate: (d) => {'status': 'cancelled'},
      );
}
