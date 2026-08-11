import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../features/auth/services/doctor_auth_service.dart';
import '../../features/notifications/models/notification_model.dart';
import '../providers/role_providers.dart';
import 'shared_notification_repository.dart';

/// Role-aware replacement surface for the existing
/// `features/notifications/providers/notification_provider.dart`
/// `notificationsProvider` / `unreadCountProvider` pair.
///
/// The originals are untouched and keep powering the current dashboard
/// badge exactly as before. These `shared*` providers exist for the new app
/// shell (and future non-doctor roles) to depend on without hardcoding
/// "doctor" anywhere in shell code.
final sharedNotificationsProvider =
    StreamProvider.autoDispose<List<NotificationModel>>((ref) {
  final uid = DoctorAuthService.currentUid;
  if (uid == null) return const Stream.empty();
  final activeRole = ref.watch(roleEngineProvider).activeRole;
  return SharedNotificationRepository.streamFor(activeRole, uid);
});

final sharedUnreadCountProvider = Provider.autoDispose<int>((ref) {
  return ref.watch(sharedNotificationsProvider).when(
        data: (list) => list.where((n) => !n.isRead).length,
        loading: () => 0,
        error: (_, __) => 0,
      );
});

/// Marks a single notification read for the active role's channel.
Future<void> sharedMarkNotificationRead(WidgetRef ref, String notifId) {
  final uid = DoctorAuthService.currentUid;
  if (uid == null) return Future.value();
  final activeRole = ref.read(roleEngineProvider).activeRole;
  return SharedNotificationRepository.markRead(activeRole, uid, notifId);
}

/// Marks every notification read for the active role's channel.
Future<void> sharedMarkAllNotificationsRead(WidgetRef ref) {
  final uid = DoctorAuthService.currentUid;
  if (uid == null) return Future.value();
  final activeRole = ref.read(roleEngineProvider).activeRole;
  return SharedNotificationRepository.markAllRead(activeRole, uid);
}
