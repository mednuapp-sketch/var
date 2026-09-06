import 'dart:async';

import '../../features/notifications/models/notification_model.dart';
import '../../features/notifications/services/notification_service.dart';
import '../models/app_role.dart';

/// Role-aware façade over the existing notification backend.
///
/// This does **not** change `NotificationService`, `NotificationModel`, or
/// the `doctor_notifications/{uid}/items` Firestore shape / FCM payload in
/// any way — it only routes to the existing doctor implementation for
/// `AppRole.doctor` and to the existing `provider_notifications/{uid}/items`
/// collection (already written by the backend's `_sendProviderNotification`
/// helper) for every other role this app hosts.
class SharedNotificationRepository {
  SharedNotificationRepository._();

  static Stream<List<NotificationModel>> streamFor(AppRole role, String uid) {
    switch (role) {
      case AppRole.doctor:
        // A doctor account also receives settlement/earnings/approval/support
        // notifications through `provider_notifications` — the same backend
        // helper every partner role uses. Merge both collections so those
        // don't silently disappear from the doctor's own bell (they already
        // push and land in Firestore correctly; only the in-app list was
        // doctor_notifications-only before this).
        return _mergeByCreatedAt(
          NotificationService.streamForDoctor(uid),
          NotificationService.streamForProvider(uid),
        );
      case AppRole.ambulance:
      case AppRole.pharmacy:
      case AppRole.lab:
      case AppRole.caregiver:
      case AppRole.physiotherapist:
      case AppRole.counsellor:
      case AppRole.nutritionist:
      case AppRole.hospital:
      case AppRole.admin:
        return NotificationService.streamForProvider(uid);
    }
  }

  static Future<void> markRead(AppRole role, String uid, String notifId) {
    switch (role) {
      case AppRole.doctor:
        // The tapped notification may live in either collection now that
        // the doctor's bell merges both — try doctor_notifications first
        // and fall back to provider_notifications (Firestore `update()`
        // throws not-found rather than silently creating the doc).
        return NotificationService.markRead(uid, notifId).catchError(
          (_) => NotificationService.markProviderRead(uid, notifId),
        );
      default:
        return NotificationService.markProviderRead(uid, notifId);
    }
  }

  static Future<void> markAllRead(AppRole role, String uid) {
    switch (role) {
      case AppRole.doctor:
        return Future.wait([
          NotificationService.markAllRead(uid),
          NotificationService.markAllProviderRead(uid),
        ]);
      default:
        return NotificationService.markAllProviderRead(uid);
    }
  }

  /// Combines the latest snapshot of each stream into one list, keyed by
  /// notification id and sorted newest-first. Unlike a plain stream merge
  /// (which would just interleave whichever side last updated), this keeps
  /// both sides' most recent values live at once — the doctor's bell needs
  /// `doctor_notifications` and `provider_notifications` visible together,
  /// not just whichever collection changed most recently.
  static Stream<List<NotificationModel>> _mergeByCreatedAt(
    Stream<List<NotificationModel>> a,
    Stream<List<NotificationModel>> b,
  ) {
    late final StreamController<List<NotificationModel>> controller;
    StreamSubscription<List<NotificationModel>>? subA;
    StreamSubscription<List<NotificationModel>>? subB;
    List<NotificationModel>? latestA;
    List<NotificationModel>? latestB;

    void emit() {
      if (latestA == null && latestB == null) return;
      final byId = <String, NotificationModel>{};
      for (final n in latestA ?? const <NotificationModel>[]) {
        byId[n.id] = n;
      }
      for (final n in latestB ?? const <NotificationModel>[]) {
        byId[n.id] = n;
      }
      final merged = byId.values.toList()
        ..sort((x, y) => y.createdAt.compareTo(x.createdAt));
      controller.add(merged);
    }

    controller = StreamController<List<NotificationModel>>.broadcast(
      onListen: () {
        subA = a.listen((v) {
          latestA = v;
          emit();
        }, onError: controller.addError);
        subB = b.listen((v) {
          latestB = v;
          emit();
        }, onError: controller.addError);
      },
      onCancel: () async {
        await subA?.cancel();
        await subB?.cancel();
      },
    );
    return controller.stream;
  }
}
