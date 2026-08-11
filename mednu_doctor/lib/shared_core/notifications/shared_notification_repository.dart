import '../../features/notifications/models/notification_model.dart';
import '../../features/notifications/services/notification_service.dart';
import '../models/app_role.dart';

/// Role-aware façade over the existing notification backend.
///
/// This does **not** change `NotificationService`, `NotificationModel`, or
/// the `doctor_notifications/{uid}/items` Firestore shape / FCM payload in
/// any way — it only routes to the existing doctor implementation for
/// `AppRole.doctor` and stays inert for roles whose notification channel
/// doesn't exist yet, so nothing breaks and nothing here silently reads a
/// collection that isn't there.
class SharedNotificationRepository {
  SharedNotificationRepository._();

  static Stream<List<NotificationModel>> streamFor(AppRole role, String uid) {
    switch (role) {
      case AppRole.doctor:
        return NotificationService.streamForDoctor(uid);
      case AppRole.ambulance:
      case AppRole.pharmacy:
      case AppRole.lab:
      case AppRole.caregiver:
      case AppRole.admin:
        // Backed by dedicated {role}_notifications collections once each
        // role's feature module ships. Until then, an empty stream is the
        // honest answer — there is nothing to read yet.
        return const Stream.empty();
    }
  }

  static Future<void> markRead(AppRole role, String uid, String notifId) {
    switch (role) {
      case AppRole.doctor:
        return NotificationService.markRead(uid, notifId);
      default:
        return Future.value();
    }
  }

  static Future<void> markAllRead(AppRole role, String uid) {
    switch (role) {
      case AppRole.doctor:
        return NotificationService.markAllRead(uid);
      default:
        return Future.value();
    }
  }
}
