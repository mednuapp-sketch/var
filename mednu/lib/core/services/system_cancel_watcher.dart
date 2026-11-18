import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// Server-side "blocked" cancellations: a booking is created, then a Cloud
/// Function immediately cancels it with `cancelledBy: 'system'` and one of
/// these reasons (functions/index.js). The patient must be told why instead of
/// seeing a success screen, and these docs never belong in My Services lists.
class SystemCancelWatcher {
  SystemCancelWatcher._();

  /// Reasons that hide the booking from My Services entirely. `slot_taken`
  /// is deliberately NOT here: it stays visible as a cancelled booking.
  static const Set<String> hiddenReasons = {
    'previous_trip_unpaid',
    'provider_not_accepting',
    'equipment_vendor_required',
  };

  /// Same wording as the push notifications sent by the functions.
  static String? messageFor(String? reason, {String? providerName}) {
    switch (reason) {
      case 'previous_trip_unpaid':
        return 'Please pay for your previous ambulance trip first.';
      case 'provider_not_accepting':
        final who = (providerName != null && providerName.trim().isNotEmpty)
            ? providerName.trim()
            : 'This provider';
        return "$who isn't accepting orders right now. Please pick another.";
      case 'equipment_vendor_required':
        return 'This equipment is no longer available. Please choose an item '
            'from an equipment vendor.';
    }
    return null;
  }

  /// True for a booking map that was blocked/cancelled by the system for one
  /// of the [hiddenReasons].
  static bool isHiddenBlocked(Map<String, dynamic> data) =>
      data['status'] == 'cancelled' &&
      hiddenReasons.contains(data['cancelReason']);

  /// Clear, dismissible explanation shown instead of a success view.
  static Future<void> showBlockedDialog(BuildContext context, String message,
      {String title = 'Booking not placed'}) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(title,
            style: const TextStyle(
                fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 17)),
        content: Text(message,
            style: const TextStyle(fontFamily: 'Poppins', fontSize: 14, height: 1.4)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK', style: TextStyle(fontFamily: 'Poppins')),
          ),
        ],
      ),
    );
  }

  /// Listens to `collection/docId` for [window] after creation. Calls
  /// [onBlocked] (once) with the user-facing text if the doc turns into a
  /// blocked system cancellation. The listener and timer are always released
  /// (after the window, after the first hit, or via [SystemCancelHandle.cancel]
  /// e.g. from dispose()).
  static SystemCancelHandle watch({
    required String collection,
    required String docId,
    required void Function(String message, String reason) onBlocked,
    String? providerName,
    Duration window = const Duration(seconds: 8),
  }) {
    final handle = SystemCancelHandle._();
    if (docId.isEmpty) return handle;
    handle._timer = Timer(window, handle.cancel);
    handle._sub = FirebaseFirestore.instance
        .collection(collection)
        .doc(docId)
        .snapshots()
        .listen((snap) {
      final d = snap.data();
      if (d == null) return;
      if (d['status'] != 'cancelled' || d['cancelledBy'] != 'system') return;
      final reason = d['cancelReason'];
      final msg = messageFor(reason is String ? reason : null,
          providerName: providerName);
      if (msg == null) return;
      handle.cancel();
      onBlocked(msg, reason as String);
    }, onError: (Object e) {
      debugPrint('SystemCancelWatcher: $e');
      handle.cancel();
    });
    return handle;
  }
}

class SystemCancelHandle {
  SystemCancelHandle._();
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sub;
  Timer? _timer;

  void cancel() {
    _timer?.cancel();
    _timer = null;
    _sub?.cancel();
    _sub = null;
  }
}
