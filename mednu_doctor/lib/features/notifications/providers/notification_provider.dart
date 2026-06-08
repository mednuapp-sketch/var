import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/services/doctor_auth_service.dart';
import '../models/notification_model.dart';
import '../services/notification_service.dart';

final notificationsProvider =
    StreamProvider.autoDispose<List<NotificationModel>>((ref) {
  final uid = DoctorAuthService.currentUid;
  if (uid == null) return const Stream.empty();
  return NotificationService.streamForDoctor(uid);
});

final unreadCountProvider = Provider.autoDispose<int>((ref) {
  return ref.watch(notificationsProvider).when(
        data: (list) => list.where((n) => !n.isRead).length,
        loading: () => 0,
        error: (_, __) => 0,
      );
});
