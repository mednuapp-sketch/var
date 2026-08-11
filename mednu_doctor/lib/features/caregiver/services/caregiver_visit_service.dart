import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

/// Thrown when a status-changing action can't proceed because the visit's
/// current state no longer matches what the caller expected — most commonly,
/// a second caregiver tried to claim a visit another one took a moment
/// earlier. Screens catch this specifically to show "someone else already
/// took this" instead of a generic error.
class CaregiverVisitConflictException implements Exception {
  final String message;
  const CaregiverVisitConflictException(this.message);
  @override
  String toString() => message;
}

/// All Firestore/Storage access for the Caregiver module lives here —
/// screens never touch `FirebaseFirestore`/`FirebaseStorage` directly. Every
/// write only ever touches `caregiver_visits` (plus its `tasks`/`notes`
/// subcollections) and Storage under `visit_photos/{visitId}/...`. Nothing
/// here writes to `service_requests` or `caregiver_transactions` — the Cloud
/// Function mirror (`functions/index.js`) is the sole writer of both on this
/// module's behalf.
class CaregiverVisitService {
  CaregiverVisitService._();

  static final _db = FirebaseFirestore.instance;
  static final _storage = FirebaseStorage.instance;

  static CollectionReference<Map<String, dynamic>> get _visits =>
      _db.collection('caregiver_visits');

  /// Visits not yet claimed by any caregiver — the shared, realtime
  /// assignment pool every caregiver partner sees.
  static Stream<QuerySnapshot<Map<String, dynamic>>> availableVisitsStream() {
    return _visits
        .where('caregiverId', isNull: true)
        .where('status', isEqualTo: 'scheduled')
        .orderBy('createdAt', descending: true)
        .limit(30)
        .snapshots();
  }

  /// Every visit this caregiver has claimed. Deliberately unordered (sorted
  /// client-side) so it needs no composite index beyond the two already
  /// declared — the same trade-off `LabBookingService.myAllBookingsStream`
  /// makes.
  static Stream<QuerySnapshot<Map<String, dynamic>>> myVisitsStream(String caregiverId) {
    return _visits.where('caregiverId', isEqualTo: caregiverId).snapshots();
  }

  static Stream<DocumentSnapshot<Map<String, dynamic>>> visitStream(String visitId) =>
      _visits.doc(visitId).snapshots();

  static Stream<QuerySnapshot<Map<String, dynamic>>> tasksStream(String visitId) =>
      _visits.doc(visitId).collection('tasks').orderBy('order').snapshots();

  static Stream<QuerySnapshot<Map<String, dynamic>>> notesStream(String visitId) =>
      _visits.doc(visitId).collection('notes').orderBy('createdAt').snapshots();

  // ── Status transitions ─────────────────────────────────────────────────
  //
  // Every transition reads the visit inside a Firestore transaction and
  // re-checks its *current* state before writing — a plain `.update()` would
  // let two caregivers both "successfully" claim the same visit, whereas a
  // transaction serializes them so the second one sees the first's result
  // and refuses. `firestore.rules`' `_validCaregiverTransition` enforces the
  // same graph server-side as a backstop.

  static Future<void> _transitionVisit(
    String visitId, {
    required bool Function(Map<String, dynamic> data) precondition,
    required String conflictMessage,
    required Map<String, dynamic> Function(Map<String, dynamic> data) buildUpdate,
  }) {
    final ref = _visits.doc(visitId);
    return _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) {
        throw const CaregiverVisitConflictException('This visit no longer exists.');
      }
      final data = snap.data()!;
      if (!precondition(data)) {
        throw CaregiverVisitConflictException(conflictMessage);
      }
      tx.update(ref, {
        ...buildUpdate(data),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  /// Claiming a visit does NOT change its status — a claimed visit stays
  /// `scheduled` until the caregiver actually checks in on the day. Only
  /// `caregiverId` moves, from null to the caller.
  static Future<void> claim(String visitId, String caregiverId) => _transitionVisit(
        visitId,
        precondition: (d) => d['caregiverId'] == null && d['status'] == 'scheduled',
        conflictMessage: 'This visit was already assigned to another caregiver.',
        buildUpdate: (d) => {'caregiverId': caregiverId},
      );

  /// Check-in also claims the visit if it wasn't claimed yet, so a caregiver
  /// arriving at a still-unassigned visit doesn't have to tap twice.
  static Future<void> checkIn(String visitId, String caregiverId) => _transitionVisit(
        visitId,
        precondition: (d) =>
            (d['caregiverId'] == null || d['caregiverId'] == caregiverId) &&
            d['status'] == 'scheduled',
        conflictMessage: 'This visit is no longer available to check in to.',
        buildUpdate: (d) => {'caregiverId': caregiverId, 'status': 'checkedIn'},
      );

  /// Retry-safe on purpose: re-running this after it already succeeded (a UI
  /// retry after a flaky response) is a no-op rather than an error. The
  /// Cloud Function's ledger credit is separately guarded by a deterministic
  /// doc ID inside a transaction, so this can never double-credit.
  static Future<void> complete(String visitId, {required String caregiverId}) =>
      _transitionVisit(
        visitId,
        precondition: (d) =>
            d['caregiverId'] == caregiverId &&
            (d['status'] == 'checkedIn' || d['status'] == 'completed'),
        conflictMessage: 'This visit is not ready to be completed.',
        buildUpdate: (d) => {'status': 'completed'},
      );

  static Future<void> cancel(String visitId, {required String caregiverId}) =>
      _transitionVisit(
        visitId,
        precondition: (d) => d['caregiverId'] == caregiverId && d['status'] == 'scheduled',
        conflictMessage: 'This visit can no longer be cancelled.',
        buildUpdate: (d) => {'status': 'cancelled'},
      );

  // ── Tasks ────────────────────────────────────────────────────────────────

  /// Toggles one checklist item. `firestore.rules` restricts this write to
  /// the `isDone` key alone, so the seeded wording can't be altered here even
  /// by accident.
  static Future<void> setTaskDone(String visitId, String taskId, bool isDone) {
    return _visits.doc(visitId).collection('tasks').doc(taskId).update({'isDone': isDone});
  }

  // ── Notes (append-only) ─────────────────────────────────────────────────

  static Future<void> addNote(String visitId, String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return Future.value();
    return _visits.doc(visitId).collection('notes').add({
      'text': trimmed,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  // ── Visit photos ────────────────────────────────────────────────────────

  /// Uploads [file] to `visit_photos/{visitId}/{timestamp}_{fileName}` and
  /// appends the resulting download URL to the visit's `photoUrls` array.
  /// `arrayUnion` (rather than a read-modify-write) means two photos
  /// uploading concurrently can't clobber each other.
  static Future<String> uploadPhoto({
    required String visitId,
    required File file,
  }) async {
    final fileName = file.path.split(Platform.pathSeparator).last;
    final storagePath =
        'visit_photos/$visitId/${DateTime.now().millisecondsSinceEpoch}_$fileName';

    final ref = _storage.ref(storagePath);
    await ref.putFile(file);
    final downloadUrl = await ref.getDownloadURL();

    await _visits.doc(visitId).update({
      'photoUrls': FieldValue.arrayUnion([downloadUrl]),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    return downloadUrl;
  }

  /// Removes a photo from the visit's list. The underlying Storage object is
  /// deleted too, best-effort — a failure there (e.g. it was already gone)
  /// must not stop the visit document from being corrected.
  static Future<void> removePhoto(String visitId, String downloadUrl) async {
    await _visits.doc(visitId).update({
      'photoUrls': FieldValue.arrayRemove([downloadUrl]),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    try {
      await _storage.refFromURL(downloadUrl).delete();
    } catch (_) {}
  }
}
