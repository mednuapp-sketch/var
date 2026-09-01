import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

/// Thrown when a status-changing action can't proceed because the booking's
/// current state no longer matches what the caller expected — most
/// commonly, a second lab tried to accept a booking another lab already
/// claimed a moment earlier. Screens catch this specifically to show
/// "someone else already took this" instead of a generic error.
class LabBookingConflictException implements Exception {
  final String message;
  const LabBookingConflictException(this.message);
  @override
  String toString() => message;
}

/// All Firestore/Storage access for the Lab & Diagnostics module lives here
/// — screens never touch `FirebaseFirestore`/`FirebaseStorage` directly.
/// Every write only ever touches `diagnostic_bookings`, `diagnostic_reports`,
/// and Storage under `lab_reports/{bookingId}/...`. Nothing here writes to
/// `service_requests`, `appointments`, or `consultations` — the Cloud
/// Function mirror (`functions/index.js`) is the only writer of
/// `service_requests` on the Lab module's behalf.
class LabBookingService {
  LabBookingService._();

  static final _db = FirebaseFirestore.instance;
  static final _storage = FirebaseStorage.instance;

  static const int pageSize = 20;

  /// Bookings not yet claimed by any lab — the shared, realtime "available
  /// requests" queue every lab partner sees.
  static Stream<QuerySnapshot<Map<String, dynamic>>> availableBookingsStream() {
    return _db
        .collection('diagnostic_bookings')
        .where('labId', isNull: true)
        .where('status', isEqualTo: 'pending')
        .orderBy('createdAt', descending: true)
        .limit(30)
        .snapshots();
  }

  /// First page of this lab's own bookings, realtime. Further pages are
  /// fetched once (not streamed) via [fetchMoreMyBookings] — see
  /// `LabBookingsController` for how the two are combined.
  static Stream<QuerySnapshot<Map<String, dynamic>>> myBookingsFirstPageStream(
    String labId, {
    String? statusFilter,
  }) {
    Query<Map<String, dynamic>> q = _db
        .collection('diagnostic_bookings')
        .where('labId', isEqualTo: labId);
    if (statusFilter != null) q = q.where('status', isEqualTo: statusFilter);
    return q.orderBy('createdAt', descending: true).limit(pageSize).snapshots();
  }

  static Future<QuerySnapshot<Map<String, dynamic>>> fetchMoreMyBookings(
    String labId, {
    required DocumentSnapshot<Map<String, dynamic>> startAfter,
    String? statusFilter,
  }) {
    Query<Map<String, dynamic>> q = _db
        .collection('diagnostic_bookings')
        .where('labId', isEqualTo: labId);
    if (statusFilter != null) q = q.where('status', isEqualTo: statusFilter);
    return q
        .orderBy('createdAt', descending: true)
        .startAfterDocument(startAfter)
        .limit(pageSize)
        .get();
  }

  static Stream<DocumentSnapshot<Map<String, dynamic>>> bookingStream(String bookingId) =>
      _db.collection('diagnostic_bookings').doc(bookingId).snapshots();

  // ── Status transitions ─────────────────────────────────────────────────
  //
  // Every transition below reads the booking inside a Firestore transaction
  // and re-checks its *current* state before writing — this is what
  // actually prevents two labs from both successfully accepting the same
  // booking (a plain `.update()` would let both writes "succeed"
  // independently; a transaction serializes them so the second one sees
  // the first one's result and can refuse). The corresponding
  // `firestore.rules` update rule enforces the same invariants server-side
  // as a backstop against a client that skips this service entirely.

  static Future<void> _transitionBooking(
    String bookingId, {
    required bool Function(Map<String, dynamic> data) precondition,
    required String conflictMessage,
    required Map<String, dynamic> Function(Map<String, dynamic> data) buildUpdate,
  }) {
    final ref = _db.collection('diagnostic_bookings').doc(bookingId);
    return _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) {
        throw const LabBookingConflictException('This booking no longer exists.');
      }
      final data = snap.data()!;
      if (!precondition(data)) {
        throw LabBookingConflictException(conflictMessage);
      }
      tx.update(ref, {
        ...buildUpdate(data),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  static Future<void> acceptBooking(String bookingId, String labId) => _transitionBooking(
        bookingId,
        precondition: (d) => d['labId'] == null && d['status'] == 'pending',
        conflictMessage: 'This booking was already claimed by another lab.',
        buildUpdate: (d) => {'labId': labId, 'status': 'accepted'},
      );

  /// A booking made directly from this lab's own test catalogue arrives
  /// already pinned to it (`labId` set at creation — see
  /// `onDiagnosticServiceRequestCreated`'s `sourceLabId` handling), so there
  /// is nothing to claim. Unlike [acceptBooking], `labId` is already correct
  /// and must stay unchanged for this write to pass firestore.rules'
  /// "already-owning lab" branch.
  static Future<void> acceptAssignedBooking(String bookingId, String labId) => _transitionBooking(
        bookingId,
        precondition: (d) => d['labId'] == labId && d['status'] == 'pending',
        conflictMessage: 'This booking is no longer awaiting acceptance.',
        buildUpdate: (d) => {'status': 'accepted'},
      );

  static Future<void> rejectBooking(String bookingId, String labId) => _transitionBooking(
        bookingId,
        // A lab claiming-then-rejecting still needs labId set so the rule
        // that scopes updates to the owning lab keeps applying; an
        // unclaimed reject (declining without ever accepting) is also valid.
        precondition: (d) =>
            (d['labId'] == null || d['labId'] == labId) && d['status'] == 'pending',
        conflictMessage: 'This booking is no longer available to reject.',
        buildUpdate: (d) => {'labId': labId, 'status': 'rejected'},
      );

  static Future<void> assignTechnician(
    String bookingId, {
    required String labId,
    required String technicianName,
    required DateTime collectionTime,
  }) =>
      _transitionBooking(
        bookingId,
        precondition: (d) => d['labId'] == labId && d['status'] == 'accepted',
        conflictMessage: 'This booking is no longer ready for technician assignment.',
        buildUpdate: (d) => {
          'technicianName': technicianName,
          'collectionTime': Timestamp.fromDate(collectionTime),
          'status': 'technician_assigned',
        },
      );

  static Future<void> markSampleCollected(String bookingId, {required String labId}) =>
      _transitionBooking(
        bookingId,
        precondition: (d) => d['labId'] == labId && d['status'] == 'technician_assigned',
        conflictMessage: 'This booking is not awaiting sample collection.',
        buildUpdate: (d) => {'status': 'sample_collected'},
      );

  static Future<void> markProcessing(String bookingId, {required String labId}) =>
      _transitionBooking(
        bookingId,
        precondition: (d) => d['labId'] == labId && d['status'] == 'sample_collected',
        conflictMessage: 'This booking is not ready to start processing.',
        buildUpdate: (d) => {'status': 'processing'},
      );

  /// Retry-safe on purpose: calling this again after it already succeeded
  /// (e.g. a UI retry after a flaky network response) is a no-op rather
  /// than an error, because the precondition also accepts the case where
  /// the booking is already `completed` — the Cloud Function's own ledger
  /// credit is separately guarded against double-crediting either way (see
  /// `onDiagnosticBookingStatusChange`), so this never risks a duplicate
  /// earning even under a retry storm.
  static Future<void> markCompleted(String bookingId, {required String labId}) =>
      _transitionBooking(
        bookingId,
        precondition: (d) =>
            d['labId'] == labId &&
            (d['status'] == 'report_uploaded' || d['status'] == 'completed'),
        conflictMessage: 'This booking is not ready to be marked completed.',
        buildUpdate: (d) => {'status': 'completed'},
      );

  // ── Report upload (versioned) ────────────────────────────────────────────

  /// Uploads [file] (PDF or image) to
  /// `lab_reports/{bookingId}/{timestamp}_{fileName}`, then — in a single
  /// Firestore transaction — records a new, versioned `diagnostic_reports`
  /// doc and points the booking's `reportUrl`/`latestReportId` at it.
  ///
  /// A lab correcting a mistake re-uploads rather than the report simply
  /// vanishing and reappearing: every previous version stays in
  /// `diagnostic_reports` untouched (append-only — `firestore.rules` denies
  /// clients any update/delete there, so a version can never be edited or
  /// erased after the fact), and the booking's `latestReportId` pointer is
  /// what marks the current one — no `isLatest` flag to keep in sync on old
  /// docs, since that would require updating them (not allowed) rather than
  /// just writing a new one. Because the booking update and the new
  /// version's creation happen in the same transaction, there is no window
  /// where `reportUrl` and `latestReportId` could disagree — which is
  /// exactly what `auditDiagnosticReportConsistency` (Cloud Function)
  /// double-checks server-side against what the patient actually sees.
  static Future<String> uploadReport({
    required String bookingId,
    required String labId,
    required String patientId,
    required String patientName,
    required String testName,
    required File file,
  }) async {
    final fileName = file.path.split(Platform.pathSeparator).last;
    final dotIndex = fileName.lastIndexOf('.');
    final ext = dotIndex == -1 ? '' : fileName.substring(dotIndex).toLowerCase();
    final fileType = ext == '.pdf' ? 'pdf' : 'image';
    final storagePath =
        'lab_reports/$bookingId/${DateTime.now().millisecondsSinceEpoch}_$fileName';

    final ref = _storage.ref(storagePath);
    await ref.putFile(file);
    final downloadUrl = await ref.getDownloadURL();

    final bookingRef = _db.collection('diagnostic_bookings').doc(bookingId);
    final reportRef = _db.collection('diagnostic_reports').doc();

    await _db.runTransaction((tx) async {
      final bookingSnap = await tx.get(bookingRef);
      if (!bookingSnap.exists) {
        throw const LabBookingConflictException('This booking no longer exists.');
      }
      final booking = bookingSnap.data()!;
      if (booking['labId'] != labId) {
        throw const LabBookingConflictException('You no longer own this booking.');
      }

      final nextVersion = ((booking['reportVersion'] as num?) ?? 0).toInt() + 1;

      tx.set(reportRef, {
        'bookingId': bookingId,
        'patientId': patientId,
        'patientName': patientName,
        'labId': labId,
        'testName': testName,
        'fileUrl': downloadUrl,
        'fileName': fileName,
        'fileType': fileType,
        'version': nextVersion,
        'uploadedAt': FieldValue.serverTimestamp(),
      });

      // A correction uploaded after the booking was already marked
      // 'completed' shouldn't demote it back to 'report_uploaded' — that
      // would be a backward transition firestore.rules' _validLabTransition
      // rejects (by design, to keep the status graph one-directional for a
      // client-driven write). Same-status is always a valid transition, so
      // this simply keeps 'completed' as-is while still updating the report
      // pointer/version.
      final currentStatus = booking['status'] as String?;
      final nextStatus = currentStatus == 'completed' ? 'completed' : 'report_uploaded';

      tx.update(bookingRef, {
        'reportUrl': downloadUrl,
        'reportUploadedAt': FieldValue.serverTimestamp(),
        'reportVersion': nextVersion,
        'latestReportId': reportRef.id,
        'status': nextStatus,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });

    return downloadUrl;
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> reportsStream(String labId) {
    return _db
        .collection('diagnostic_reports')
        .where('labId', isEqualTo: labId)
        .orderBy('uploadedAt', descending: true)
        .limit(50)
        .snapshots();
  }

  // ── Dashboard metrics (single realtime query, computed client-side) ──────

  static Stream<QuerySnapshot<Map<String, dynamic>>> myAllBookingsStream(String labId) {
    return _db
        .collection('diagnostic_bookings')
        .where('labId', isEqualTo: labId)
        .snapshots();
  }
}
